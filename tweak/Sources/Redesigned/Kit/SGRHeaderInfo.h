// The text and the controls of a redesigned page's header, under its full bleed picture, the way the Music
// app (iOS 26.4) sets a playlist or an album: the title, the creator and the length centered, one row of
// shuffle, a white Play capsule and one more round button, and the description under the row.
//
// A page conceals what Spotify draws in its header and puts this in its place, so nothing of Spotify's lays
// it out. It keeps no state of its own: the page hands it the text it read (from Spotify's model or from
// Spotify's concealed labels) and Spotify's own controls to draw from and fire, on every pass, and it lays
// itself out again only when something it shows changed.
//
// Its content sits on its bottom edge with SGRHeaderInfoBottom under it, whatever height the page gives it,
// so the buttons stay just above the first track; what does not fit rises over the picture. The page's
// picture reaches SGRHeaderInfoTitleRise below the content's top, so the title and the creator sit on the
// bottom of its dissolve. A page whose header changes height under it (the album's, a point or more as Play
// turns to Pause, more with a taller font) pins the content's top instead (pinnedTop).
//
// Ownership: the page that adds it; it keeps only weak references to Spotify's controls.
// Threading: main thread only.
#import <UIKit/UIKit.h>

extern const CGFloat SGRHeaderInfoBottom;     // 14, under the content
extern const CGFloat SGRHeaderInfoTitleRise;  // 56, of the content over the picture

// Independent header layouts; an album's animated cover still fills the hero in Card mode.
// The legacy setting migrates into both choices before either is read. Unset, an album is Card and a playlist
// Full screen.
#define SGRKeyFullBleedCovers @"spotifyglass.redesign.fullBleedCovers"
#define SGRKeyFullCoverMigrated @"spotifyglass.redesign.fullBleedCovers.migrated"
#define SGRKeyAlbumFullCover @"spotifyglass.redesign.album.fullCover"
#define SGRKeyPlaylistFullCover @"spotifyglass.redesign.playlist.fullCover"
BOOL SGRPageFullCover(NSString *key);
// Read at launch. Play's glyph and word in the color the page hands over (on unless switched off), else the accent;
// the capsule stays white either way.
#define SGRKeyPlayInPageColour @"spotifyglass.redesign.playInPageColour"
// SGRScrolledTitle.x: Spotify's small navigation title on content pages. On by default, live.
#define SGRKeyPageTitleWhenScrolled @"spotifyglass.redesign.pageTitleWhenScrolled"
// The artist page's Play round, its glyph alone (off unless switched on): Artist/ArtistHeader.x sets roundPlay.
#define SGRKeyArtistRoundPlay @"spotifyglass.redesign.artist.roundPlay"
// Read at launch, off unless switched on, and only for round Play (roundPlay): the circle with its glyph cut out of it
// (SGRPlayCapsule's cutOut), white, or in the accent with SGRKeyAccentPlay. Every other Play keeps
// SGRKeyPlayInPageColour.
#define SGRKeyArtistCutOutPlay @"spotifyglass.redesign.artist.cutOutPlay"
#define SGRKeyAccentPlay @"spotifyglass.redesign.accentPlay"

@interface SGRHeaderInfo : UIView
// YES when anything shown changed. nil or empty hides that line.
- (BOOL)showTitle:(NSString *)title creator:(NSString *)creator length:(NSString *)length about:(NSString *)about;
// Spotify's own control behind the creator line -- the album's artist row, the playlist's collaborators
// button -- so a tap on the line opens whoever made it, and several of them open Spotify's own picker.
// The line keeps its color: it is the page's one piece of secondary text, not a link to be tinted. nil
// leaves it as text.
- (void)showCreatorLink:(UIView *)control;
// The picture of whoever made it -- the album's artist, the playlist's owner -- drawn round, a line high, before
// the creator's name, the two centered together, as Spotify's own facepile sat beside the name. `source` is the
// image view Spotify draws it in (SGRCreatorPicture), followed as Spotify fills it, so a picture that lands
// after the page has laid out still shows. With no picture in it, or nil, the name stands alone.
- (void)showCreatorPicture:(UIImageView *)source;
// The faces of everyone on the creator line, the album's artists (Album/AlbumHeader.x), instead of one picture: `sources`
// are the image views of Spotify's own line `parent` (SGRCreatorFaces), and the first three of them with a picture are
// drawn as circles a line's height and a point across (at most 22pt), 8pt before the name, each next one 0.85 of that
// on from the one before and cut 1.5pt clear around it, so they overlap as separate circles. They are followed as
// Spotify fills them, coalesced and drawn anew only when the pictures are other ones, each view's visibility under
// `parent` read again every time; while the views still shown have no picture at all the faces drawn for the same
// parent and name stay, and another parent or name, or none of the views shown, drops them. nil or empty draws
// the name alone, laid out as if there had never been a picture. Decorative: no element and no touch of their own, the
// line keeps its link. -showCreatorPicture:'s callers (the playlist's) never get them.
- (void)showCreatorFaces:(NSArray<UIImageView *> *)sources from:(UIView *)parent;
// For a trailing control that shows its state only as a word (the artist's Follow): SGRMirrorButton's
// readState and its two symbols. Set before the first -showShuffle:...; -trailingStateChanged redraws it.
@property (nonatomic, copy) BOOL (^trailingState)(BOOL *on);
@property (nonatomic, copy) NSString *trailingOffSymbol;
@property (nonatomic, copy) NSString *trailingOnSymbol;
- (void)trailingStateChanged;
// Spotify's controls, each drawn from and fired; nil hides that button. Play stays in the middle of the
// page whether the other two are there or not. Stacked, where the buttons shown would not fit either side of the capsule
// at its width (SGRPlayCapsule's sgr_width) with the usual gap, Play is a circle the row's height, its glyph alone.
// `trailingFallback` is drawn when Spotify's trailing control has no image to copy. `playColor` is the color of the capsule's glyph and word, taken while
// SGRKeyPlayInPageColour is on; off, they are the accent.
- (void)showShuffle:(UIView *)shuffle play:(UIView *)play trailing:(UIView *)trailing
   trailingFallback:(UIImage *)trailingFallback playColor:(UIColor *)playColor;
// A picture drawn in the title's place, such as an artist's logo; the title stays its spoken name. nil
// draws the title again.
- (void)showTitleImage:(UIImage *)image;
// The height the content wants at `width`, from the top of the title to the bottom of the description.
- (CGFloat)contentHeightForWidth:(CGFloat)width;
// Where the content starts, from the top; 0 keeps it on the bottom edge. Content that would then run past the
// bottom goes back on the bottom edge.
@property (nonatomic) CGFloat pinnedTop;
// The artist's name the Music app's way on iOS 26 (Artist/ArtistHeader.x): Large Title bold (34pt at the default size,
// capped with the rest at Extra Large), the name, the logo standing for it and the lines under it centered like the
// album's. NO is the album's and the playlist's centered Title 2.
@property (nonatomic) BOOL largeTitle;
// Play a circle 64pt across with its glyph alone, its word only what VoiceOver reads, in a 64pt row, and the buttons
// either side 44pt across, 20pt off it (the artist's, SGRKeyArtistRoundPlay). NO is the capsule in its 48pt row.
// Round, Play is cut out while SGRKeyArtistCutOutPlay is on. Set before the first -showShuffle:....
@property (nonatomic) BOOL roundPlay;
// On every step of `scroll` and after each of the info's own passes: what of the content has gone under the pinned
// top bar -- the window's top safe area and 44pt under it -- is clipped there, once it is half a point past it,
// fading in over the 14pt under the line rather than cut at it; the clip goes when nothing is under the bar. The
// album page always asks (nothing of its header ghosts under the bar), the playlist and artist pages with the scroll
// veil (SGRHeroVeil.h). nil stops following and takes the clip off. The mask is the info's own; one someone else
// set is left alone. The scroll view is held weakly.
- (void)clipUnderTopBarFollowing:(UIScrollView *)scroll;
// Kept for the page, which reads them back to tell whether a pass has anything new to hand over: the play color
// it last handed over, and whether it has found Spotify's buttons' row. The info itself never reads them.
@property (nonatomic, strong) UIColor *handedPlayColor;
@property (nonatomic) BOOL rowFound;
@end

// The image view of the leading face on Spotify's creator line `root` -- the playlist header's collaborators
// button, which carries a facepile, or the album header's artist row, which carries an Encore.ImageView: the
// square image view nearest the leading edge, so a badge after the name is not taken for it. nil when there is
// none yet.
UIImageView *SGRCreatorPicture(UIView *root);
// The image views of every face on Spotify's creator line `root`, picture or not yet, one per avatar: an avatar is the
// outermost square at least a face wide running up from an image view (the image view itself only when it is square;
// Spotify's may be wider than the avatar that clips it), and it counts when its leading edge is ahead of the line's name
// (so a badge after it is not one) and neither the image view nor its ancestors up to `root` are hidden or transparent.
// The name is the first label shown with text outside every avatar, its picture shown or hidden (an avatar's initial is
// not it). In the order they
// read, leading first. Empty when there is none, and when the line shows no name label to measure them against.
NSArray<UIImageView *> *SGRCreatorFaces(UIView *root);
