// The controls a redesigned page puts in the row under its hero, where the Music app has them: the Play
// capsule it draws instead of a disc, and a round button standing in for one of Spotify's own where that
// one cannot be brought into the row.
//
// Neither is a control of its own making. Each takes what it shows from a button of Spotify's -- the glyph
// it draws, the word beside it in the app's own language, whether it reads play or pause -- and a tap on it
// fires that button, so the action, the state and the accessibility stay Spotify's and only the drawing is
// the redesign's. A page that can move Spotify's button into its row moves it and needs neither.
//
// Ownership: whoever adds them; each keeps a weak reference to Spotify's control.
// Threading: main thread only.
#import <UIKit/UIKit.h>

// Spotify's own words for its play button and its shuffle button, from Spotify's strings bundle (SPTStrings.bundle's
// _i18n data assets, the same in 9.1.90 and 9.2.0), in the app's preferred languages and English: each of the keys
// AccessibilityPlay, AccessibilityPause, AccessibilityShufflePlay, ShuffleButtonOff, ShuffleButtonOn and
// ShuffleButtonOnSmartShuffle to the set of its words; a key Spotify has no word for is missing. Read once.
NSDictionary<NSString *, NSSet<NSString *> *> *SGRSpotifyControlWords(void);

// Whether Spotify's play button `button` (an Encore PlayButtonView) is playing, from the view's own state: the Swift
// stored property isPlaying, which the Objective-C runtime lists as a one-byte ivar (at 192 in 9.1.90 and 9.2.0), its
// offset read from the runtime. NO, with `playing` untouched, for any other view or where the property is gone.
BOOL SGRPlayButtonPlaying(UIView *button, BOOL *playing);

// A capsule the height of SGRActionHeight with a glyph and a word in it, on prominent glass: the one
// control of an action row that leads. `sgr_width` is the width it asks for, measured with the longest of Spotify's
// Play and Pause words and every word it has shown for its source, so it keeps one width as Play turns to Pause.
@interface SGRPlayCapsule : UIControl
// Spotify's play button, the one the capsule reads and fires. Set by -feedFrom:.
@property (nonatomic, weak, readonly) UIView *source;
// A solid capsule of this color instead of the prominent glass, the Music app's white Play (the playlist).
// nil, the default, is the glass. Set before the capsule is first laid out; another color later repaints it.
@property (nonatomic, copy) UIColor *fillColor;
// The glyph's and the word's color; nil is the accent.
@property (nonatomic, copy) UIColor *contentColor;
// A circle as wide as it is tall with the glyph alone in its middle; the word is then only its accessibility label.
@property (nonatomic) BOOL round;
// With a fillColor, the glyph and any word shown are cut out of the fill instead of painted on it, so whatever is
// behind the capsule shows through them (the artist's round Play, SGRKeyArtistCutOutPlay): the capsule's layer takes
// an alpha mask of its own (SGRCutOutMask), drawn again only when the shape, the glyph or the word changes, and
// dimmed with the source. NO, the default, paints them in contentColor; turned off, the mask goes.
@property (nonatomic) BOOL cutOut;
// Takes the glyph, the word and the language from `source`, and follows the glyph as Spotify swaps it
// (play becoming pause) without the header laying out again. Cheap to call again on every pass.
- (void)feedFrom:(UIView *)source;
- (CGFloat)sgr_width;
@end

// The alpha mask that cuts a button out of its fill, `view`'s bounds in size at `view`'s display scale: `shape` (in
// `view`'s bounds) filled as a capsule, a circle when it is square, with the image `glyph` shows taken out of it where
// and as the image view shows it, and the text `word` shows the same way. A glyph view without an image and a hidden
// or empty word take nothing out. Inline so the Artists page's preview (Artist/ArtistSettings.m), which links none of
// this file's classes, draws the same cut as the capsule.
static inline UIImage *SGRCutOutMask(UIView *view, CGRect shape, UIImageView *glyph, UILabel *word) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat formatForTraitCollection:view.traitCollection];
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [UIColor.blackColor setFill];
        [[UIBezierPath bezierPathWithRoundedRect:shape cornerRadius:MIN(shape.size.width, shape.size.height) / 2] fill];
        UIImage *image = glyph.image;
        CGSize size = image.size;
        if (image && size.width > 0 && size.height > 0) {
            CGRect frame = [glyph convertRect:glyph.bounds toView:view], drawn = frame;
            // At its own size or fitted, centered, as UIImageView draws those two modes; stretched over the view otherwise.
            CGFloat scale = glyph.contentMode == UIViewContentModeCenter ? 1
                          : glyph.contentMode == UIViewContentModeScaleAspectFit ? MIN(frame.size.width / size.width, frame.size.height / size.height)
                          : 0;
            if (scale > 0) {
                drawn.size = CGSizeMake(size.width * scale, size.height * scale);
                drawn.origin = CGPointMake(CGRectGetMidX(frame) - drawn.size.width / 2, CGRectGetMidY(frame) - drawn.size.height / 2);
            }
            [image drawInRect:drawn blendMode:kCGBlendModeDestinationOut alpha:1];
        }
        if (word && !word.hidden && word.text.length) {
            CGContextRef c = context.CGContext;
            CGContextSaveGState(c);
            CGContextSetBlendMode(c, kCGBlendModeDestinationOut);
            CGRect frame = [word convertRect:word.bounds toView:view];
            CGContextTranslateCTM(c, frame.origin.x, frame.origin.y);
            [word drawTextInRect:word.bounds];
            CGContextRestoreGState(c);
        }
    }];
}

// A round glass button SGRActionHeight across showing the glyph of one of Spotify's round buttons and
// firing it, for a control the row cannot reach: the album page's shuffle floats over the page rather
// than scrolling with its header, so it is left where it is, concealed, and this stands in for it.
@interface SGRMirrorButton : UIControl
@property (nonatomic, weak, readonly) UIView *source;
// Drawn, in white, when Spotify's button has no image view to copy (a glyph it draws itself).
@property (nonatomic, strong) UIImage *fallbackGlyph;
// The color to draw the mirrored glyph in, whatever color Spotify drew it. nil, the default, keeps
// Spotify's -- which is what a glyph that says something by its color needs (shuffle turns the accent
// color while it is on). Set it for a glyph whose color is only the weight Spotify gave the control it
// sat in: Encore bakes the color into the image it draws, so this re-renders the copy as a template.
@property (nonatomic, copy) UIColor *glyphColor;
// The color the glyph takes while Spotify's button is on, and glyphColor while it is off, for a button that
// says it is on with the small dot Encore puts under its glyph (shuffle: trees/continuous/1.txt, a 4pt round
// view, hidden while off). Spotify's own off gray read as a disabled button beside the white download
// (issue #65). A button with no such dot keeps Spotify's colors. nil, the default, reads no dot.
@property (nonatomic, copy) UIColor *onGlyphColor;
// For a button that shows its state only as a word in the app's language (the artist's Follow): YES with
// whether it is on once the state is known, from wherever the page reads it. The button then draws
// stateOffSymbol, or stateOnSymbol in the accent color, and nothing while it answers NO. Set before the
// first -feedFrom:; call -feedFrom: again when the state changes.
@property (nonatomic, copy) BOOL (^readState)(BOOL *on);
@property (nonatomic, copy) NSString *stateOffSymbol;
@property (nonatomic, copy) NSString *stateOnSymbol;
// Takes the glyph, its color and the label from `source`, and follows the glyph as Spotify swaps it
// (shuffle turning on). Cheap to call again on every pass.
//
// Spotify's download button (SGRDownload.h) is drawn by Lottie, with nothing to copy: for it the button
// draws the state Spotify reports instead -- the arrow, a ring filling up, the downloaded glyph -- and reads
// it again while it is on screen, twice a second while a download runs, since nothing Spotify does then
// lays out anything the page hears. So is the add-to button, drawn as a plus or, saved, a fixed 22pt disc in the
// accent color with a dark check, as downloaded is.
- (void)feedFrom:(UIView *)source;
@end

// The ⋯ every redesigned entity page pins to its top trailing corner, level with the back button: one
// button, one size, one place on the playlist, the album and the artist. It is added to `page` -- the
// page's own root view, outside anything that scrolls -- so it stays where it is however far the page is
// scrolled, which is what Spotify's own does not (the navigation bar's slot is emptied on the way down,
// trees/continuous/1.txt 2026-09-20, issue #57) and what a button in a scrolling header cannot. On a page laid out
// right to left the corner is the left one, opposite the mirrored back button, read from the page's own
// effectiveUserInterfaceLayoutDirection.
//
// `source` is Spotify's own ⋯, wherever the page keeps it; nil hides the button until one is found. Kept
// on `page` under `key` and cheap to call again on every pass.
SGRMirrorButton *SGRPinnedMore(UIView *page, const void *key, UIView *source);

// Download, pinned the same way right inside ⋯, the two drawn as one 88x44 glass capsule the way the navigation
// bar groups its buttons, each half keeping its own touch, press, glyph and accessibility; for the album and the
// playlist that has both save and download, whose action row keeps only shuffle, Play and add. `source` is
// Spotify's download button: its tap, its state and its progress are drawn as SGRMirrorButton draws a download.
// nil hides the button, and ⋯ is its own circle again. Kept on `page` under `key`, just under ⋯, and cheap to
// call again on every pass; call it after SGRPinnedMore.
SGRMirrorButton *SGRPinnedDownload(UIView *page, const void *key, UIView *source);

// A sheet opening within this long of a tap on a pinned ⋯ is that page's context menu.
static const NSTimeInterval SGRPinnedMoreWindow = 3;
// The page whose pinned ⋯ was tapped within that window, or nil: for a screen that puts rows of its own on
// Spotify's context menu sheet and has to know which page the sheet belongs to.
UIView *SGRPinnedMoreRecentPage(void);
// The pinned ⋯ itself, tapped within that window, or nil: what the redesign's system menu opens from
// (Redesigned/ContextMenu).
SGRMirrorButton *SGRPinnedMoreRecentButton(void);
// The redesign's system menu has taken the sheet a tap on the pinned ⋯ asked for: the button's claim ends there, so the
// next sheet in the window (a track row's ⋯) is not taken for the page's too. The page's claim stays for the window:
// the playlist's rows on that same sheet read it as the sheet lays out (SGRPinnedMoreRecentPage).
void SGRPinnedMoreTaken(void);
