#import "Core/SGPrefs.h"
#import "AnimatedArtwork.h"

// A lock-screen mode can be selected by the star while playback is paused. On the
// first live enable, set up the owner on main and let it replay the current track.
static inline void SGLockArtworkStartWhen(BOOL (^wanted)(void), void (^start)(BOOL replay)) {
    // The first read can migrate the legacy switch and synchronously notify defaults
    // observers. Finish it before an observer can reenter the migration's dispatch_once.
    if (wanted()) {
        start(NO);
        return;
    }
    __block id token;
    void (^activate)(BOOL) = ^(BOOL replay) {
        if (!token || !wanted()) return;
        [NSNotificationCenter.defaultCenter removeObserver:token];
        token = nil;
        start(replay);
    };
    token = [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        SGPrefsChanged();
        if (wanted()) dispatch_async(dispatch_get_main_queue(), ^{ activate(YES); });
    }];
    activate(NO);
}
