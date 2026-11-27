// The mod's own settings, in Spotify's NSUserDefaults. Every key is declared by the feature that
// owns it, in that feature's header, and starts with "spotifyglass.": Reset all settings on the Mod
// page sweeps by that prefix and knows no key by name. The accessors here are what the hooks and the
// pages share.
#import <Foundation/Foundation.h>

// Set by the reset, after the sweep: an unset switch then reads off rather than the way the build
// came, so a reset is stock Spotify, for every switch there is and every one added later.
#define SGKeyStock @"spotifyglass.stock"
// Shared with Diagnostics so screen dumps omit the user's server URL.
#define SGKeySponsorBlockServer @"spotifyglass.sponsorblock.serverURL"
#define SGKeyLyricsOpenAIBaseURL @"spotifyglass.lyrics.openai.baseURL"
// Install-local authentication for the debug driver, never part of settings backups or reports.
#define SGKeyDriverToken @"spotifyglass.driver.token"
// Install-local rotation receipt, not branding: renaming it would rotate an existing token again.
#define SGKeyDriverTokenRotated @"vitrine.private.driver.token.rotated"
#define SGKeyDriverTokenLegacyRotation @"spotifyglass.driver.token.rotated"
// Credentials and their migration state stay on this install, out of backups and screen trees.
NSSet<NSString *> *SGPrivatePreferenceKeys(void);
BOOL SGPrivatePreferenceKey(NSString *key);

BOOL SGFlag(NSString *key, BOOL fallback);
BOOL SGEnabled(NSString *key);   // an unset switch is on
BOOL SGHidden(NSString *key);    // an unset switch is off
void SGSetEnabled(NSString *key, BOOL on);

// A setting picked from a list, stored as the index into it; the choice rows of
// Settings/SGModPage.h write these.
NSInteger SGInt(NSString *key, NSInteger fallback);
void SGSetInt(NSString *key, NSInteger value);

// The accessors keep what they read until the defaults change. An observer of NSUserDefaultsDidChangeNotification
// that reads them calls this first, as observers are not called in a set order.
void SGPrefsChanged(void);

// Overrides of Spotify's remote-config flags, stored under SGFlagOverridePrefix + flag key;
// nil keeps Spotify's value. Shared/Flags reads them, the All flags page and flag rows write them.
extern NSString *const SGFlagOverridePrefix;
id SGFlagOverride(NSString *key);
void SGSetFlagOverride(NSString *key, id value);

// Moves a stored setting to another key, once: nothing happens unless `from` is set and `to` is not.
// A feature that leaves Redesigned/ for Shared/ loses the ".redesign." from its keys this way, so the
// switch someone already flipped is still the one they get.
void SGMigrateKey(NSString *from, NSString *to);

// Posted on main by SGRestartSpotify just before it exits, which skips UIApplicationWillTerminateNotification.
// Whatever a feature holds in memory that termination would save goes to disk synchronously in its observer.
extern NSNotificationName const SGWillRestartNotification;
// SGRestartSpotify's last step before exit(0): posts SGWillRestartNotification on the calling thread.
// Declared so a harness can run it without the process exiting.
void SGRestartPrepareExit(void);
// Quits Spotify so the hooks read the switches afresh on the next launch; the writes reach cfprefsd first.
void SGRestartSpotify(void);
// Set immediately when a restart is requested, until process exit. Safe to read on any thread.
BOOL SGRestartPending(void);

// Apple Music's red, 0xRRGGBB, offered under either look's accent color.
#define SGAppleMusicRed 0xFA2D48
// Spotify's own green, the token either look's accent replaces.
#define SGSpotifyGreen 0x1ED760
