// The album redesign: Spotify's album page kept, with its header, its track list and its controls, and laid
// out the way the Music app lays an album out -- the same page the playlist redesign gives a playlist, so
// the two read as one app.
//
// The album page is not the playlist's. It is built by the Creative Work Platform out of the element
// framework (trees/clean/album/01.txt: CreativeWorkPlatform.CreativeWorkTemplateView, a header element over
// one list), its header is a column of stack views rather than a plain block, and its play and shuffle
// float over the page instead of scrolling with the header. So none of Redesigned/Playlist/ is shared: only
// the Kit is, which is what keeps the look the same.
//
//     AlbumField.x     the artwork field behind the whole page, the artwork it is read from, the flags the
//                      screen forces
//     AlbumHeader.x    the header: the cover full bleed at the top dissolving into the field, and the Kit's
//                      SGRHeaderInfo over it -- title, artist, kind and date, shuffle, a white Play, add
//     AlbumRows.x      the track rows on the field with no surface of their own and a hairline between them,
//                      and no artist line where it only repeats the album's (AlbumCredits.m decides)
//     AlbumSections.x  everything under the tracks dropped but the album's own line and its copyright: no
//                      more by the artist, no videos, no concerts, no merch, no you might also like, each
//                      back once its switch is off
//     AlbumPlays.m     each track's plays from Listening stats, for the rows to show
//     AlbumPlaysPlace.m where they show: on the row, on its ⋯ sheet, or nowhere
//     AlbumPlaysMenu.x the plays as a line of information on a track's ⋯ sheet
//
// Every hook installs only while Redesigned UI is on (SGRedesignedUI); the native look's do not then.
// Threading: main thread only.
#import <UIKit/UIKit.h>

// Apple Music's animated cover at the top of an album; on until switched off (AlbumSettings.m).
#define SGRKeyAlbumMotion @"spotifyglass.redesign.album.motion"
// The picture-aware cover (AlbumHeader.x): with the Full screen cover, the page's color is read off what the cover is
// (Kit/SGRCoverRead.h) and the cover stays sharp down through the title, then blurs into that color. Off until
// switched on (AlbumSettings.m), read at launch.
#define SGRKeyAlbumAdaptiveCover @"spotifyglass.redesign.album.adaptiveCover"
// The artists' faces before their names under the album's title (AlbumHeader.x, Kit/SGRHeaderInfo.h's
// -showCreatorFaces:from:), up to three of the pictures Spotify's own artist line has; on until switched off
// (AlbumSettings.m), and a flip applies to the album pages open. Off, the line is the names alone.
#define SGRKeyAlbumArtistPicture @"spotifyglass.redesign.album.artistPicture"
UIViewController *SGRAlbumSettingsPage(void);

// AlbumSections.x. The sections under the tracks, one switch each, all dropped until switched off; the last
// is every section none of the others names.
#define SGRKeyAlbumHideMoreBy @"spotifyglass.redesign.album.hide.moreBy"
#define SGRKeyAlbumHideVideos @"spotifyglass.redesign.album.hide.videos"
#define SGRKeyAlbumHideConcerts @"spotifyglass.redesign.album.hide.concerts"
#define SGRKeyAlbumHideMerch @"spotifyglass.redesign.album.hide.merch"
#define SGRKeyAlbumHideYouMightLike @"spotifyglass.redesign.album.hide.youMightLike"
#define SGRKeyAlbumHideOther @"spotifyglass.redesign.album.hide.other"

// AlbumRows.x. A track row's artist line goes when it only repeats the album's artist, with the explicit badge
// moved up beside the title; on until switched off (AlbumSettings.m).
#define SGRKeyAlbumHideTrackArtists @"spotifyglass.redesign.album.hide.trackArtists"
#define SGRKeyAlbumTrackNumbers @"spotifyglass.redesign.album.trackNumbers"
// The album's artist as the header of the page `view` is on shows it, for the rows to compare theirs with. A
// change lays the page's track rows out again; the same artist again is a no-op.
void SGRAlbumSetArtist(UIView *view, NSString *artist);
void SGRAlbumMotionHeader(UIView *page, UIView *hero, NSString *albumKey, NSString *releaseID);
BOOL SGRAlbumMotionRowsAllowed(UIView *page);
// The first row can wake a pending search; only evaluating its answer consumes evidence.
void SGRAlbumWaitForMotionRow(UIView *page, BOOL evaluating, BOOL (^use)(NSString *artist, NSString *song));
// AlbumCredits.m. Whether a row's artist line says nothing the album's header does not: it is the album's
// artist, or the album's artist and the guests the title names after "feat.", "ft.", "featuring" or "with".
BOOL SGRCreditRepeatsAlbum(NSString *albumArtist, NSString *rowArtist, NSString *title);

// How many times each track was played (AlbumPlays.m counts them), shown where the Albums page says
// (AlbumSettings.m), read at launch: trailing on its row before ⋯ (AlbumRows.x), or as a line of information on the
// sheet its ⋯ opens (AlbumPlaysMenu.x), or nowhere. Stored under SGRKeyAlbumPlayCountsPlace as an
// SGRAlbumPlayCountsPlace; while that is unset, the switch it replaced decides: on (or unset) is in the row, off is
// off.
#define SGRKeyAlbumPlayCountsPlace @"spotifyglass.redesign.album.playCounts.place"
#define SGRKeyAlbumPlayCounts @"spotifyglass.redesign.album.playCounts"
#define SGRKeyAlbumPlayCountsSource @"spotifyglass.redesign.album.playCounts.source"
// 0 Your plays (default), 1 Spotify plays. Placement remains independent.
BOOL SGRAlbumUsesSpotifyCounts(void);
NSString *SGRAlbumSpotifyPlaysText(NSNumber *plays);
@class SGRAlbumCountPage;
void SGRAlbumPlaysMarkSpotifyMenu(NSString *trackURI, SGRAlbumCountPage *page);
typedef NS_ENUM(NSInteger, SGRAlbumPlayCountsPlace) {
    SGRAlbumPlayCountsOff,
    SGRAlbumPlayCountsInRow,
    SGRAlbumPlayCountsInMenu,
};
// AlbumPlaysPlace.m.
SGRAlbumPlayCountsPlace SGRAlbumPlayCountsWhere(void);
// AlbumPlaysMenu.x. A ⋯ of an album's track row sent its action: the sheet that opens next, at once, is that
// track's, `title` on the album `album`. Nil for either clears the mark.
void SGRAlbumPlaysMarkMenu(NSString *album, NSString *title);
// AlbumRows.x and AlbumPlaysMenu.x. "12 plays", the count in the locale's grouping; nil for none.
NSString *SGRAlbumPlaysText(NSUInteger plays);
// The album's title as the header of the page `view` is on shows it, for the rows to match their plays by. A
// change lays the page's track rows out again; the same title again is a no-op.
void SGRAlbumSetTitle(UIView *view, NSString *title);
// AlbumPlays.m. The plays in Listening stats of the track `title` on the album `album`, matched folded and
// trimmed; 0 for none, and until the log has been read. The first call starts reading it.
NSUInteger SGRAlbumPlayCount(NSString *album, NSString *title);
// Posted on the main thread, object nil, when the counts change: the log was read, grew, was imported into or
// erased.
extern NSNotificationName const SGRAlbumPlayCountsDidChangeNotification;

// The album page `view` is on, or nil: the CreativeWorkTemplateView that carries the header, the list and
// the two floating controls (trees/clean/album/01.txt:22).
UIView *SGRAlbumPageOf(UIView *view);

// AlbumField.x. The field belongs to the page `view` is on, found by walking up from it, so two album pages
// on the navigation stack keep a field each.
//
// The color the page's field is showing, SGRNeutralField() before one has been read: what the header's
// cover has to dissolve into for there to be no seam.
UIColor *SGRAlbumFieldColor(UIView *view);
// The cover of the page `view` is on, for its field to take its color from. The same image again is a no-op.
void SGRAlbumSetArtwork(UIView *view, UIImage *image);
// The color Spotify picked for the album, read off the wash it paints behind the header: the field shows it
// until the cover's own main color has been read, and not after.
void SGRAlbumSetSpotifyColor(UIView *view, UIColor *color);
// The color the picture-aware cover read off the cover (AlbumHeader.x), shown by the field instead of the cover's main
// color; nil goes back to that.
void SGRAlbumSetCoverColor(UIView *view, UIColor *color);
// The page comes in whole once its cover has been read (Kit/SGRField.h). Called from the album header's pass
// only, so a podcast's episode page, the same template with no cover for the field to read, is never held.
void SGRAlbumHoldPage(UIView *page);
