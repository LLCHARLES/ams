#import "Shared/AnimatedArtwork/SGLockArtworkStart.h"
#import "../harness-fail.h"

// Use the production migration, but deliver its defaults notification synchronously
// on every platform, including Foundation versions that normally coalesce the post.
void HarnessMigrateKey(NSString *from, NSString *to);
void SGMigrateKey(NSString *from, NSString *to) {
    HarnessMigrateKey(from, to);
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
}

int main(void) { @autoreleasepool {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults removeObjectForKey:SGKeyLockScreenArtwork];
    [defaults setBool:YES forKey:SGKeyLockScreenMotion];
    __block BOOL reading = NO, started = NO;
    SGLockArtworkStartWhen(^BOOL {
        if (reading) HARNESS_FAIL(@"observer reentered the unfinished artwork migration");
        reading = YES;
        BOOL wantsMotion = SGLockScreenArtwork() == SGLockArtworkMotion;
        reading = NO;
        return wantsMotion;
    }, ^(BOOL replay) { started = !replay; });
    if (!started || [defaults objectForKey:SGKeyLockScreenMotion] ||
        [defaults integerForKey:SGKeyLockScreenArtwork] != SGLockArtworkMotion)
        HARNESS_FAIL(@"the legacy moving artwork switch did not start motion at launch");
    [defaults removeObjectForKey:SGKeyLockScreenArtwork];
    puts("PASS legacy-only motion migrated and activated synchronously without reentry");
    return 0;
} }
