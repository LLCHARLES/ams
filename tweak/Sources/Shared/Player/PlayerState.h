// What Spotify's player is doing, read through one hook so no feature of the mod hooks the player a
// second time, and under either look: the state is data, not a screen.
//
// -[_TtC23NowPlaying_PlatformImpl28StatefulPlayerImplementation player:stateDidChange:]
// (objc-methods.txt:60654) is the now playing platform's own player observer, and until that has
// reported, an observer of the mod's added to the first SPTEsperantoPlayer the app adds one to
// (-[SPTEsperantoPlayer addPlayerObserver:], :35729).
//
// Threading: the player reports from several threads and everything here is moved onto the main one,
// so observers are called there.
#import <UIKit/UIKit.h>
#import "Headers/SPTPlayer.h"

// A URI Spotify types as id (NSURL or NSString) as a string; nil for anything else.
NSString *SGURIString(id uri);

// Upcoming tracks with a title and a nonnil string/URL URI, in order, including duplicates.
// Stops as soon as `limit` tracks qualify; pass NSUIntegerMax for the full list.
NSArray<SPTPlayerTrack *> *SGPlayerUpcomingTracks(SPTPlayerState *state, NSUInteger limit);
// Only the first future item, if it is a track with a nonempty URI different from current.
SPTPlayerTrack *SGPlayerUpNextIn(SPTPlayerState *state);

// Spotify's Repeat button's next mode: off, then the playlist or album, then the track, then off again.
// Sends the commands to `player` in that order and returns what the last one answered.
id SGPlayerAdvanceRepeat(id<SPTPlayer> player, SPTPlayerOptions *options);

// The first SPTEsperantoPlayer the app added an observer to, weak and nil until then. Unlike
// SGKaraokePlayer it is there under either look and with the lyrics features off, for the commands
// that only need a player (the keyboard's). Responds to SPTPlayer's own selectors.
id SGPlayerInstance(void);

@protocol SGPlayerStateObserver <NSObject>
// Called when the track, the context, paused, playing, loading or shuffle changed, not for position.
- (void)playerStateDidChange:(SPTPlayerState *)state;
@optional
// Every accepted report, including position-only updates. Called before the change callback.
- (void)playerStateDidReport:(SPTPlayerState *)state;
// Current/first-future identity changed. Also reports an empty/invalid next item.
- (void)playerUpNextDidChange:(SPTPlayerState *)state;
@end
// Observers are held weakly and need no removal.
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer);
// The last state reported, nil before the player has reported one.
SPTPlayerState *SGPlayerState(void);
// Main thread. NO also before Connect has reported its playback location.
BOOL SGPlayerPlaybackIsLocal(void);
// NO until Connect has reported a manager; an unknown location is not a remote session.
BOOL SGPlayerPlaybackIsRemote(void);
// Main thread, object/userInfo nil; emitted only when the local-playback fact changes.
FOUNDATION_EXPORT NSNotificationName const SGPlayerPlaybackLocationDidChangeNotification;
// The SPTEsperantoPlayer the mod observes, nil until the app has added its first observer.
id SGPlayer(void);
