// A live preview at the top of the redesign's page settings in Mod Settings (Playlists, Home, Search, Albums and
// Artists): a small mock of the Spotify page those settings change, drawn in plain views over local placeholder
// art, that changes with the page's switches as they are flipped, so the page shows what the restart will bring.
//
// The mock is a stack of parts from the top of the page down, with overlays over it (a tab bar, a menu, a sheet).
// A hidden part fades where it is and the parts under it move up into its room. The card draws from the page's own
// preference readers in two steps: `state` reads them into one value, and `apply` draws that value, showing or
// hiding parts and changing whatever else follows a setting (a header's layout, a card's look). While the card is in
// a window and in sight it reads `state` again whenever the defaults change, and draws only a value unlike the last
// one drawn, with the redesign's layout motion (SGRAnimate; at once under Reduce Motion). Out of sight a change is
// only noted, and read and drawn at once when the card is back in sight (SGRPagePreviewPage tells it as the page
// scrolls). Coming into a window it draws at once, from the top of the page. Nothing runs in between: no timer, and
// no observer while it has no window.
//
// The page is taller than the card: a change to a part below the card's foot scrolls the mock to it, as does one a
// page names with -revealPart: (a part that shows or hides is followed by itself), so a switch far down the
// settings is seen too.
//
// The mock's text grows with the reader's text size up to a cap, and the card grows with it; everything a part
// lays out is in multiples of `unit`.
//
// A part and an overlay lay out from the left. Right to left (the card's effectiveUserInterfaceLayoutDirection) the
// card mirrors them as the real pages are: every view in them moved to the other side of the view it sits in, the
// overlay itself to the other side of the page. Text keeps its own reading; a label sized wider than its text reads
// from the leading edge (natural alignment, or set by the part).
//
// VoiceOver reads the card as one element: the label it was made with, then the names (accessibilityLabel) of the
// parts and overlays shown, in order.
//
// SGRPagePreviewPage puts the card at the top of a page as the Lyrics page has its preview: in the table's
// header, scrolling with the rows, the page's note under it.
//
// Threading: main thread only.
#import <UIKit/UIKit.h>

@class SGModSection;
@class SGRPagePreview;
UIViewController *SGRPairedPreviewPage(NSString *title, SGRPagePreview *first, SGRPagePreview *second,
                                      NSArray<NSString *> *labels, NSString *note, NSArray<SGModSection *> *sections);

extern const CGFloat SGRPagePreviewMargin;   // 12, the mock page's side margin

// The tab the mock's tab bar shows as the one open.
typedef NS_ENUM(NSUInteger, SGRPreviewTab) {
    SGRPreviewTabHome,
    SGRPreviewTabSearch,
    SGRPreviewTabLibrary,
};

@interface SGRPagePreview : UIView
// `label` says which page the card previews, for VoiceOver.
- (instancetype)initWithLabel:(NSString *)label;
// The scale of the mock's text and of the sizes laid out around it: 1 at the default text size.
@property (nonatomic, readonly) CGFloat unit;
// The card's height, from its text size.
@property (nonatomic, readonly) CGFloat preferredHeight;
// The page's background, black unless set; the foot of the mock fades into it.
@property (nonatomic, strong) UIColor *fieldColor;
// A color washed over the top of the page and fading into the field (Home's page color), nil for none.
@property (nonatomic, strong) UIColor *topTint;
// The next part down. `layout` places the part's subviews for a width and returns the part's height.
- (UIView *)addPartWithLayout:(CGFloat (^)(UIView *part, CGFloat width, CGFloat unit))layout;
// Drawn over the parts: `layout` places the overlay's subviews and returns its frame for the size of the page.
- (UIView *)addOverlayWithLayout:(CGRect (^)(UIView *overlay, CGSize page, CGFloat unit))layout;
// A glass tab bar over the foot of the page, `tab` lit in the accent color; the page's content ends clear of it.
- (void)addTabBarShowing:(SGRPreviewTab)tab;
// For `apply`: whether a part or an overlay added above shows (a part taking its room in the stack). Every one is
// shown until told otherwise.
- (void)setPart:(UIView *)part shown:(BOOL)shown;
// For `apply`: the part has changed in some other way, and is scrolled into sight if it is out of it.
- (void)revealPart:(UIView *)part;
// Reads the settings, compared with isEqual: to the value last drawn.
@property (nonatomic, copy) id<NSObject> (^state)(void);
// Draws what `state` read on `card`, inside the change's animation; the parts are laid out again after it.
@property (nonatomic, copy) void (^apply)(SGRPagePreview *card, id state);
@end

// What a mock is drawn with. The placeholder art comes in a few colors, picked by index (wrapping round).
UIColor *SGRPreviewColor(NSUInteger index);        // a cover's color, as vivid as Spotify's category cards
UIImage *SGRPreviewArt(NSUInteger index);          // the placeholder art in that color
UIImageView *SGRPreviewCover(NSUInteger index);    // that art, filling its frame, corners continuous
UIView *SGRPreviewBar(UIColor *color);             // a capsule standing in for a line of text
UIView *SGRPreviewGlass(void);                     // the shape of a glass control or pill, corners continuous
UIView *SGRPreviewAvatar(void);                    // the account's picture at a page title's trailing edge
// A gradient through `colors`, from `start` to `end` in the unit square of its bounds.
UIView *SGRPreviewGradient(NSArray<UIColor *> *colors, CGPoint start, CGPoint end);
UIImageView *SGRPreviewSymbol(NSString *name, UIColor *tint);   // an SF Symbol fitted to its frame
UIImageView *SGRPreviewAddSymbol(UIView *view, NSString *name, UIColor *tint);   // the same, added to `view`
void SGRPreviewCenter(UIView *view, CGRect bounds, CGFloat side);  // a square of `side` in the middle of `bounds`
UILabel *SGRPreviewLabel(NSString *text, UIColor *color);       // one line, cut short with an ellipsis
UIFont *SGRPreviewFont(CGFloat size, UIFontWeight weight, CGFloat unit);
// Names joined into a list the way the mod's screens' language joins them ("A, B, and C"), for VoiceOver.
NSString *SGRPreviewList(NSArray<NSString *> *names);

// The parts the pages have in common.
//
// A page's large title at the leading edge and the avatar at the trailing one (Home, Search).
@interface SGRPreviewTitle : NSObject
@property (nonatomic, weak, readonly) UIView *part;   // the card keeps it
@property (nonatomic) BOOL inPill;     // the title on a glass pill with the filter menu's chevron (Home's look)
@property (nonatomic) BOOL hardEdge;   // a hairline under the row, the hard edge the page scrolls under
@end
SGRPreviewTitle *SGRPreviewAddTitle(SGRPagePreview *card, NSString *title);
// The title row's sizes in points at the default text size, times `unit` in a layout, for a page that draws a title
// row of its own (Library's, with its menu's glyph before the avatar): the room above the row, the row's height, the
// title's font size and the avatar's side.
extern const CGFloat SGRPreviewTitleTop, SGRPreviewTitleRowHeight, SGRPreviewTitleFontSize, SGRPreviewAvatarSide;

// The header of the playlist, album and artist pages (Kit/SGRHeaderInfo.h): the artwork in `cover`'s color full
// bleed at the top, dissolving into the page's field (which takes the cover's color), the title and two lines of
// detail centered under it, and the row of glass controls with the white Play between shuffle and `trailing`, in
// that order right to left too, as the real header keeps it. A glass badge of `badge` sits over the artwork's lower
// leading corner, hidden until its alpha is set.
@interface SGRPreviewHeader : NSObject
@property (nonatomic, weak, readonly) UIView *part;
@property (nonatomic, readonly) UIView *badge;
// The cover the artwork is drawn in, and the page's field and the artwork's dissolve take their color from.
@property (nonatomic) NSUInteger cover;
// A logo (an artist's wordmark) in place of the title's bar, the detail under it moved clear of it; NO until set.
@property (nonatomic) BOOL showsLogo;
// Defaults YES for existing callers (including the artist). NO draws the static square Card cover.
@property (nonatomic) BOOL fullCover;
// Only playlist previews have a face beside the creator and a description below the controls.
- (void)setCreatorLine:(BOOL)line picture:(BOOL)picture description:(BOOL)description;
@end
SGRPreviewHeader *SGRPreviewAddHeader(SGRPagePreview *card, NSUInteger cover, NSString *badge, NSString *trailing);

// A list of `count` tracks, with their covers from `firstCover` on or, without, their numbers; the first playing,
// its title in the accent color.
@interface SGRPreviewTracks : NSObject
@property (nonatomic, weak, readonly) UIView *part;
@property (nonatomic) BOOL showsArtists;                    // the artist line under each title; YES until set
@property (nonatomic, copy) NSArray<NSString *> *trailing;  // a word before each row's ⋯, nil for none
@end
SGRPreviewTracks *SGRPreviewAddTracks(SGRPagePreview *card, NSUInteger count, BOOL artwork, NSUInteger firstCover);

// A paragraph: `lines` lines of secondary text, the last cut short.
UIView *SGRPreviewAddParagraph(SGRPagePreview *card, NSUInteger lines);

// The back button and the ⋯ pinned over the top of the playlist, album and artist pages.
void SGRPreviewAddTopBar(SGRPagePreview *card);

// A menu open from the pinned ⋯: a row for each of `symbols`, with the word at the same place in `words` or a bar
// where there is none (NSNull, or past the end). A hidden row closes up.
@interface SGRPreviewMenu : NSObject
@property (nonatomic, weak, readonly) UIView *overlay;
- (void)setRow:(NSUInteger)row shown:(BOOL)shown;
- (void)setRow:(NSUInteger)row word:(NSString *)word;
@end
SGRPreviewMenu *SGRPreviewAddMenu(SGRPagePreview *card, NSArray<NSString *> *symbols, NSArray *words);

// A shelf: a heading (`heading`, or a bar standing in for one) over a row of tiles from `firstCover` on.
typedef NS_ENUM(NSUInteger, SGRPreviewTiles) {
    SGRPreviewTilesSquare,   // covers, a caption under each
    SGRPreviewTilesRound,    // artists' pictures, a caption under each
    SGRPreviewTilesWide,     // videos, a play glyph on each
    SGRPreviewTilesTall,     // portrait previews, a play glyph on each
};
UIView *SGRPreviewAddShelf(SGRPagePreview *card, NSString *heading, NSUInteger firstCover, SGRPreviewTiles tiles);

// A page of Mod Settings led by `card`, with `note` under it in place of the page's intro.
UIViewController *SGRPagePreviewPage(NSString *title, SGRPagePreview *card, NSString *note, NSArray<SGModSection *> *sections);
