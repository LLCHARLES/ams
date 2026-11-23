// The player redesign (screen key "player"): Spotify's full screen player kept, with its controller,
// units, controls and card list, and restyled from the Kit. Every control stays Spotify's own, so its
// action, state and accessibility do too; the redesign adds the artwork field behind it, glass behind
// the header buttons, bare glyphs for previous, play and next, a lyrics glyph in the footer, and one
// screen with nothing under it: every card is collapsed and the player does not scroll. The lyrics
// come to the player itself, the way the Music app shows them, when the lyrics glyph is tapped.
//
//     PlayerField.x      the switch's flags and rows, the field in the background plane, the cover it reads
//     PlayerArtwork.x    the cover's corners, shadow and paused shrink; the lyric preview as Spotify's setting has it
//     PlayerHeader.x     the header's close and more buttons put away for the Music app's grabber (the AI DJ's keep
//                        their glass)
//     PlayerControls.x   previous, play and next as bare glyphs, shuffle and repeat hidden on request, monospaced times
//     PlayerFooter.x     share gone, lyrics, Connect and queue as one row of three glyphs
//     DJPlayer.x         the AI DJ's player (its own units): skip glyphs, a four glyph footer row, over the shared
//                        play glyph, lowered row and Connect of PlayerControls.x and PlayerFooter.x
//     PlayerCards.x      every card under the player collapsed, so the list closes up
//     PlayerScroll.x     the list held at its top, so the player is one screen and cannot be scrolled up,
//                        and its pull held off while the progress bar is scrubbed
//     PlayerLyrics.x     the lyrics in the player: the cover as a thumbnail, the title up beside it
//     PlayerGestures.x   the gestures' hookup
//     PlayerMorph.x      the open and close grown out of the now playing bar's card, the cover flown
//     PlayerMotion.x     Animated artwork: the Canvas or Apple Music's animated cover behind the player
//     PlayerVisualiser.m the Visualizer background: a calm spectrum of the song in the cover's colors, read
//                        through SGRSpectrum.m from the audio effects' tap on Spotify's output
//     PlayerLyricStages.m the Visualizer's Poster and Cut lyric styles and their parameters
//     PlayerMenu.m       the ⋯ beside the title and its system menu: Share, Add to playlist and Add to queue on top,
//                        the title row's add button and X, Spotify's other rows, then speed, pitch and reverb, the
//                        backgrounds it can switch to and the rest of the player's own (Redesigned/ContextMenu)
//     PlayerSettings.m   the Player page in Mod Settings, led by a showcase of the player
//     PlayerFree.x       a Spotify Free account given the player mode these units belong to
//     PlayerTitle.x      the title and the artist shown simplified or translated, over Spotify's own labels
//
// Speed and pitch, once the redesign's own, are Shared/Player/SpeedPitch.h's; PlayerHeader.x still hands
// the more button over, so a menu opened from it is taken for the player's, and hands it to PlayerMenu.m,
// which opens it as the system menu.
//
// Every hook installs only while Redesigned UI is on (SGRedesignedUI); the native look's do not then.
// Threading: main thread only.
#import <UIKit/UIKit.h>

@class SGRArtworkField;

// What is behind the player, chosen on the Player page (PlayerSettings.m).
// SGRKeyPlayerMotion is the switch the choice replaced: until a choice is stored, it picks Still or Colors.
#define SGRKeyPlayerBackground @"spotifyglass.redesign.player.background"
#define SGRKeyPlayerMotion @"spotifyglass.redesign.player.movingBackground"
typedef NS_ENUM(NSInteger, SGRPlayerBackgroundKind) {
    SGRPlayerBackgroundStill,      // the artwork blurred and held still
    SGRPlayerBackgroundColours,    // the artwork's colors drifting (SGRFlow.h)
    SGRPlayerBackgroundFluid,      // the artwork itself blurred and turning (SGRFluid.h)
    SGRPlayerBackgroundAnimated,   // the track's Canvas or Apple Music's animated cover, over Fluid (PlayerMotion.x)
    SGRPlayerBackgroundVisualiser, // a spectrum of the song over Fluid held still (PlayerVisualiser.m)
    SGRPlayerBackgroundBlack,      // pure black, nothing of the artwork (PlayerBackdrop.m)
    SGRPlayerBackgroundPhoto,      // a photo of the user's own, darkened for the text over it (PlayerBackdrop.m)
};
// The player's ⋯ menu switches between Fluid, Animated and Visualizer, which share the Fluid field, without a restart.
SGRPlayerBackgroundKind SGRPlayerBackground(void);
// Main-thread choices from the page and menu. Each choice advances the generation, even when the kind
// stays the same, so an asynchronous Photo choice cannot override a later choice.
NSUInteger SGRSetPlayerBackground(SGRPlayerBackgroundKind kind);
NSUInteger SGRPlayerBackgroundGeneration(void);
// Whether the kind is drawn from the artwork (Still to Visualizer), not black or a photo.
static inline BOOL SGRPlayerBackgroundFromArtwork(SGRPlayerBackgroundKind kind) {
    return kind <= SGRPlayerBackgroundVisualiser;
}
// The artwork's choice last picked, Still to Visualizer: what the field is made as under black or a photo, and what
// "Artwork" goes back to. Written by the Player page as a segment is picked.
#define SGRKeyPlayerArtworkBackground @"spotifyglass.redesign.player.background.artwork"
SGRPlayerBackgroundKind SGRPlayerArtworkBackground(void);
// The Player page stored another choice: the clip and the Visualizer follow it at once (PlayerMotion.x).
void SGRPlayerBackgroundDidChange(void);
// The names of the artwork's choices, Still to Visualizer, in order: the Player page's segments.
NSArray<NSString *> *SGRPlayerBackgroundNames(void);

#pragma mark - black or a photo behind the player (PlayerBackdrop.m)

// Posted on the main thread when a prepared photo is ready, from disk or a successful import.
extern NSNotificationName const SGRPlayerPhotoDidChangeNotification;
// Lays black or the photo over the field while the background is one of them, and takes it away otherwise; the
// field's layout calls it before the clip's (PlayerField.x).
void SGRPlayerBackdropLaidOut(SGRArtworkField *field);
// Whether black or a photo lies over the field.
BOOL SGRPlayerBackdropShowing(void);
// The lyrics came or went: the photo takes a little more dim and a blur behind them.
void SGRPlayerBackdropLyricsChanged(void);
// A view drawing the chosen black or photo, for the Player page's card; nil for the artwork's choices.
UIView *SGRPlayerBackdropPreview(void);
// Loads and prepares the stored photo off main, once. The optional completion runs on main (immediately
// when already prepared) with whether a photo is available; callers keep their current look meanwhile.
void SGRPlayerLoadPhoto(void (^done)(BOOL available));
// The photo library over `from`, one image: a picked one is stored, and `done` runs on the main thread with
// whether it was (NO when canceled).
void SGRPlayerPickPhoto(UIViewController *from, void (^done)(BOOL stored));

// The field behind the player, nil until the player has laid out once (PlayerField.x).
SGRArtworkField *SGRPlayerField(void);
// Holds the field still, or lets it move, for what is over it now: a paused song, an Animated artwork clip, the
// Visualizer (PlayerField.x).
void SGRPlayerHoldField(void);

#pragma mark - the player's margins and rhythm

// The Music app's side margin: the title row and the progress bar (SGRPlayerHoldMargin) and
// the volume row (PlayerFooter.x) start this far in from the player's edges, where Spotify's own sit nearer.
static const CGFloat SGRPlayerSideMargin = 32;
// Insets `view`, which Spotify's constraints lay out in its superview (a unit's view), on both sides so that its content,
// starting `contentX` in from the view's own leading edge, starts SGRPlayerSideMargin in from the superview's. Called
// after each of Spotify's layout passes; the inset is measured from the native leading pin and the `contentX` of the pass
// that inset the view (later ones are of the inset view's own layout and are not used) and added to the constants of Spotify's side
// constraints (each one's own constant kept), so it never compounds, the content inside lays out for the new width, and
// a view Spotify already insets as far is left alone.
void SGRPlayerHoldMargin(UIView *view, CGFloat contentX);
// The Music app's gap from the volume row's middle to the footer row's middle: the footer's rhythm makes the room for it
// (PlayerFooter.x) and the volume row stands this far over the footer where the room allows (PlayerVolume.m).
static const CGFloat SGRPlayerVolumeToRow = 48;

#pragma mark - the cover (PlayerArtwork.x)

// The sideways list of covers behind the player, nil until one has laid out.
UIView *SGRPlayerCoverList(void);
// The cover on screen itself (its corners clip, its transform is the paused shrink), nil when none has laid out:
// a square clip plays inside it (PlayerMotion.x).
UIView *SGRPlayerShowingCover(void);
// The cover on screen as it is drawn, its paused shrink included, in `host`'s coordinates; CGRectNull
// when no cover has laid out.
CGRect SGRPlayerCoverFrameIn(UIView *host);
// The scale the cover is drawn at: 1 while playing, its shrink while paused, so a stand-in can draw its
// corners the size the cover's are.
CGFloat SGRPlayerCoverScale(void);
// The band that cover sits in -- the room the player gives its artwork, between the header row and the
// title -- in `host`'s coordinates; CGRectNull when no cover has laid out.
CGRect SGRPlayerArtworkAreaIn(UIView *host);
// Hides the cover on screen and its shadow, or shows them again, for a stand-in to fly in its place
// (PlayerMorph.x). Until NO, every cover laid out on screen is hidden too, the first open's included.
void SGRPlayerSetCoverHidden(BOOL hidden);
// A header row taking touches (`live`) or letting them go (PlayerHeader.x, on each of its layouts), in `player`, the
// player's own view holding it, or nil: the cover, lifted to the Music app's top, stays under every live row in its own
// player, wherever the row is moved in it.
void SGRPlayerCoverUnderRow(UIView *row, BOOL live, UIView *player);
// A header row in `view`'s window shows something to read besides the grabber: where it plays from, Spotify's live
// arrow, the AI DJ's buttons (the rows SGRPlayerCoverUnderRow is told are live). The clip's dim covers it
// (PlayerMotion.x), which hears of each change through SGRPlayerMotionHeaderChanged.
BOOL SGRPlayerHeaderShowsIn(UIView *view);
void SGRPlayerMotionHeaderChanged(void);

#pragma mark - the title (PlayerTitle.x)

// The title the redesign shows for a track, simplified or translated as the Lyrics page sets, and in
// \`shownArtist\` the artist; the title as given while neither is on or nothing is in. Main thread.
NSString *SGRShownTitle(NSString *trackID, NSString *title, NSString *artist, NSString **shownArtist);
// Finds Spotify's title and artist labels in the information unit's view and has them show the title above, in the
// Music app's type.
void SGRShownTitleWatch(UIView *unit);
// The lyrics came or went (SGRPlayerLyricsChanged): the two labels take the type for it, 17 over 17 beside the
// lyrics' thumbnail, 20 over 20 otherwise.
void SGRShownTitleRestyle(void);
// The lyrics slide the title's arranged view `slide` points toward the row's trailing controls, 0 when they do not
// (PlayerLyrics.x): the title, and its explicit mark, then end that much and a gap sooner.
void SGRShownTitleSlide(CGFloat slide);

#pragma mark - iPad (PlayerLyrics.x, Redesigned/NowPlayingBar/NowPlayingBar.x)

// The iPad layouts, the two column player and the capsule mini player, run in an iPad window of regular width; an
// iPhone and an iPad window of compact width (a narrow Split View or Slide Over) keep the ordinary ones. No switch.
static inline BOOL SGRPlayerIPadRegular(UIView *view) {
    UITraitCollection *traits = view.window.traitCollection;
    return traits.userInterfaceIdiom == UIUserInterfaceIdiomPad && traits.horizontalSizeClass == UIUserInterfaceSizeClassRegular;
}

// A player can extend beyond its window while Spotify's scroll container is inset or translated.
// Both columns use the visible safe rectangle, in the player's coordinates, not just its own bounds.
static inline CGRect SGRPlayerVisibleSafeArea(UIView *view) {
    UIWindow *window = view.window;
    CGRect safe = window.safeAreaLayoutGuide.layoutFrame;
    if (@available(iOS 26.0, *)) {
        if (window.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            // The ordinary safe area excludes bars, not the window controls in a corner.
            // Keep the columns below that system-owned region, including full-screen windows.
            UIViewLayoutRegion *region = [UIViewLayoutRegion safeAreaLayoutRegionWithCornerAdaptation:UIViewLayoutRegionAdaptivityAxisVertical];
            safe = UIEdgeInsetsInsetRect(window.bounds, [window edgeInsetsForLayoutRegion:region]);
        }
    }
    CGRect windowSafe = [view convertRect:safe fromView:window];
    return CGRectIntersection(UIEdgeInsetsInsetRect(view.bounds, view.safeAreaInsets), windowSafe);
}

#pragma mark - the lyrics in the player (PlayerLyrics.x)

// The two column player: on an iPad of regular width a player wide enough for both columns (Spotify's expanded player,
// not its side panel) keeps the cover and Spotify's bottom stack in a column on the leading side and shows the lyrics,
// or the queue (PlayerQueue.m's list), in a column beside it. Whether the open player is laid out so.
BOOL SGRPlayerTwoColumns(void);
// Which the side column shows: the lyrics while SGRPlayerLyricsOpen, else the queue. The lyrics show by default when
// the track has them; the footer's lyrics and queue glyphs pick one, for as long as the player stays open.
BOOL SGRPlayerQueueSideShown(void);
// The footer's queue glyph selects the queue in the side column.
void SGRPlayerToggleQueueSide(void);
// The mini player's lyrics button: the player, opened next, shows the lyrics once it is up (both layouts; nothing for
// a track without lyrics). Called before the player is asked to open.
void SGRPlayerShowLyricsOnOpen(void);

// Whether the playing track has lyrics the player can show.
BOOL SGRPlayerLyricsAvailable(void);
// Whether the playing track has none: its grace is over and nothing is looking for them any more.
BOOL SGRPlayerLyricsNone(void);
// Whether the player is showing them.
BOOL SGRPlayerLyricsOpen(void);
// Hides a control without room or while lyrics are alone; only fitting controls return when they wake.
BOOL SGRPlayerLyricsFadeView(UIView *view, BOOL fits);
// Shows them, or puts the cover back; does nothing when there are none to show.
void SGRPlayerToggleLyrics(void);
void SGRPlayerOpenPreviewLyrics(UIView *preview);
// Called by PlayerLyrics.x whenever either of those two changed, so the footer's lyrics glyph follows
// (PlayerFooter.x). It returns at once when nothing changed.
void SGRPlayerLyricsChanged(void);
// The lyrics glyph of the footer, made on first ask in `host` and kept there; the ordinary player's footer
// (PlayerFooter.x) and the AI DJ's (DJPlayer.x) share it. Only the one asked for last is followed by
// SGRPlayerLyricsChanged, which is the footer on screen: each layout of a footer asks again.
@class SGRGlyphButton;
SGRGlyphButton *SGRPlayerLyricsGlyphIn(UIView *host);
// An Endless_DJMusicImpl class of the AI DJ's player by its Swift name, under the mangled spelling or the
// dotted one the trees print; nil when the app has neither.
static inline Class SGRDJClass(NSString *name) {
    NSString *module = @"Endless_DJMusicImpl";
    NSString *mangled = [NSString stringWithFormat:@"_TtC%lu%@%lu%@", (unsigned long)module.length, module, (unsigned long)name.length, name];
    return NSClassFromString(mangled) ?: NSClassFromString([NSString stringWithFormat:@"%@.%@", module, name]);
}
// What fades a few seconds after the last touch while the lyrics play, as the lines grow into the room
// (PlayerLyrics.x): nothing, everything but the lines, or the controls under the title row alone. A scroll
// through the lines hides the same views, everything when the choice is Off. The key was a switch first: its
// NO and YES are the first two indexes, and unset reads as the switch did.
#define SGRKeyLyricsAutoHide @"spotifyglass.redesign.lyrics.autoHide"
typedef NS_ENUM(NSInteger, SGRLyricsHide) { SGRLyricsHideOff, SGRLyricsHideAll, SGRLyricsHideControls };
SGRLyricsHide SGRLyricsHideMode(void);
@class SGModRow;
// The Lyrics page's choice of it (PlayerSettings.m).
SGModRow *SGRLyricsHideRow(void);

// A volume slider under the controls (PlayerVolume.m), the system's: this iPhone's, or the Connect device's.
// On until switched off. Placed by the footer's layout, between the controls (`controls`) and the footer row
// (`row`), both arranged in Spotify's bottom stack, `margin` in from each side: SGRPlayerVolumeToRow over the footer row
// where the room allows while the footer keeps the Music app's rhythm (`rhythm`: taller than wide, one column), else
// halfway between the play button and the footer's glyphs.
#define SGRKeyPlayerVolume @"spotifyglass.redesign.player.volume"
BOOL SGRPlayerVolumeOn(void);
// The colors of the progress bar (PlayerControls.x) and the volume row, translucent as the Music app's: the fill a light
// white the background shows through, whole white while `lit` (a finger scrubs), and the track dimmer; both more opaque
// under Increase Contrast.
UIColor *SGRPlayerBarFill(BOOL lit);
UIColor *SGRPlayerBarTrack(void);
// Both bars are drawn the one way, the Music app's: default-style sliders with an empty thumb, as Spotify's progress bar
// is, whose tracks are capsule images (SGRPlayerBarImage) `height` tall in the bar's colors. Such a slider draws its fill
// up to the thumb's middle and cuts it there, so the fill ends square inside the round track. Spotify's track images are
// SGRPlayerBarHeight tall (trees/clean 01.txt:1907), and a finger dragging a bar grows its track to
// SGRPlayerBarDragHeight about its middle.
static const CGFloat SGRPlayerBarHeight = 7;
UIImage *SGRPlayerBarImage(UIColor *color, CGFloat height);
CGFloat SGRPlayerBarDragHeight(CGFloat height);
// YES when the row shows; NO when it is off, has no controls to sit under or no room between them and the footer.
BOOL SGRPlayerPlaceVolume(UIView *stack, UIView *controls, UIView *row, CGFloat margin, BOOL rhythm);

// Follow the cover (PlayerCoverAccent.x): the player's lit controls painted in the cover's color instead of the accent.
// Off until switched on, read at launch. The cover's color (a gray one gives the accent back), and a paint of Spotify's
// bottom stack, which the footer's layout asks for. The switch's key is the Kit's (SGRAccent.h): it keeps the accent's
// provenance hooks installed under Spotify's green.
BOOL SGRPlayerFollowsCover(void);
void SGRPlayerSetCoverAccent(UIColor *cover);
void SGRPlayerPaintCover(UIView *stack);

// Glass circles behind the AI DJ's header down arrow and ⋯ (PlayerHeader.x; the ordinary player's header has only the
// grabber). On until switched off; off, the buttons are Spotify's as drawn, with their actions, touches and
// accessibility, and the grabber stays. Followed at once (SGRPlayerLookChanged).
#define SGRKeyPlayerHeaderGlass @"spotifyglass.redesign.player.headerGlass"
#define SGRKeyPlayerHideContext @"spotifyglass.redesign.player.hideContext"
// The Music app's glyphs in the footer row (PlayerFooter.x) and the AI DJ's (DJPlayer.x): AirPlay audio for Connect and a
// bulleted list for the queue over Spotify's own, a quote bubble for Lyrics, and the DJ button as a waveform. On until
// switched off; off, Spotify's Connect and queue glyphs show again in the colors and state Spotify gives them, Lyrics and
// the AI DJ's Queue draw Spotify's Encore glyphs (SGRPlayerFooterGlyph), and the DJ button its blue disc. Followed at
// once (SGRPlayerLookChanged).
#define SGRKeyPlayerMusicIcons @"spotifyglass.redesign.player.musicIcons"
// What one of the redesign's footer buttons draws (PlayerFooter.x): its own symbol while the switch above is on; while
// it is off, Spotify's Encore glyph `encoreName` (an SPTEncoreIcon class method: "microphone", "queue") in its place, in the
// symbol's color, the symbol hidden. Asked on every pass of the footer, so the switch reaches it live; hands back the
// view that draws, for the press. A build without that glyph keeps the symbol.
@class SGRGlyphButton;
UIView *SGRPlayerFooterGlyph(SGRGlyphButton *button, NSString *encoreName);
// The unit views that draw what those two switches change, each made to lay out again when one is flipped on the
// Player page (PlayerSettings.m), so the open player follows without a restart. Watching a view again changes nothing.
void SGRPlayerWatchLook(UIView *unitView);
void SGRPlayerLookChanged(void);

// Shuffle and repeat left out of the controls (PlayerControls.x), each on its own switch under Hide on the player, the
// way the Music app keeps them off its main controls. Off until switched on, read at launch. The buttons go by alpha
// and keep their slots, so previous, play and next stay centered; with neither shown (both hidden, or a row Spotify
// builds without them), in portrait, previous and next move out from play (PlayerControls.x, spreadSkips).
#define SGRKeyPlayerHideShuffle @"spotifyglass.redesign.player.hideShuffle"
#define SGRKeyPlayerHideRepeat @"spotifyglass.redesign.player.hideRepeat"

// The lyrics turn sideways with the phone onto a landscape screen of their own (PlayerLandscape.x). On
// until switched off. Shown or put away by hand for the harness.
#define SGRKeyLyricsLandscape @"spotifyglass.redesign.lyrics.landscape"
// The player turns onto it too with its lyrics closed, laid out as for a track without lines. Off until switched on
// (PlayerSettings.m), read at each turn. Either switch on turns a player whose lyrics are open.
#define SGRKeyPlayerLandscape @"spotifyglass.redesign.player.landscape"
// Goes up only over the player on screen, in its scene.
void SGRPlayerShowLandscape(BOOL show);
// The playing track's lines came in, or turned out to be none: the landscape screen lays out for it.
void SGRPlayerLandscapeLinesChanged(void);

// Animated's full-screen cover (PlayerMotion.x): a track with no clip shows its cover behind the player the way a clip
// is shown, as a still, in place of the ordinary cover. Off until switched on; the open player follows the switch at
// once (SGRPlayerStillChanged, from the Player page).
#define SGRKeyPlayerAnimatedStill @"spotifyglass.redesign.player.animatedStill"
BOOL SGRPlayerStillOn(void);
// The Player page switched the full-screen cover on or off: the open player follows at once. Switching it on
// switches the Visualizer without a clip off.
void SGRPlayerStillChanged(void);
// Animated's Visualizer for a track with no clip (PlayerMotion.x, PlayerVisualiser.m): off until switched on. Switching
// it on switches the full-screen cover off (the last one switched on wins); the open player follows at once.
#define SGRKeyPlayerAnimatedVisualiser @"spotifyglass.redesign.player.animatedVisualizer"
BOOL SGRPlayerAnimatedVisualiserOn(void);
void SGRPlayerAnimatedVisualiserChanged(void);
// With both switches saved on, the full-screen cover stays and the Visualizer switch goes off. Called at start and on
// every pass of SGRPlayerVisualiserUpdate; the fallback is never wanted while the cover is on.
void SGRPlayerReconcileFallbackSwitches(void);
// The Visualizer is wanted in place of the cover: the switch is on, the playing track's lookup finished with no clip,
// and a clip would be wanted (Animated, Spotify's video not showing, Reduce Motion and Low Power Mode off). NO while
// the lookup is out.
BOOL SGRPlayerVisualiserFallbackWanted(void);
// The animated artwork follows the lyrics: blurred behind them (PlayerMotion.x).
void SGRPlayerMotionLyricsChanged(void);
// The field was laid out (PlayerField.x): the clip goes onto it, and the cover is hidden or shown again.
void SGRPlayerMotionFieldLaidOut(void);
// The player's field is on screen and its controller has not disappeared. Main-thread changes only.
BOOL SGRPlayerIsVisible(void);
// The settled field in window coordinates, or CGRectNull. Coverage requires didAppear and a finished
// opening morph, and ends at willDisappear. Moving or resizing a settled field also notifies.
CGRect SGRSettledPlayerRect(UIWindow *window);
FOUNDATION_EXPORT NSNotificationName const SGRPlayerVisibilityDidChangeNotification;
@class SGRProgressClock;
extern __thread __unsafe_unretained SGRProgressClock *SGRWritingProgress;
void SGRProgressSliderWrote(UISlider *slider);
void SGRProgressOutputMounted(UIView *view);
void SGRProgressRailChanged(UISlider *slider, BOOL tracking);
void SGRProgressPlaybackChanged(double seconds, double rate);
void SGRProgressVisibilityChanged(void);
void SGRProgressControlsFaded(BOOL finished);
// A cover in the player laid out: hides it while a clip plays.
void SGRPlayerMotionCoverLaidOut(void);
// A clip is playing in place of the cover, which is then hidden: the lyrics' thumbnail and the open's
// flown cover fade where they are rather than flying to or from it.
BOOL SGRPlayerMotionShowing(void);
// The Visualizer's Poster or Cut shows a line (PlayerVisualiser.m): the cover fades away by the clip's own mask so the
// type owns its place, and fades back when `takes` is NO, unless a clip holds it.
void SGRPlayerLyricStageTakesCover(BOOL takes);
// The player's cover card is hidden, by a clip or by a lyric stage's line: the open's and close's flown cover fades
// out rather than landing on an empty slot (PlayerMorph.x).
BOOL SGRPlayerCoverHidden(void);
// A view of its own playing that clip, drawn as the player draws it (its foot, the blur under the controls),
// for the Player page's showcase. It plays only in a window, like the player's. While the player has no clip
// it is the playing track's, which the page looks up itself, by the player's sources and Low Data Mode, into
// the store the player reads too: nil until it is in, and with `arrived` given the lookup starts, and
// `arrived` runs once on the main queue when a call would return it (never when nothing is found, or the
// track changed). Without `arrived` it only answers with a clip already in.
UIView *SGRPlayerMotionPreview(void (^arrived)(void));
// End the page's preview only: cancel its lookup, invalidate late posters, and release its decoder.
// Shared transfers still needed by the real player are not cancelled.
void SGRPlayerMotionPreviewStop(void);
// How dark the clip is drawn (the dim's opacity, where its gradient is whole) for white text over it to keep
// 4.5:1, or 7:1 with `contrast` (Increase Contrast), when `luminance` is the clip's bright end, its 75th
// percentile of linear luminance; between 0.10 and 0.80, 0.15 more while the lyrics are up.
CGFloat SGRPlayerClipDim(CGFloat luminance, BOOL contrast, BOOL lyrics);
// The bright end of an image's linear luminance (its 75th percentile, read 16 points square), what
// SGRPlayerClipDim takes. Any thread.
CGFloat SGRPlayerImageBrightEnd(CGImageRef image);

#pragma mark - the Visualizer (PlayerVisualiser.m)

// Compatibility exception to the redesign-only prefix: 0.51.0 stores these exact string IDs here.
#define SGRKeyVisualiserStyle @"spotifyglass.visualizer.shader"
// The two lyric styles after Lyrics, drawn by PlayerLyricStages.m.
#define SGRVisualiserPosterID @"builtin:poster"
#define SGRVisualiserCutID @"builtin:cut"
extern NSNotificationName const SGRVisualiserStyleDidChangeNotification;
NSArray<NSString *> *SGRVisualiserStyleNames(void);
NSArray<NSString *> *SGRVisualiserStyleIDs(void);
// Invalid or missing storage reads as builtin:hills without rewriting the original value.
NSString *SGRVisualiserStyle(void);
void SGRSetVisualiserStyle(NSString *identifier);
// The user's own pick: the style, and the one shuffle goes back to when it is turned off.
void SGRPickVisualiserStyle(NSString *identifier);
// Shuffle styles: with each new song, while the Visualizer is on screen, a style other than the current one is
// picked at random and made the current style. Off until switched on. Switching it on remembers the current
// style as the user's own; switching it off restores that one.
#define SGRKeyVisualiserShuffle @"spotifyglass.visualizer.shuffle"
#define SGRKeyVisualiserShuffleHome @"spotifyglass.visualizer.shuffle.home"
void SGRVisualiserShuffleChanged(void);
// Ignore heat warnings: the Visualizer keeps moving at a serious or critical thermal state (Low Power Mode and
// Reduce Motion still stop it). Off until switched on. Whether `state` stands the Visualizer down.
#define SGRKeyVisualiserIgnoreHeat @"spotifyglass.visualizer.ignoreHeat"
BOOL SGRVisualiserStandsDownFor(NSProcessInfoThermalState state);
// The switch changed: the Visualizer on screen takes it up now rather than at its next check.
void SGRVisualiserIgnoreHeatChanged(void);
// Poster's and Cut's parameters (PlayerLyricStages.m), in one dictionary: style id -> { parameter id -> value }.
// A switch is stored as a boolean, a color as "#RRGGBB", a number as itself. A missing or malformed entry reads
// as its default and a number out of range is clamped; storing a parameter's default removes it, and a style left
// with none is removed, so no empty dictionary stays behind.
#define SGRKeyVisualiserParams @"spotifyglass.visualizer.params"
#define SGRVisualiserHalftone @"halftone"   // Poster: switch, on
#define SGRVisualiserInk @"ink"             // Poster: #F4EFE6, Cut: #FFFFFF
#define SGRVisualiserBackdrop @"backdrop"   // Poster's print strength: 0 to 1, 0.6
#define SGRVisualiserGhost @"ghost"         // Poster's words ahead: 0 to 0.5, 0.35
#define SGRVisualiserShade @"shade"         // Cut's background darkening: 0 to 1, 0.75
#define SGRVisualiserMotion @"motion"       // Cut: 0 to 1.5, 1
#define SGRVisualiserSubtitle @"subtitle"   // Cut's whole line: switch, on
// Posted on main when a parameter is stored; the views on screen take it up at once.
extern NSNotificationName const SGRVisualiserParamsDidChangeNotification;
typedef struct { double least, most, step; } SGRVisualiserParamLimits;
// A number's range and step; a switch's 0 to 1, a color's 0 to 0xFFFFFF.
SGRVisualiserParamLimits SGRVisualiserParamLimitsOf(NSString *style, NSString *param);
// A number as itself, a switch as 0 or 1, a color as 0xRRGGBB.
double SGRVisualiserParam(NSString *style, NSString *param);
void SGRSetVisualiserParam(NSString *style, NSString *param, double value);

@class SGModRow;
SGModRow *SGRVisualiserStyleRow(void);
// Local styles only; never changes the player's background kind or creates a player visualizer.
UIViewController *SGRVisualiserSettingsPage(void);

// The background is the Visualizer, or it stands in for a track's missing clip (SGRPlayerVisualiserFallbackWanted)
// and the thermal state does not stand it down.
BOOL SGRPlayerVisualiserShowing(void);
// Puts the hills on the field or takes them off as the background says, lays them out, and blurs them while the
// lyrics are open. Called on every layout pass of the field (PlayerField.x), when the lyrics come or go
// (PlayerFooter.x), and when the ⋯ menu switches the background (PlayerMotion.x and here); cheap when nothing
// changed.
void SGRPlayerVisualiserUpdate(void);
// A view of its own drawing the same hills, for the Player page's showcase. It moves only in a window.
UIView *SGRPlayerVisualiserPreview(void);
// Release only the page's cached visualizer and stop its observers, timers and pending palette application.
void SGRPlayerVisualiserPreviewStop(void);
// Switches the background to `kind` from the ⋯ menu, at once: Fluid, Animated or Visualizer, while it is one of
// them (SGPlayerMenuOffersAnimatedArtwork); nothing otherwise.
void SGRPlayerMenuSetBackground(SGRPlayerBackgroundKind kind);

#pragma mark - Mod Settings (PlayerSettings.m)

// The redesign's Player page: a card of the player over the background chosen and the control that picks
// it, the background's rows and the Mini player section under it, then `more`, the sections either look
// shares (App/Pages.m).
UIViewController *SGRPlayerSettingsPage(NSArray *more);
// The redesign's Buttons card for the Player page's shared sections (App/Pages.m): Shuffle, Repeat and Video as toggle
// chips, each selected while its hide key (SGRKeyPlayerHideShuffle, SGRKeyPlayerHideRepeat, SGKeyHideVideoSwitch) is
// effectively off. Shuffle and Repeat start selected, Video unselected. Only SGRPlayerSettingsPage draws the chips.
@class SGModSection;
SGModSection *SGRPlayerButtonsSection(void);

// The play glyph over the play button in `host`, a controls unit's view: the ordinary player's
// (PlayerControls.x) and the AI DJ's (DJPlayer.x) share it, with its state, spinner and tap handling.
void SGRPlayerPlayGlyphIn(UIView *host);

// Transport glyph creation and placement shared by the ordinary and DJ controls (PlayerControls.x).
// Each caller keeps its own association key; the symbol and size apply only when first created.
@class SGRGlyphView;
SGRGlyphView *SGRPlayerGlyphFor(UIView *owner, const void *key, NSString *symbol, CGFloat size);
void SGRPlayerPlaceGlyph(UIView *view, UIView *host, CGFloat dy);

// A podcast's speed button in the controls unit `host`, its words on one line inside the button, where it takes its
// tap and VoiceOver frames it (PlayerSpeedLabel.m); kept so as Spotify lays the words out again.
void SGRPlayerFitSpeedLabel(UIView *host);

// The footer's shared parts (PlayerFooter.x), for the AI DJ's footer (DJPlayer.x). `row` is the footer unit's view:
// moved down over the home indicator with the controls following, the volume row and Follow the cover placed.
void SGRPlayerLowerRow(UIView *row);
// Connect's glyph in `connect`, laid out and with the device name hidden; nil while it has no size yet, and `host`
// then lays out again on the next turn of the run loop. Leave Connect where it is while it is nil.
UIView *SGRPlayerConnectGlyphIn(UIView *host, UIView *connect);
// Connect's touches only in a 44pt square over its glyph: `holder` is the view of the footer that holds Connect, whose
// own view reaches far past the glyph (over Queue and the DJ button once the glyph is moved).
void SGRPlayerCoverConnect(UIView *holder, UIView *glyph);
// Whether a control is drawn lit: in the accent, judged as Follow the cover judges what it repaints.
BOOL SGRPlayerAccentLike(UIColor *color);
// The color an image is drawn in: the average of its opaque pixels, read once at 16 by 16 and kept on the image; nil
// for one with too few.
UIColor *SGRPlayerImageInk(UIImage *image);

// The tap to seek around the progress bar (PlayerControls.x), apart for the harness: whether a tap at `point`
// in the duration unit's view seeks, and the share of the song a point on the slider stands for, measured
// over the thumb's travel (NAN while the slider has no width).
BOOL SGRSeekTapLands(UIView *unit, UISlider *slider, CGPoint point);
CGFloat SGRSeekShareAt(UISlider *slider, CGPoint point);

// The player's ⋯ (PlayerMenu.m): a button of the mod's beside the title, where the Music app has it, opening the system
// menu: the song's actions first (the title row's add button and Spotify's X among them), the player's own items after.
// PlayerHeader.x hands over Spotify's own ⋯, which it hides, on every pass of the header: its action brings up the
// sheet whose rows the menu shows. Watching it again changes nothing.
void SGRPlayerMenuWatch(UIView *button);
// Called on every pass of the ordinary player's title row (PlayerLyrics.x) with the title's arranged view: the add
// button and Spotify's X go (alpha, and out of VoiceOver's reach) and the ⋯ takes the add button's slot, or the row's
// trailing one where there is none.
void SGRPlayerMenuInTitleRow(UIView *title);
