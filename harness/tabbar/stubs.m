// What the harness does not compile: the accent hook (SGRAccent.x), the repaint hook (SGRRepaint.x), the
// tab bar's composition (Navbar.x) and Mod Settings. Spotify's order of tabs stays as the mock has it.
#import <UIKit/UIKit.h>

UIColor *SGRAccentColor(void) { return nil; }
__weak UIView *sgr_nowPlayingRoot = nil;
NSHashTable<UIView *> *sgr_nowPlayingPainted = nil;
__weak UIView *sgr_lyricsPageRoot = nil;
__weak UIView *sgr_playlistRoot = nil;
__weak UIView *sgr_albumRoot = nil;
__weak UIView *sgr_artistRoot = nil;

__weak UIView *sgHarnessLitTab = nil;
NSUInteger sgHarnessTabBarRefreshes = 0;
BOOL sgHarnessTabBarRefreshedOffMain = NO;

#ifndef HARNESS_COMPOSED
void SGRComposeTabBar(UIView *tabBar) {}
NSArray<UIView *> *SGRComposedTabItems(UIView *tabBar) { return nil; }

// With `split` among the launch words, Search is a split tab, which TabBar.x stands on a bar of its own;
// with `split2`, Create is one too; with `splitcreate`, Create alone.
BOOL SGRTabIsApart(UIView *item) {
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    BOOL two = [args containsObject:@"split2"], create = [args containsObject:@"splitcreate"];
    if (![args containsObject:@"split"] && !two && !create) return NO;
    for (UIView *sub in item.subviews) {
        if (![sub isKindOfClass:UILabel.class]) continue;
        NSString *text = ((UILabel *)sub).text;
        if ([text isEqualToString:@"Search"] && !create) return YES;
        if ([text isEqualToString:@"Create"] && (two || create)) return YES;
    }
    return NO;
}
// The tab the `lit` launch word sets by hand.
UIView *SGRNavbarLitTab(void) { return sgHarnessLitTab; }
void SGRNavbarForgetTab(void) {
    if (sgHarnessLitTab) NSLog(@"[harness] the lit tab forgotten");
    sgHarnessLitTab = nil;
}
// Navbar.x's lays out the bar SGRComposeTabBar last composed, and the stub above composes none, so it lays out
// nothing here: what the Tab bar page changes reaches the bar only through TabBar.x's own path (`navsettings`). It
// counts its calls and notes one off the main thread, for `symbols`' list read off it.
void SGRRefreshTabBar(void) {
    if (!NSThread.isMainThread) sgHarnessTabBarRefreshedOffMain = YES;
    sgHarnessTabBarRefreshes++;
}

#endif

// How often a hold opened Mod Settings, for `symbols hold`.
NSUInteger sgHarnessModSettingsOpens = 0;
void SGOpenModSettings(UIView *source) { sgHarnessModSettingsOpens++; }

// The full player never covers the mini player in this harness.
NSNotificationName const SGRPlayerVisibilityDidChangeNotification = @"SGRPlayerVisibilityDidChange";
CGRect SGRSettledPlayerRect(UIWindow *window) { return CGRectNull; }
BOOL SGRPlayerLandscapeCovers(UIWindow *window) { return NO; }
void SGRObserveVisibility(UIView *view, dispatch_block_t changed) {}

#import "../shared/placeholder-artwork.m"
#include "../shared/bar-title-notifications.inc"
NSString *SGRShownTitle(NSString *trackID, NSString *title, NSString *artist, NSString **shownArtist) {
    *shownArtist = artist;
    return title;
}
// Shared/Player/PlayerState.x, which NowPlayingBar.x reads titles from: no player has reported a state here, so the
// card's text is split by its line alone.
@class SPTPlayerState;
SPTPlayerState *SGPlayerState(void) { return nil; }
// The player the card's next button skips on (NowPlayingBar.x): none here, so a tap on it does nothing.
id SGPlayer(void) { return nil; }
// Shared/Player/PlayerState.x's observers and repeat, which NowPlayingBar.x reaches for: no player here, so nothing
// reports and the card's repeat does nothing.
void SGAddPlayerStateObserver(id observer) {}
id SGPlayerAdvanceRepeat(id player, id options) { return nil; }
// Redesigned/Kit's accent (SGRAccent.x), Spotify's green with no change of it, and the player's lyrics and queue
// (Redesigned/Player), which the card's buttons open: nothing opened.
NSNotificationName const SGRAccentDidChangeNotification = @"spotifyglass.redesign.accentDidChange";
NSInteger SGRAccentRGB(void) { return 0x1ED760; }
// SGRRestyle.m's lookup, which NowPlayingBar.x finds the glass tab bar with: the first view with the identifier, depth
// first, uncached (the harness's ids are exact).
UIView *SGRFindByIdentifier(UIView *root, NSString *identifier, const void *cacheKey) {
    if ([root.accessibilityIdentifier isEqualToString:identifier]) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = SGRFindByIdentifier(sub, identifier, cacheKey);
        if (found) return found;
    }
    return nil;
}
void SGRPlayerShowLyricsOnOpen(void) {}
void SGRPlayerShowQueue(UIView *from) {}
// Shared/Player/PlayerEvents.x, which TabBarMinimize.x listens to.
NSString *const SGPlayerTransitionNotification = @"spotifyglass.playerTransition";
