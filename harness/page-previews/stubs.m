// What the harness does not compile from the pages' parts. Top picks' row lives in HomeTopPicks.x, a file of hooks
// on Spotify's Home; this is the same row, by the same title and key. The rest are reached by the files that hold
// the readers the cards use (SGLastTrack.m, MotionSources.m, AlbumNotes.m, AlbumPlays.m) and never by a card: Spotify's
// player, the Listening stats log, the artwork downloads. Each fails the run if it is called, so a card that reached
// for the network or the player would be caught.
#import "../harness-fail.h"
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/AnimatedArtwork/SGMotionCatalog.h"
#import "Shared/AnimatedArtwork/SGMotionClip.h"
#import "Shared/ListeningStats/ListeningStats.h"
#import "Shared/ListeningStats/SGPlayLog.h"
#import "Shared/LocalFiles/LocalFiles.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerState.h"
#import "Redesigned/Kit/SGRRestyle.h"
#import "Redesigned/Home/Home.h"
#import "Redesigned/Album/Album.h"
#import "Redesigned/Album/AlbumNotes.h"

SGModRow *SGRHomeTopPicksRow(void) {
    return SGSwitchRow(SGL(@"settings.home.top_picks.title", @"Top picks"), nil, SGRKeyHomeTopPicks);
}

NSNotificationName const SGPlayLogDidChangeNotification = @"harness.playLogDidChange";

#define UNREACHED HARNESS_FAIL(@"%s reached from a preview card", __func__)

// SGLastTrack.m's constructor registers its recorder at load; with no player, it is never told anything.
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) {}
// The accent context observes the empty player at launch; no preview may fetch artwork.
SPTPlayerState *SGPlayerState(void) { return nil; }
NSString *SGURIString(id uri) { if (uri) { UNREACHED; } return nil; }
NSNotificationName const SGRNowPlayingArtworkDidChangeNotification = @"harness.artwork";
NSNotificationName const SGRFieldColorDidChangeNotification = @"harness.field";
UIImage *SGRNowPlayingArtwork(NSString **trackURI, NSString **identity) { UNREACHED; }
SGPlayLog *SGListeningLog(void) { UNREACHED; }
NSString *SGLocalFileCoverInURL(NSString *url) { UNREACHED; }
void SGSpclientHeaders(void (^use)(NSDictionary<NSString *, NSString *> *headers)) { UNREACHED; }
void SGMotionAlbumCover(NSString *artist, NSString *album, CGFloat pixels, void (^done)(NSURL *file)) { UNREACHED; }
void SGMotionAlbumNotes(NSString *artist, NSString *album, NSDictionary *edition, void (^done)(NSDictionary *notes)) { UNREACHED; }
NSData *SGMotionCanvasAsk(NSString *uri) { UNREACHED; }
NSString *SGMotionCanvasInReply(NSData *reply) { UNREACHED; }
void SGMotionFile(NSURL *remote, void (^done)(NSURL *file)) { UNREACHED; }
SGMotionTicket *SGMotionRequestFile(NSURL *remote, void (^done)(NSURL *file)) { UNREACHED; }
SGMotionTicket *SGMotionRequestSongCover(NSString *artist, NSString *album, NSString *song, NSString *albumURI, NSString *trackURI, CGFloat pixels, void (^done)(NSURL *file)) { UNREACHED; }
void SGRAlbumNotesChanged(UIView *page) { UNREACHED; }
UIView *SGRAlbumPageOf(UIView *view) { UNREACHED; }
UIView *SGRFindByIdentifier(UIView *root, NSString *identifier, const void *cacheKey) { UNREACHED; }
NSString *SGRFirstLabelText(UIView *root) { UNREACHED; }
