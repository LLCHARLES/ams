// A line of lyrics as a short video for the lock screen's full-screen artwork (LyricsArtwork.x): the
// line, its translation smaller under it when there is one, and the next one dimmed, over the cover blurred
// or over the moving artwork; or, in Messages and Vinyl, a whole picture of the layout's own. Core Graphics,
// Core Text, Core Image and AVFoundation, and the platform's font descriptor for Vinyl's serif, so
// harness/lyrics-clip renders the same files on the Mac.
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SGLyricsClipStyle) {
    SGLyricsClipStill = 0,   // one frame, held
    SGLyricsClipAnimated,    // the cover breathes behind the words, in a loop; a scene's one frame is held as long
};

typedef NS_ENUM(NSInteger, SGLyricsClipTextSize) {
    SGLyricsClipTextSmall = 0,
    SGLyricsClipTextMedium,
    SGLyricsClipTextLarge,
};

static inline SGLyricsClipTextSize SGLyricsClipNormalizedTextSize(NSInteger value) {
    return value >= SGLyricsClipTextSmall && value <= SGLyricsClipTextLarge ? (SGLyricsClipTextSize)value : SGLyricsClipTextMedium;
}

// Where the words sit. Every layout keeps them between the clock and the media controls: a block too tall even
// at the smallest size lets go of the line sung last, then the next, then the translation, and last ends the line
// in an ellipsis after as many whole lines as fit. Stored by index (SGKeyLockScreenLyricsLayout): new ones go last.
typedef NS_ENUM(NSInteger, SGLyricsClipLayout) {
    SGLyricsClipLeft = 0,    // left-aligned, the next line (and over moving artwork the one sung last) dimmed beside it
    SGLyricsClipCentered,    // the same, each line centred
    SGLyricsClipPoster,      // the line alone, larger and heavy, left-aligned, its translation under it; at a rest the next
                             // line alone in its place, dimmed
    SGLyricsClipMessages,    // a chat on black: the line sung last in a grey bubble, the line in a blue one on the other
                             // side, and while a next line is coming a grey bubble of three dots
    SGLyricsClipVinyl,       // a record with the cover as its label, the line in italic serif under it and the next one dimmed
    SGLyricsClipOverArtwork, // sharp cover, previous/current/translation over a feathered local scrim; dimmed (the
                             // backdrop SGLyricsClipDimmedArtwork makes, or over moving artwork) the whole picture
                             // blurred and darkened evenly instead, with no scrim
};

// Messages and Vinyl paint the whole picture: no backdrop, no translation, never over moving artwork.
static inline BOOL SGLyricsClipIsScene(SGLyricsClipLayout layout) {
    return layout == SGLyricsClipMessages || layout == SGLyricsClipVinyl;
}

// An exact 3:4 size no wider than `pixels` (minimum 48), both sides a multiple of 16 for the encoder.
CGSize SGLyricsClipSize(CGFloat pixels);
// The lock screen's default background (the cover blurred, 45% darkened), through the shared CPU renderer;
// a dark field for NULL.
// Callers with a preference snapshot use SGLyricsBackgroundCreate directly.
CGImageRef SGLyricsClipBackdrop(CGImageRef cover, CGSize size) CF_RETURNS_RETAINED;
// Over the artwork dimmed whole: the cover blurred and darkened evenly through the shared renderer, darkened by as
// much as its brightest pixel needs for the lines' contrast over it, so a bright cover is darkened more.
CGImageRef SGLyricsClipDimmedArtwork(CGImageRef cover, CGSize size) CF_RETURNS_RETAINED;
// The clip's first frame, for the lock screen's preview image. Any of the words may be nil; a translation shows
// smaller under the line, and only with it. `backdrop` is behind the words of Left, Centered and Poster, which
// leave out `cover` and `previous`. Scenes (SGLyricsClipIsScene) leave out `backdrop`, which may be NULL for them,
// and the translation: Messages draws `previous`, Vinyl `cover` (a plain label for NULL).
// OverArtwork keeps `previous` above the line instead of `next`, over `backdrop` with no scrim when it is given
// (SGLyricsClipDimmedArtwork), else over `cover` sharp under a local scrim.
CGImageRef SGLyricsClipFrameWithLayout(CGImageRef backdrop, CGImageRef cover, NSString *previous, NSString *line,
                                       NSString *translation, NSString *next, CGSize size, SGLyricsClipLayout layout) CF_RETURNS_RETAINED;
CGImageRef SGLyricsClipFrameWithTextSize(CGImageRef backdrop, CGImageRef cover, NSString *previous, NSString *line,
                                       NSString *translation, NSString *next, CGSize size, SGLyricsClipLayout layout, SGLyricsClipTextSize textSize) CF_RETURNS_RETAINED;
// Writes H.264 on a worker, replacing `file` only after completion. `current`, if supplied, is
// checked between encoder frames; NO cancels an obsolete render without publishing it.
BOOL SGLyricsClipWriteWithLayout(NSURL *file, CGImageRef backdrop, CGImageRef cover, NSString *previous, NSString *line,
                                 NSString *translation, NSString *next, CGSize size, SGLyricsClipStyle style,
                                 SGLyricsClipLayout layout, BOOL (^current)(void));
BOOL SGLyricsClipWriteWithTextSize(NSURL *file, CGImageRef backdrop, CGImageRef cover, NSString *previous, NSString *line,
                                 NSString *translation, NSString *next, CGSize size, SGLyricsClipStyle style,
                                 SGLyricsClipLayout layout, SGLyricsClipTextSize textSize, BOOL (^current)(void));
// The same in the Left layout.
static inline CF_RETURNS_RETAINED CGImageRef SGLyricsClipFrame(CGImageRef backdrop, NSString *line, NSString *translation,
                                                               NSString *next, CGSize size) {
    return SGLyricsClipFrameWithLayout(backdrop, NULL, nil, line, translation, next, size, SGLyricsClipLeft);
}
static inline BOOL SGLyricsClipWrite(NSURL *file, CGImageRef backdrop, NSString *line, NSString *translation, NSString *next,
                                     CGSize size, SGLyricsClipStyle style) {
    return SGLyricsClipWriteWithLayout(file, backdrop, NULL, nil, line, translation, next, size, style, SGLyricsClipLeft, nil);
}

// The words over moving artwork instead: `motion` is a local video, played from `from` seconds into the
// song, taken round its length, for `seconds`, round its end as often as needed; when the video is no
// longer than that, the whole of it, turned to start there, so the lock screen's loop has no seam. The
// line sung last shows dimmed above the line. Written at the largest 3:4 cut of the video, about its
// middle, at the video's frame rate up to 30 fps. NO for a video stood on its side by its transform, or
// one that does not read. Blocks, so never on the main queue. Not for a scene, which covers the picture whole.
// OverArtwork here is always dimmed whole: every frame blurred and darkened evenly, by the brightest of the
// stretch, rather than a band behind the words.
BOOL SGLyricsClipWriteOverMotion(NSURL *file, NSURL *motion, NSString *previous, NSString *line, NSString *translation,
                                 NSString *next, double from, double seconds, SGLyricsClipLayout layout, BOOL (^current)(void));
BOOL SGLyricsClipWriteOverMotionWithTextSize(NSURL *file, NSURL *motion, NSString *previous, NSString *line, NSString *translation,
                                 NSString *next, double from, double seconds, SGLyricsClipLayout layout, SGLyricsClipTextSize textSize, BOOL (^current)(void));
// The end of a line's artwork ID, so a clip kept under it is the one wanted: the render version, the text size, the style, which a clip falling
// back to the cover is drawn in, and the layout, d when Over the artwork is dimmed whole, and with moving artwork m and the
// first 16 characters of its file's name (the store names files by a SHA-1 of their address), so another video for the
// track redraws the line showing.
NSString *SGLyricsClipLook(NSURL *motion, SGLyricsClipStyle style, SGLyricsClipLayout layout, BOOL dimmed);
NSString *SGLyricsClipLookWithTextSize(NSURL *motion, SGLyricsClipStyle style, SGLyricsClipLayout layout, BOOL dimmed, SGLyricsClipTextSize textSize);
// That clip's first frame, for the preview image, NULL where the clip would not be written. The same `from` and
// `seconds` as the clip's, as the darkness behind the words is judged across that stretch of the video.
CGImageRef SGLyricsClipMotionFrame(NSURL *motion, NSString *previous, NSString *line, NSString *translation, NSString *next,
                                   double from, double seconds, SGLyricsClipLayout layout) CF_RETURNS_RETAINED;
CGImageRef SGLyricsClipMotionFrameWithTextSize(NSURL *motion, NSString *previous, NSString *line, NSString *translation, NSString *next,
                                   double from, double seconds, SGLyricsClipLayout layout, SGLyricsClipTextSize textSize) CF_RETURNS_RETAINED;
