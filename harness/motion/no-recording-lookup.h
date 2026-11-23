#import "../harness-fail.h"
#import "Shared/Haptics/Haptics.h"

dispatch_block_t SGSpotifyISRCAllowConstrained(NSString *uri, NSUInteger tries, BOOL allow, void (^done)(NSString *, BOOL)) {
    HARNESS_FAIL(@"unexpected Spotify recording lookup: %@", uri);
}
