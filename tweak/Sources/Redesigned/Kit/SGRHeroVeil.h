// The scroll veil over a page's hero, the picture across the top of the album, playlist and artist pages
// (Album/AlbumHeader.x, Playlist/PlaylistHeader.x, Artist/ArtistHeader.x): as the page scrolls up the picture blurs
// and dims into the page's color and moves up slower than the page, and pulled down past the top it zooms. With it
// the page clips its SGRHeaderInfo under the top bar (-[SGRHeaderInfo clipUnderTopBarFollowing:]). Off unless switched on
// (SGRKeyHeroScrollVeil, read at launch); off, a hero makes no veil and draws as it always has.
//
// How far the page has scrolled, d, is measured rather than read off one scroll view: the hero's own upward
// displacement in the window since the page was last at rest, plus the page's scroll beyond it (what the list
// scrolls on once the hero has stopped moving), the scroll counted from the list's adjusted top inset.
//
// The blur is the redesign's plain Gaussian layer filter, the one the player's clip has behind the lyrics
// (Player/PlayerMotion.x), on the surface's layer (the hero's, or its square's); where the filter does not exist there is the dim alone. Every
// step draws with implicit animations off and does nothing when nothing it draws changed.
//
// Ownership: the hero that makes it; it keeps weak references to the hero, the scroll view and the info.
// Threading: main thread only.
#import <UIKit/UIKit.h>

#define SGRKeyHeroScrollVeil @"spotifyglass.redesign.hero.scrollVeil"
BOOL SGRHeroScrollVeilOn(void);

// The quintic smoothstep: 0 up to 0, 1 from 1, 6x^5 - 15x^4 + 10x^3 between.
CGFloat SGRHeroVeilRamp(CGFloat x);
// The blur's radius at d: 0 up to 60, 24 from 320, on the ramp between, to the nearest quarter point; none under a
// quarter point.
CGFloat SGRHeroVeilBlurRadius(CGFloat distance);
// The dim's alpha at d: 0 up to 80, 0.45 from 400, on the ramp between; none under 0.002.
CGFloat SGRHeroVeilDimAlpha(CGFloat distance);

// Where the art goes, in the hero's coordinates: scaled by `scale` about the hero's top edge, then moved down by
// `shift`. Pulled down `pull` (at least half a point, the hero at least a point tall) it is (h + pull) / h and
// -pull / 2; scrolled it is 0.25 x the hero's displacement - 0.75 x the scroll beyond it.
typedef struct {
    CGFloat scale, shift;
} SGRHeroArtPlace;
SGRHeroArtPlace SGRHeroVeilArtPlace(CGFloat pull, CGFloat height, CGFloat displacement, CGFloat beyond);

// The nearest scroll view above `view`, the one a page whose header scrolls with it scrolls in.
UIScrollView *SGRHeroVeilScrollAbove(UIView *view);

@interface SGRHeroVeil : NSObject
- (instancetype)initWithHero:(UIView *)hero;
// The hero's own sublayers that are its picture (the cover, an animated cover): placed by SGRHeroVeilArtPlace. Not
// the scrim or the dissolve, which stay where they are; none for a square cover, which stays where the page puts
// it. A layer dropped from it goes back to where it was laid out.
@property (nonatomic, copy) NSArray<CALayer *> *art;
// The page's color, the one its field shows and the hero dissolves into, drawn under the dim's alpha: a new one
// keeps the alpha it has.
@property (nonatomic, copy) UIColor *color;
// For a hero that stretches with a pull itself (the playlist's grows with its plane): no zoom on top of it.
@property (nonatomic) BOOL stretchesItself;
// The view the blur and the dim are drawn on, the hero unless set: a square cover (the album's own square, the
// playlist's left to Spotify), so the page around it is neither blurred nor dimmed. The dim is kept to its bounds
// on every step; a new surface takes over the blur and the dim as drawn.
@property (nonatomic, weak) UIView *surface;
// The scroll view the page scrolls with, followed on every change of its offset. The same one again is a no-op.
- (void)followScroll:(UIScrollView *)scroll;
// Measures and draws. The page calls it from its own passes as well; cheap when nothing changed.
- (void)update;
// Around the hero's -layoutSubviews: the art's frames are set with its placement taken off, then it goes back on.
- (void)artWillLayOut;
- (void)artDidLayOut;
@end
