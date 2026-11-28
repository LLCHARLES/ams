// Moving artwork for a track: its Canvas, or Apple Music's animated album cover where the album has one,
// and for the lock screen, failing both, the selected fallback background (SGFluidClip.h).
// SGMotionCatalog.m looks covers and logos up in Apple Music's catalog. SGMotionStore.m keeps every video
// as a local file, the form the system's lock screen takes.
#import <UIKit/UIKit.h>

// What the lock screen fills the screen with, stored as the index of SGLockArtwork. It took over from the
// Moving artwork switch, whose key is moved onto it once: on is Moving artwork, off is Off.
#define SGKeyLockScreenArtwork @"spotifyglass.lockscreen.artwork"
#define SGKeyLockScreenMotion @"spotifyglass.lockscreen.motion"
typedef NS_ENUM(NSInteger, SGLockArtwork) {
    SGLockArtworkOff = 0,
    SGLockArtworkMotion,   // the Canvas, else Apple Music's animated cover (LockScreenMotion.x)
    SGLockArtworkLyrics,   // a clip per line of lyrics (Shared/LockScreenLyrics/LyricsArtwork.x)
    SGLockArtworkEverySong,   // Moving artwork, else the cover over a moving blur of it (LockScreenMotion.x)
    // The lyrics over the moving artwork, else Lyrics: LockScreenMotion.x finds the clip, LyricsArtwork.x
    // draws the lines over it.
    SGLockArtworkMotionLyrics,
};
// Off below iOS 26, which has no animated artwork on the lock screen.
SGLockArtwork SGLockScreenArtwork(void);
// Under Moving artwork with lyrics, LyricsArtwork.x says whether the playing track has no synced lines (YES), so
// LockScreenMotion.x shows its moving artwork plain, as Moving artwork does, or has them (NO), so it takes it off
// for the lyrics' clips. Main queue.
void SGLockMotionShowPlain(BOOL plain);
static inline BOOL SGLockArtworkShowsLyrics(SGLockArtwork artwork) {
    return artwork == SGLockArtworkLyrics || artwork == SGLockArtworkMotionLyrics;
}
// How the lyrics are drawn, stored as the index of SGLyricsClipStyle (Still unless changed).
#define SGKeyLockScreenLyricsStyle @"spotifyglass.lockscreen.lyricsStyle"
// Where the lyrics sit, stored as the index of SGLyricsClipLayout (Left unless changed).
#define SGKeyLockScreenLyricsLayout @"spotifyglass.lockscreen.lyricsLayout"
// Size of the lyrics in every layout, stored as SGLyricsClipTextSize (Medium by default).
#define SGKeyLockScreenLyricsSize @"spotifyglass.lockscreen.lyricsSize"
// Off until switched on: Over the artwork blurs and darkens the whole artwork, moving artwork included, and the
// lines float over it, instead of a shade beside them over the cover kept sharp (SGLyricsClipDimmedArtwork).
#define SGKeyLockScreenDimArtwork @"spotifyglass.lockscreen.dimArtwork"
// Off until switched on: the line's translation, where the lyrics have one (or automatic translation makes
// one), shows smaller under the line. Read on each tick, so a change applies at once.
#define SGKeyLockScreenTranslation @"spotifyglass.lockscreen.translation"
#define SGKeyLockScreenKeepWidgetCover @"spotifyglass.lockscreen.keepWidgetCover"
// Off until switched on: the lock screen widget's star switches the choice between a choice with lyrics and
// one without (LockScreenStar.x), and takes the place of Spotify's like and dislike buttons. StarBack is the
// choice the star left, to go back to.
#define SGKeyLockScreenStar @"spotifyglass.lockscreen.star"
#define SGKeyLockScreenStarBack @"spotifyglass.lockscreen.star.back"
// Off until switched on: download in Low Data Mode too.
#define SGKeyMotionLowData @"spotifyglass.motion.lowdata"

// Apple Music's animated cover for an album, as a local file, or nil. `done` runs on the main queue.
// `pixels` is the width it is shown at; the closest stream at or above it is downloaded.
void SGMotionAlbumCover(NSString *artist, NSString *album, CGFloat pixels,
                        void (^done)(NSURL *file));

// The artist's logo from Apple Music, a transparent PNG `pixels` wide, or nil. Main queue.
void SGMotionArtistLogo(NSString *artist, CGFloat pixels, void (^done)(UIImage *logo));

// The width a full-screen clip is downloaded at: three quarters of the screen's pixels. A tall cover at the
// screen's full width ran to 29 MB a song; at this width it was 7 MB and looks the same in motion.
CGFloat SGMotionPixels(void);

// Apple Music's catalog songs with this ISRC, each with its isrc, durationInMillis and hasHaptics, or nil
// when the catalog could not be asked. Kept for the launch. Main queue.
void SGMotionSongsWithISRC(NSString *isrc, void (^done)(NSArray *songs));

// Where moving artwork comes from (MotionSources.m): the keys that are on, in the order they are asked,
// Spotify's Canvas then Apple Music's animated cover unless the user changed it.
#define SGKeyMotionSources @"spotifyglass.motion.sources"
NSArray<NSString *> *SGMotionSourceOrder(void);
BOOL SGMotionAppleMusicOn(void);
// The redesign moves a track's canvas.* metadata keys under this prefix, so Spotify's player makes no Canvas cell.
#define SGMotionHiddenCanvas @"spotifyglass."
// The track's Canvas video as its metadata names it (canvas.url, of a canvas.type that is a video, under either
// name), or nil.
NSURL *SGMotionCanvasIn(NSDictionary *metadata);
// The first clip the order finds for the track `uri`, as a local file, or nil, and the key of the source it
// came from. `canvas` is the track's Canvas video, nil when its metadata names none, and then Spotify's
// Canvas service is asked for it. Main queue.
void SGMotionClipFor(NSString *uri, NSURL *canvas, NSString *artist, NSString *album, CGFloat pixels,
                     void (^done)(NSURL *file, NSString *source));

// Main queue consumer handle. Explicit cancellation suppresses completion; dropping the handle
// alone preserves the completion-only API's lifetime. Other consumers keep their shared transfer.
@interface SGMotionTicket : NSObject
- (void)cancel;
@end
SGMotionTicket *SGMotionRequestFile(NSURL *remote, void (^done)(NSURL *file));
SGMotionTicket *SGMotionRequestAlbumCover(NSString *artist, NSString *album, CGFloat pixels, void (^done)(NSURL *file));
SGMotionTicket *SGMotionRequestClip(NSString *uri, NSURL *canvas, NSString *artist, NSString *album, CGFloat pixels,
                                   void (^done)(NSURL *file, NSString *source));
// When the artist credit is a song's, pass that song's full title as evidence.
// An album page can use one of its own rows; never use an unrelated playing track.
SGMotionTicket *SGMotionRequestSongCover(NSString *artist, NSString *album, NSString *song, NSString *albumURI, NSString *trackURI, CGFloat pixels,
                                       void (^done)(NSURL *file));
// One title search. The page may try distinct rows against the retained records locally until
// one returns YES (its file is then requested). A nil `found` file signals no candidate
// in the title search, not an identified release without video or a transfer failure.
typedef BOOL (^SGMotionRowMatch)(NSString *artist, NSString *song);
void SGMotionAlbumRowMatcher(NSString *albumArtist, NSString *album, NSString *albumURI, CGFloat pixels, void (^ready)(SGMotionRowMatch match), void (^found)(NSURL *file));
// Main queue. A page may use rows only when the header did not identify a release.
void SGMotionPageAlbumCover(NSString *artist, NSString *album, NSString *albumURI, CGFloat pixels, void (^done)(NSURL *file, BOOL identified));
// Only a confirmed miss permits an unrestricted title search. A known still edition permits a year-bound one.
typedef NS_ENUM(NSInteger, SGMotionIdentifierOutcome) {
    SGMotionIdentifierUnavailable, SGMotionIdentifierMiss, SGMotionIdentifierStill, SGMotionIdentifierClip, SGMotionIdentifierAmbiguous,
    SGMotionIdentifierKnownTitle
};
void SGMotionPageIdentifierCover(NSString *albumURI, NSString *artist, NSString *album, CGFloat pixels, void (^done)(NSURL *file, SGMotionIdentifierOutcome outcome));
// After the identifiers named a still edition: the album by its title among Apple's releases of the album's year on
// Spotify (within a year), so another of the same name and another year cannot stand in; nil without a year or a clip.
void SGMotionPageStillEditionCover(NSString *albumURI, NSString *artist, NSString *album, CGFloat pixels, void (^done)(NSURL *file));
SGMotionTicket *SGMotionRequestSongClip(NSString *uri, NSURL *canvas, NSString *artist, NSString *album, NSString *song,
                                      CGFloat pixels, void (^done)(NSURL *file, NSString *source));
SGMotionTicket *SGMotionRequestAlbumSongClip(NSString *uri, NSURL *canvas, NSString *artist, NSString *album, NSString *song,
                                           NSString *albumURI, CGFloat pixels, void (^done)(NSURL *file, NSString *source));

// Follows the player for one user of moving artwork, the lock screen or the redesign's player
// (SGMotionFollower.m). Each track's sources are walked once, and again when its Canvas turns up in a later
// state, as it does on a skip, where Spotify reports the track before its extended metadata, unless the clip
// showing came from a source above Canvas. `begin` runs as a walk starts, to take the last clip off, and
// says whether to walk at all; `found` gets the walk's clip, nil for none, and never runs for a walk a newer
// one overtook. The next track's clip follows queue changes independently of the current walk. Main queue.
@class SPTPlayerState;
@interface SGMotionFollower : NSObject
- (instancetype)initWithBegin:(BOOL (^)(NSString *uri, SPTPlayerState *state))begin
                        found:(void (^)(NSString *uri, NSURL *file))found;
// The track is walked again from the player's last state: a setting it depends on changed.
- (void)restart;
@end
// The row that opens the ordered list, for the Player page and the lock screen's.
@class SGModRow;
SGModRow *SGMotionSourcesRow(void);

// Any remote video (a Canvas) as a local file, or nil. Main queue.
// Retain the returned URL while consuming it: the store excludes retained handoffs from eviction.
void SGMotionFile(NSURL *remote, void (^done)(NSURL *file));
// Where a video the mod makes itself is kept under `key`, among the downloads, which are kept to the
// newest few. Pure filename derivation; does not access the filesystem. Any thread.
NSURL *SGMotionMadeFile(NSString *key);
// Serial store queue: checks for an existing file, creates/trims the folder, then writes if needed.
// Both blocks run off main on that queue. done reports whether the file is ready.
// The supplied URL pins a ready file until its last consumer releases that URL.
void SGMotionMakeFile(NSURL *file, BOOL (^write)(void), void (^done)(BOOL));

// The clips the store keeps on disk: their bytes (`done` on main), and removal of every one no consumer holds. Removal
// is main queue; it cancels the downloads in flight, whose consumers get nil, and `done(complete)` on main is NO
// when a clip could not be removed.
void SGMotionStoreBytes(void (^done)(uint64_t bytes));
void SGMotionStoreClear(void (^done)(BOOL complete));

// Everything downloaded for covers and artist photos that Retrine can fetch again (SGMotionCatalog.m): the store's
// clips and the catalog's answers, in memory and on disk. `done` runs on main. Clearing is main queue; `complete` is NO
// when something could not be removed. Lookups and downloads started before a clear leave nothing behind after it.
void SGMotionCacheBytes(void (^done)(uint64_t bytes));
void SGMotionCacheClear(void (^done)(BOOL complete));

// The first frame of a local video. Main queue.
void SGMotionPoster(NSURL *file, void (^done)(UIImage *poster));

// Settings: what the lock screen shows and the lyrics' style; below iOS 26 the one row
// SGLockScreenArtworkNeedsRow, which says the setting needs iOS 26 and, tapped, why.
NSArray *SGLockScreenMotionRows(void);
SGModRow *SGLockScreenArtworkNeedsRow(void);
// Mod > Storage: downloaded covers and artist photos, cleared only after confirmation.
SGModRow *SGArtworkCacheRow(void);

// Pure steps, for the harness.
NSString *SGMotionNameKey(NSString *name);
NSString *SGMotionSearchName(NSString *name);
NSString *SGMotionStreamIn(NSString *master, CGFloat pixels);
NSString *SGMotionWholeFileIn(NSString *media);
