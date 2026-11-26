// Player redesign: the lyrics come to the player itself, the way the Music app shows them. The player
// is one screen and does not scroll (PlayerScroll.x), so the footer's lyrics glyph is the only way to
// them: it shrinks the cover into a thumbnail at the top of the artwork band, lifts the track's title
// up beside it, and fades the Apple Music style lines (Redesigned/Lyrics/SGRKaraokeView.h) into the
// room that frees between the title and the progress bar. Tapping it again puts the cover back.
//
// Nothing of Spotify's is taken apart for it. The cover is the Kit's now playing artwork drawn again
// in a view of the redesign's own, flown from where Spotify's cover is drawn to where the thumbnail
// belongs, while Spotify's list of covers goes to alpha 0 underneath: one view to move instead of a
// paging list of them, and the two pictures are the same one, so the swap is not seen. The title row
// is Spotify's own unit translated, the way PlayerFooter.x moves the footer's controls -- a transform
// survives the stack view laying its arranged views out again -- and narrowed by PlayerTitle.x by as much
// as it slid (SGRShownTitleSlide), so a long title scrolls or ends before the controls it moved toward. The row
// of chips over it (Switch to video) goes while the lines are up, since they take the room it sits in.
//
// Tree (trees/clean/player/01.txt): SPTNowPlayingView (:26) holds the content layers, the header row
// (:91), and id=npv.bottomStackView {0, 576.67, 402, 236} (:127) whose arranged views are the
// information unit {0, 0, 402, 64} (:160, the title, the artist and the add button), the duration unit
// {0, 64, 402, 40} (:209), the controls (:240) and the footer (:295). The title is
// id=now-playing-title-label and the artist id=now-playing-subtitle-label (:174, :185), both inside one
// arranged element view {12, 2.33, 304, 43.33} of the unit's row. Every measurement here is taken from
// the views themselves, since a player with a volume row or another mode's units has other numbers.
//
// The geometry is re-applied on every layout pass of the units, since a new track rebuilds the
// elements inside them, and it is undone before the player closes: the bar morphs back into a full
// size cover, which a thumbnail would not match.
//
// The two column player (SGRPlayerTwoColumns): on an iPad of regular width, in a player wide enough for both columns
// (Spotify's expanded player; its side panel, 352 pt in 9.1.90, keeps the narrow layout), Spotify's bottom stack is
// narrowed into a column on the leading side, with the cover over it drawn by the same overlay, and the side column
// beside it shows the lyrics or the queue (PlayerQueue.m's list) for as long as the player is that wide, whatever the
// lyrics glyph says: the glyph and the footer's queue glyph only pick which. It holds in either orientation: on iPad
// the landscape screen of PlayerLandscape.x never goes up (iPhone only), so a turn only lays the columns out again.
#import <UIKit/UIGestureRecognizerSubclass.h>
#import "Core/SGCore.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Lyrics/SGRKaraokeView.h"
#import "Redesigned/Lyrics/SGRSingButton.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Sing/Sing.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LocalFiles/LocalFiles.h"
#import "Shared/Player/PlayerEvents.h"
#import "Player.h"
#import "PlayerLyricLine.h"
#import "PlayerQueue.h"

static const CGFloat kThumbSide = 72;          // the cover once the lyrics are up
static const CGFloat kThumbGap = 16;           // between the thumbnail and the title beside it
static const CGFloat kThumbTop = 8;            // inset below the header-aware content top
// The Music app's collapsed artwork, as its player lays it out: the grabber 7 pt under the content's top (the safe
// area's top over 20) and 4 pt tall, and the artwork 22 pt under it, 72 pt square, at the content's leading margin. PlayerHeader.x draws the grabber at the same 7 pt under the safe area.
static const CGFloat kGrabberTopSpacing = 7, kGrabberHeight = 4, kArtworkToGrabberSpacing = 22;
// Carried by the queue's list, the artwork and the title go up at most the artwork's 72 and 32 more, as
// the Music app's stop, so they leave and stay gone.
static const CGFloat kRideMostUp = 72 + 32;
static const CGFloat kLyricsTop = 20;          // between the title row and the first line
static const CGFloat kQueueTop = 16;           // between the thumbnail and the queue page's toggles (the Music app's)
static const CGFloat kQueueRideFade = 40;      // the thumbnail and title fade over this much as the list carries them off
static const CGFloat kLyricsBottom = 8;        // above the progress bar
// The lines are a surface arriving, not something moving: they come up from just under full size as the
// room for them opens, and go at once when it closes. An exit the eye waits through reads as a stall.
static const CGFloat kLyricsEnterScale = 0.96;
static const NSTimeInterval kLyricsIn = 0.3, kLyricsInDelay = 0.12, kLyricsOut = 0.16;
// A track that changes while the lines are up has this long to bring its own before they are put away. A
// look for them still running then is waited out, since a local file's sources are asked one after another,
// up to 6 s each, with a Musixmatch token fetched first the first time.
static const NSTimeInterval kLyricsGrace = 3;
// Below this the player has not laid out yet and nothing can be measured from it.
static const CGFloat kLivingHeight = 200;
// The lines on their own: the controls under them fade after this long without a touch.
static const NSTimeInterval kRest = 4, kRestSinging = 5;
// Keeping the title, the lines alone the way the Music app's are (its player on an iPhone 17 Pro, 2026-11-25): the
// cover, the title row and its ⋯ rise 22 pt together, the title then 12 pt from the cover rather than kThumbGap, and
// the lines start 16 pt under them and run down the whole safe area, its mic gone with the controls.
static const CGFloat kAloneRise = 22, kAloneTitleGap = 12, kAloneLinesTop = 16;
// There the sung line's view stands this far from the top of the player (its first line's capitals 246 pt down on
// the Music app's), where the lines would otherwise rest at a share of their height, well lower.
static const CGFloat kAloneLineTop = 238;
// The two columns: the leading one never narrower than the narrowest iPhone Spotify lays its controls out for, the
// side one never narrower than this, this far apart, so a player is wide enough for both from their sum on. The
// leading column takes this share of the safe width: half on a window taller than wide, less on its side, where the
// height rather than the width limits the cover. The cover stands this far in from each side of its column.
static const CGFloat kColumnMinWidth = 320, kSideMinWidth = 300, kColumnGap = 24;
static const CGFloat kColumnSharePortrait = 0.5, kColumnShareLandscape = 0.42;
static const CGFloat kColumnCoverInset = 16;
// The mini player's lyrics button asks for the lyrics of a player that is about to open: the ask holds this long.
static const NSTimeInterval kLyricsOnOpenWindow = 3;

static char kOverlayKey, kPlateKey, kTitleKey, kStackKey, kQueueKey, kQueuePageKey, kSliderKey;
// The Music app's lyrics view ends 3 pt over its time control's bar (measured on its player, 402 x 874 pt, 2026-11-25).
// Its lyrics view starts at the collapsed artwork's bottom (its content layout guide), and its lines' scroll view is
// inset so the sung line's top stands 12% of the player's height down, less the font's ascent, against the
// whole player's height.
static const CGFloat kLyricsOverBar = 3, kSungLineShare = 0.12;
// The page over the cover is up: in the one column with the lines or the queue, in the two columns the lines picked.
static BOOL sg_open;
// The one column's page shows the queue (SGRKeyPlayerQueueStyle's Apple Music style) rather than the lines: the same
// thumbnail, title row and stage, the queue page (PlayerQueue.m) in the stage. Never set in the two columns.
static BOOL sg_queuePage;
static __weak UIView *sg_dismissingPage;
static BOOL sg_moving;                      // the transition is in flight, so no layout pass may re-place it
static NSUInteger sg_openGeneration;        // only the latest accepted transition may settle
static __weak UIView *sg_host;              // SPTNowPlayingView
static __weak UIViewController *sg_info, *sg_duration, *sg_floating, *sg_header;
static __weak UIView *sg_titleElement;      // the arranged element view holding the title and the artist
static __weak UIViewController *sg_player;  // NowPlayingViewController, whose units the controls are
BOOL SGRPlayerInteractiveMorph(void) {
    return sg_player.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact &&
        sg_player.transitionCoordinator.initiallyInteractive;
}
static BOOL sg_alone;                       // the lines have the player to themselves
static BOOL sg_touching;                    // a finger is on the player, which holds the clock (SGRPlayerTouchWatcher)
static NSTimer *sg_rest;
static __weak UIGestureRecognizer *sg_wake; // on the player, on while alone: the tap that brings the controls back
// A flick on through the lines put them on their own, and they have not gone back to the song yet: until then a tap
// under them brings nothing back, only a flick back does (as in the Music app).
static BOOL sg_flickedAlone;
// The two column player: up, the footer's last pick of its side column (kept while the player stays open), and the
// mini player's ask for the lyrics, until when it holds.
typedef NS_ENUM(NSInteger, SGRSidePick) { SGRSidePickNone, SGRSidePickLyrics, SGRSidePickQueue };
static BOOL sg_wide;
static SGRSidePick sg_sidePick;
static CFTimeInterval sg_lyricsOnOpenUntil;
static BOOL sg_orderedForVoiceOver;         // the player's accessibilityElements are this file's
static __weak UIView *sg_replacedCoverList;
static void setOpen(BOOL open, BOOL animated);
static void forgetPreview(void);

// Issue #33: the pixels alone can't distinguish a narrower native tilt from
// a smaller image inside it. Capture the still-open page on app resign, not
// on the playback clock (and not after reopening, which restores the layout).
static NSString *geometryIn(UIView *host, UIView *view) {
    return [view isDescendantOfView:host] ? NSStringFromCGRect([host convertRect:view.bounds fromView:view]) : @"-";
}

static BOOL geometryVisible(UIView *view, UIView *root) {
    if (!view) return NO;
    for (UIView *v = view; v && v != root; v = v.superview)
        if (v.hidden || v.alpha < 0.01) return NO;
    return YES;
}

static void reportPlayerGeometry(void) {
    UIView *host = sg_host, *art = SGRPlayerShowingCover(), *tilt = art.superview;
    if (!host.window || sg_open || ![tilt isDescendantOfView:host]) return;
    UIView *cell = tilt;
    while (cell && ![cell isKindOfClass:UICollectionViewCell.class]) cell = cell.superview;
    __block UIView *preview = nil, *bitmap = nil;
    SGForEachView(cell, ^(UIView *v) {
        if ([v isKindOfClass:UIImageView.class] && !bitmap && [v isDescendantOfView:art] && geometryVisible(v, art)) bitmap = v;
        if ((SGClassNamed(v.class, @"LyricsElementWrapperView") || SGClassNamed(v.class, @"LyricsContainerView"))
            && v.bounds.size.height > preview.bounds.size.height) preview = v;
    });
    CGRect normal = SGRPlayerNormalCover(host, tilt, CGRectGetWidth(tilt.superview.bounds));
    SGLog(@"redesign player geometry: safe=%.1f column=%@ tilt=%@ normal=%@ art=%@ bitmap=%@ preview=%@ shown=%d masked=%d strip=%@",
          host.window.safeAreaInsets.top, geometryIn(host, tilt.superview), geometryIn(host, tilt), NSStringFromCGRect(normal),
          geometryIn(host, art), geometryIn(host, bitmap), geometryIn(host, preview), geometryVisible(preview, cell),
          preview.layer.mask != nil, geometryIn(host, sg_floating.viewIfLoaded));

    UIView *stack = SGRFindByIdentifier(host, @"npv.bottomStackView", &kStackKey);
    static char barKey, playKey, queueKey;
    UIView *bar = SGRFindByIdentifier(stack, @"SPTNowPlayingSliderV2", &barKey);
    UIView *play = SGRFindByIdentifier(stack, @"SPTNowPlayingPlayButton", &playKey);
    UIView *queue = SGRFindByIdentifier(stack, @"QueueButtonNowPlaying", &queueKey);
    UIView *volume = nil;
    for (UIView *v in stack.subviews) if ([v isKindOfClass:NSClassFromString(@"SGRVolumeRow")]) volume = v;
    __block UIView *slider = nil;
    SGForEachView(volume, ^(UIView *v) {
        if ([v isKindOfClass:UISlider.class] && geometryVisible(v, volume)) slider = v;
    });
    UIView *info = sg_info.viewIfLoaded, *row = sg_titleElement;
    while (row && row.superview != info) row = row.superview;
    SGLog(@"redesign player rows: stack=%@ row=%@ title=%@ bar=%@ play=%@ footerQueue=%@ volume=%@ slider=%@",
          geometryIn(host, stack), geometryIn(host, row), geometryIn(host, sg_titleElement), geometryIn(host, bar),
          geometryIn(host, play), geometryIn(host, queue), geometryIn(host, volume), geometryIn(host, slider));
}

// Restore the actual list we faded to full visibility, not a transient alpha captured during presentation.
static void replaceCoverList(BOOL replaced) {
    UIView *list = replaced ? SGRPlayerCoverList() : nil;
    if (list != sg_replacedCoverList) {
        sg_replacedCoverList.alpha = 1;
        sg_replacedCoverList = list;
    }
    if (list) list.alpha = 0;
}

#pragma mark - the wide player's control column

static BOOL wideIn(UIView *host) {
    if (!host || !SGRPlayerIPadRegular(host)) return NO;
    CGFloat width = SGRPlayerVisibleSafeArea(host).size.width;
    return width >= kColumnMinWidth + kColumnGap + kSideMinWidth;
}

static CGRect wideColumn(UIView *host) {
    CGRect safe = SGRPlayerVisibleSafeArea(host);
    CGFloat room = safe.size.width - kColumnGap;
    CGFloat share = safe.size.height > safe.size.width ? kColumnSharePortrait : kColumnShareLandscape;
    CGFloat width = round(MIN(MAX(room * share, kColumnMinWidth), room - kSideMinWidth));
    BOOL rtl = host.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    return CGRectMake(rtl ? CGRectGetMaxX(safe) - width : CGRectGetMinX(safe),
                      CGRectGetMinY(safe), width, safe.size.height);
}

// Narrow the actual stack, not a scaled snapshot: labels reflow and every button keeps its touch size.
// Only its external horizontal constraints are replaced; Spotify still owns its vertical layout and
// all the arranged views. Closing, or resizing below the breakpoint, restores those exact constraints.
@interface SGRLyricsColumn : NSObject
@property (nonatomic, weak) UIView *stack;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *original;
@property (nonatomic, strong) NSLayoutConstraint *left, *width;
@property (nonatomic) BOOL autoresizing;
@property (nonatomic) CGRect originalFrame;
@property (nonatomic) CGRect placedFrame;
@end
@implementation SGRLyricsColumn
@end

static char kColumnKey;
static BOOL sg_placingColumn;

static BOOL horizontalAttribute(NSLayoutAttribute attribute) {
    return attribute == NSLayoutAttributeLeft || attribute == NSLayoutAttributeRight
        || attribute == NSLayoutAttributeLeading || attribute == NSLayoutAttributeTrailing
        || attribute == NSLayoutAttributeCenterX || attribute == NSLayoutAttributeWidth;
}

static BOOL restoreColumn(SGRLyricsColumn *column) {
    if (column.autoresizing) {
        CGRect frame = column.stack.frame;
        // Restore only the horizontal values we still own; Spotify's latest vertical layout stays.
        if (frame.origin.x == column.placedFrame.origin.x) frame.origin.x = column.originalFrame.origin.x;
        if (frame.size.width == column.placedFrame.size.width) frame.size.width = column.originalFrame.size.width;
        if (CGRectEqualToRect(frame, column.stack.frame)) return NO;
        column.stack.frame = frame;
        return YES;
    }
    [NSLayoutConstraint deactivateConstraints:@[column.left, column.width]];
    [NSLayoutConstraint activateConstraints:column.original];
    return YES;
}

static void placeColumn(UIView *host, BOOL open) {
    if (!host || sg_placingColumn) return;
    sg_placingColumn = YES;
    BOOL changed = NO;
    SGRLyricsColumn *column = objc_getAssociatedObject(host, &kColumnKey);
    UIView *stack = open && wideIn(host) ? SGRFindByIdentifier(host, @"npv.bottomStackView", &kStackKey) : nil;
    if (!column && !stack) {
        sg_placingColumn = NO;
        return;
    }
    if (column && column.stack != stack) {
        changed = restoreColumn(column);
        objc_setAssociatedObject(host, &kColumnKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        column = nil;
        if (changed) [host setNeedsLayout];
    }
    if (stack && !column) {
        column = [SGRLyricsColumn new];
        column.stack = stack;
        column.autoresizing = stack.translatesAutoresizingMaskIntoConstraints;
        column.originalFrame = stack.frame;
        column.placedFrame = stack.frame;
        NSMutableArray *original = [NSMutableArray array];
        for (UIView *owner = stack; owner; owner = owner.superview) {
            for (NSLayoutConstraint *constraint in owner.constraints) {
                BOOL first = constraint.firstItem == stack && horizontalAttribute(constraint.firstAttribute);
                BOOL second = constraint.secondItem == stack && horizontalAttribute(constraint.secondAttribute);
                if (!constraint.active || (!first && !second)) continue;
                id other = first ? constraint.secondItem : constraint.firstItem;
                UIView *otherView = [other isKindOfClass:UILayoutGuide.class] ? [other owningView] : other;
                if ([otherView isKindOfClass:UIView.class] && [otherView isDescendantOfView:stack]) continue;
                [original addObject:constraint];
            }
        }
        column.original = original;
        [NSLayoutConstraint deactivateConstraints:original];
        if (original.count) changed = YES;
        if (!column.autoresizing) {
            column.left = [stack.leftAnchor constraintEqualToAnchor:host.leftAnchor];
            column.width = [stack.widthAnchor constraintEqualToConstant:wideColumn(host).size.width];
        }
        objc_setAssociatedObject(host, &kColumnKey, column, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (column) {
        CGRect frame = wideColumn(host);
        if (column.autoresizing) {
            CGRect placed = stack.frame;
            CGRect original = column.originalFrame;
            // A vertical-only change must not teach the saved frame our narrowed width.
            if (placed.origin.x != column.placedFrame.origin.x) original.origin.x = placed.origin.x;
            if (placed.size.width != column.placedFrame.size.width) original.size.width = placed.size.width;
            original.origin.y = placed.origin.y;
            original.size.height = placed.size.height;
            column.originalFrame = original;
            CGRect local = [host convertRect:frame toView:stack.superview];
            placed.origin.x = local.origin.x;
            placed.size.width = local.size.width;
            if (!CGRectEqualToRect(stack.frame, placed)) {
                stack.frame = placed;
                changed = YES;
            }
            column.placedFrame = placed;
        } else {
            CGFloat left = CGRectGetMinX(frame) - CGRectGetMinX(host.bounds);
            if (column.left.constant != left) {
                column.left.constant = left;
                changed = YES;
            }
            if (column.width.constant != frame.size.width) {
                column.width.constant = frame.size.width;
                changed = YES;
            }
            if (!column.left.active || !column.width.active) {
                [NSLayoutConstraint activateConstraints:@[column.left, column.width]];
                changed = YES;
            }
        }
    }
    if (changed) [host layoutIfNeeded];
    sg_placingColumn = NO;
}

SGRLyricsHide SGRLyricsHideMode(void) {
    NSInteger stored = SGInt(SGRKeyLyricsAutoHide, -1);
    return stored >= 0 ? stored : SGEnabled(SGRKeyLyricsAutoHide) ? SGRLyricsHideAll : SGRLyricsHideOff;
}

// Alone, the lines leave the header row, the thumbnail and the title row where they are, the way the Music
// app keeps its title over the lyrics.
static BOOL keepsTitle(void) {
    return SGRLyricsHideMode() == SGRLyricsHideControls;
}

#pragma mark - the overlay

// The thumbnail and the lines, side by side under one view so the lines' own view has no sibling of
// ours to hide: SGRKaraokeView takes the whole of whatever it is put in and dims what is next to it.
@interface SGRPlayerLyricsOverlay : UIView
@property (nonatomic, readonly) UIView *thumb;       // the cover, at full size, moved by its transform
@property (nonatomic, readonly) UIImageView *cover;
@property (nonatomic, readonly) UIView *stage;       // holds the lines' view alone, or the two columns' queue
@property (nonatomic, readonly) SGRKaraokeView *lyrics;
// The lines' view if it has been made, wherever it is, without putting it in the stage.
@property (nonatomic, readonly) SGRKaraokeView *madeLyrics;
@end

@implementation SGRPlayerLyricsOverlay {
    UIView *_thumb, *_stage;
    UIImageView *_cover;
    SGRKaraokeView *_lyrics;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _thumb = [[UIView alloc] initWithFrame:CGRectZero];
    // A tap on the cover beside the lines brings the full player back.
    [_thumb addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(sgr_thumbTapped)]];
    _thumb.isAccessibilityElement = YES;
    _thumb.accessibilityLabel = SGL(@"settings.player.lyrics.thumb_a11y", @"Show the player");
    _thumb.accessibilityTraits = UIAccessibilityTraitButton;
    _cover = [[UIImageView alloc] initWithFrame:CGRectZero];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.cornerCurve = kCACornerCurveContinuous;
    _cover.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_thumb addSubview:_cover];
    _stage = [[UIView alloc] initWithFrame:CGRectZero];
    [self addSubview:_stage];
    [self addSubview:_thumb];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateRendering)
                                               name:SGRPlayerVisibilityDidChangeNotification object:nil];
    return self;
}

- (void)updateRendering {
    _lyrics.renderingSuspended = self.hidden || SGRPlayerLandscapeCovers(self.window);
}

- (void)setHidden:(BOOL)hidden {
    [super setHidden:hidden];
    [self updateRendering];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateRendering];
}

- (void)sgr_thumbTapped {
    // Left on screen while the lines are alone (keepsTitle), a tap on it only wakes the controls (SGRPlayerWake). In the
    // two columns it is the player's cover, and the player is already all there.
    if (sg_open && !sg_moving && !sg_alone && !sg_wide) {
        forgetPreview();
        setOpen(NO, YES);
    }
}

- (UIView *)thumb { return _thumb; }
- (UIImageView *)cover { return _cover; }
- (UIView *)stage { return _stage; }
- (SGRKaraokeView *)madeLyrics { return _lyrics; }

// The lines seek when they are tapped and the thumbnail brings the player back, so everywhere else the
// overlay would only swallow touches: a view that takes them does, even with nothing on it.
//
// What it hands them to instead is the title row. Translated to the top of the player it is drawn well
// outside the stack view it is arranged in, and UIKit stops looking at a view whose bounds the touch is
// not in, so the add button and the menu that rode up with it are past Spotify's own reach. Asked here
// directly, the row answers for where it is drawn. Not while the lines are alone, unless the title is kept: the
// row is faded then, and a tap where its add button was is the player's, which brings everything back.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // The queue page's list reaches up behind the title row it carries: the row's buttons (add, ⋯) keep their taps, and
    // anywhere else there scrolls the list.
    UIView *carried = sg_open && sg_queuePage ? sg_info.viewIfLoaded : nil;
    if (carried && carried.alpha > 0.01) {
        UIView *inRow = [carried hitTest:[carried convertPoint:point fromView:self] withEvent:event];
        for (UIView *v = inRow; v && v != carried; v = v.superview) {
            if ([v isKindOfClass:UIControl.class]) return inRow;
        }
    }
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit != self) return hit;
    UIView *row = sg_open && (!sg_alone || keepsTitle()) ? sg_info.viewIfLoaded : nil;
    UIView *inRow = row ? [row hitTest:[row convertPoint:point fromView:self] withEvent:event] : nil;
    return inRow == row ? nil : inRow;
}

// Made on the first tap and kept afterward: it measures the song for its width before it can place a
// line, so a view built again on every tap would show nothing for the first frames. Out of the window
// it costs nothing -- its display link only runs while it is in one.
- (SGRKaraokeView *)lyrics {
    if (!_lyrics) {
        _lyrics = [[SGRKaraokeView alloc] initWithFrame:_stage.bounds];
        _lyrics.sizePlace = SGRLyricsPlacePlayer;
        _lyrics.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        // Sing's mic goes with the controls when the lines are on their own unless Keep the mic is on or Sing is
        // (setAlone sets it each time).
        _lyrics.keepsSing = YES;
        [self updateRendering];
    }
    if (_lyrics.superview != _stage) [_stage addSubview:_lyrics];
    _lyrics.frame = _stage.bounds;
    return _lyrics;
}

@end

static SGRPlayerLyricsOverlay *overlayIn(UIView *host) {
    SGRPlayerLyricsOverlay *overlay = objc_getAssociatedObject(host, &kOverlayKey);
    if (!overlay) {
        overlay = [[SGRPlayerLyricsOverlay alloc] initWithFrame:host.bounds];
        objc_setAssociatedObject(host, &kOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // On top of the player: it reaches from under the header row down to the progress bar, so it is over
    // the covers and the gradients and clear of every control. Under them instead, the mixing background
    // Spotify keeps between the two (01.txt:72) would be free to draw over the lines.
    // Kept on top here and in replace(): Spotify adds Mix's transition cards later, over the lines.
    if (overlay.superview != host) [host addSubview:overlay];
    else if (host.subviews.lastObject != overlay) [host bringSubviewToFront:overlay];
    return overlay;
}

void SGRPlayerPreparePortraitLyricsForReveal(void) {
    SGRPlayerLyricsOverlay *overlay = objc_getAssociatedObject(sg_host, &kOverlayKey);
    [overlay updateRendering];
}

#pragma mark - the measurements

typedef struct {
    BOOL ok;
    BOOL wide;
    CGRect cover;     // where Spotify draws the cover now, in the player
    CGRect thumb;     // where it goes
    CGRect stage;     // where the lines go
    CGFloat lift;     // how far the title row rises
    CGFloat shift;    // how far the title slides right to clear the thumbnail, 0 when it sits under it
    CGFloat head;     // the queue page: the room from the stage's top down to its toggles, the thumbnail and title in it
    CGFloat clear;    // how far up the thumbnail and title can go before a live header row's bottom; CGFLOAT_MAX with none
} SGRLyricsLayout;

// What a view's frame would be with the translation this file put on it left out.
static CGRect untransformed(UIView *view, UIView *host) {
    CGRect frame = SGFrameIn(view, host);
    CGAffineTransform t = view.transform;
    return CGRectOffset(frame, -t.tx, -t.ty);
}

static SGRLyricsLayout layoutIn(UIView *host, BOOL wide) {
    SGRLyricsLayout l = {0};
    UIView *info = sg_info.viewIfLoaded, *duration = sg_duration.viewIfLoaded, *title = sg_titleElement;
    if (!host || host.bounds.size.height < kLivingHeight || !info || !duration) return l;
    CGRect area = SGRPlayerArtworkAreaIn(host), cover = SGRPlayerCoverFrameIn(host);
    if (CGRectIsNull(area) || CGRectIsNull(cover)) return l;
    UIView *header = sg_header.viewIfLoaded;
    CGFloat contentTop = CGRectGetMinY(area);
    if ([header isDescendantOfView:host]) contentTop = MAX(contentTop, CGRectGetMaxY(SGFrameIn(header, host)));
    // During a resize the artwork band can extend behind the stationary header.
    BOOL bandBehindHeader = contentTop > CGRectGetMinY(area);
    if (host.window) contentTop = MAX(contentTop, CGRectGetMinY(SGRPlayerVisibleSafeArea(host)));
    CGRect row = untransformed(info, host), bar = untransformed(duration, host);
    if (wide) {
        CGRect safe = SGRPlayerVisibleSafeArea(host), column = wideColumn(host);
        CGFloat top = contentTop + kThumbTop;
        // The cover ends over the chips (Switch to video), which stay over the title in the column.
        CGFloat bottom = CGRectGetMinY(row);
        UIView *floating = sg_floating.viewIfLoaded;
        if (floating.window && !floating.hidden && floating.alpha > 0.01 && floating.bounds.size.height >= 1) {
            bottom = MIN(bottom, CGRectGetMinY(untransformed(floating, host)));
        }
        // As large as the column and the room over the stack allow, in the middle of that room as Spotify's own sits.
        CGFloat band = bottom - kLyricsTop - top;
        CGFloat side = floor(MIN(column.size.width - 2 * kColumnCoverInset, band));
        BOOL rtl = host.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
        CGFloat sideWidth = safe.size.width - column.size.width - kColumnGap;
        l.wide = YES;
        l.cover = cover;
        l.thumb = CGRectMake(round(CGRectGetMidX(column) - side / 2), round(top + (band - side) / 2), side, side);
        l.stage = CGRectMake(rtl ? CGRectGetMinX(safe) : CGRectGetMaxX(column) + kColumnGap,
                             top, sideWidth, CGRectGetMaxY(safe) - kLyricsBottom - top);
        l.ok = side >= kThumbSide && l.stage.size.height > kLivingHeight / 2;
        return l;
    }
    // The thumbnail takes the title's own leading edge, so the two line up down the page, and the title slides
    // toward its trailing side.
    BOOL rtl = host.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGRect titleFrame = title ? untransformed(title, host) : CGRectInset(area, SGRSideMargin, 0);
    CGFloat leading = rtl ? CGRectGetMaxX(titleFrame) - kThumbSide : CGRectGetMinX(titleFrame);
    l.cover = cover;
    CGFloat thumbTop = contentTop + kThumbTop;
    if (host.window) {
        CGFloat headerAwareTop = thumbTop;
        thumbTop = CGRectGetMinY(SGRPlayerVisibleSafeArea(host)) + kGrabberTopSpacing + kGrabberHeight + kArtworkToGrabberSpacing;
        if (bandBehindHeader) thumbTop = MAX(thumbTop, headerAwareTop);
    }
    // A header row whose controls stay on show (the AI DJ's buttons, an arrow kept to close by) keeps them clear: the
    // thumbnail stands under it, as the cover does.
    CGFloat rowBottom = SGRPlayerLiveRowBottomIn(host), underRow = rowBottom + kThumbTop;
    thumbTop = MAX(thumbTop, underRow);
    l.thumb = CGRectMake(leading, thumbTop, kThumbSide, kThumbSide);
    // Beside the thumbnail when the title can be moved clear of it, under it when it cannot be found.
    CGFloat top = title ? CGRectGetMidY(l.thumb) - row.size.height / 2 : CGRectGetMaxY(l.thumb) + SGRGrid;
    l.lift = top - CGRectGetMinY(row);
    l.shift = title ? (rtl ? -1 : 1) * (kThumbSide + kThumbGap) : 0;
    // The Music app's content (its lyrics, its queue) starts at the collapsed artwork's bottom. The lines fade
    // in under it on their own (SGRKaraokeView's edge fade); the queue's toggles stand kQueueTop under it.
    CGFloat lines = MAX(CGRectGetMaxY(l.thumb), top + row.size.height) + (sg_queuePage ? kQueueTop : 0);
    if (sg_alone && keepsTitle()) {
        // The header stays with the title, so the rise stops under a live row.
        CGFloat rise = MAX(0, MIN(kAloneRise, CGRectGetMinY(l.thumb) - underRow));
        l.thumb.origin.y -= rise;
        top -= rise;
        l.lift = top - CGRectGetMinY(row);
        if (title) l.shift = (rtl ? -1 : 1) * (kThumbSide + kAloneTitleGap);
        lines = MAX(CGRectGetMaxY(l.thumb), top + row.size.height) + kAloneLinesTop;
    }
    l.clear = rowBottom == -CGFLOAT_MAX ? CGFLOAT_MAX : MIN(CGRectGetMinY(l.thumb), top) - rowBottom;
    // The artwork band belongs to a paging cell: on a skip its x can still be between pages.
    // Only its vertical room belongs to the lyrics. The lyric viewport and its controls belong
    // to the stationary player, not the outgoing or incoming cover.
    // The queue page starts at the thumbnail's top: the thumbnail and the title stand in the room over its toggles and
    // ride with its list (the Music app's playing header is the first item of its queue).
    CGFloat stageTop = lines;
    if (sg_queuePage) {
        stageTop = CGRectGetMinY(l.thumb);
        l.head = lines - stageTop;
    }
    // The page reaches down to just over the bar itself, the slider inside the duration unit, as the Music app's lyrics
    // reach its time control; without the slider, kLyricsBottom over the unit.
    CGFloat bottom = CGRectGetMinY(bar) - kLyricsBottom;
    UIView *slider = SGRFindByIdentifier(duration, @"SPTNowPlayingSliderV2", &kSliderKey);
    if (slider.window && slider.bounds.size.height >= 1) {
        CGRect drawn = SGFrameIn(slider, host);
        bottom = CGRectGetMinY(drawn) - duration.transform.ty - kLyricsOverBar;
    }
    l.stage = CGRectMake(CGRectGetMinX(host.bounds), stageTop, host.bounds.size.width, bottom - stageTop);
    l.ok = l.stage.size.height - l.head > kLivingHeight / 2 && l.lift < 0;
    return l;
}

#pragma mark - the title row

// The unit's row lays its arranged views out after the unit's own pass, so the transforms go on after it. The title
// moved beside the thumbnail would run into the controls it moved toward, so PlayerTitle.x narrows it by as much.
// How far the queue page's list has moved from rest (positive up): the thumbnail and the title row ride with it.
static CGFloat sg_pageShift;

static CGFloat pageShift(void) {
    return sg_open && sg_queuePage && !sg_wide ? MIN(sg_pageShift, kRideMostUp) : 0;
}

static void placeTitleRow(SGRLyricsLayout l) {
    UIView *info = sg_info.viewIfLoaded;
    if (!info) return;
    [SGRowIn(info) layoutIfNeeded];
    CGFloat lift = sg_open ? l.lift - pageShift() : 0, shift = sg_open ? l.shift : 0;
    SGRShownTitleSlide(sg_titleElement ? fabs(round(shift)) : 0);
    // To the pixel, not the point: riding with the queue page's list, a whole point at a time stepped against rows that
    // move by the pixel, and the title looked to scroll at a lower rate than the list.
    CGFloat pixels = info.traitCollection.displayScale ?: UIScreen.mainScreen.scale;
    CGAffineTransform rise = CGAffineTransformMakeTranslation(0, round(lift * pixels) / pixels);
    if (!CGAffineTransformEqualToTransform(info.transform, rise)) info.transform = rise;
    UIView *title = sg_titleElement;
    if (!title) return;
    CGAffineTransform slide = CGAffineTransformMakeTranslation(round(shift), 0);
    if (!CGAffineTransformEqualToTransform(title.transform, slide)) title.transform = slide;
}

#pragma mark - opening and closing

BOOL SGRPlayerLyricsAvailable(void) {
    NSString *track = SGKaraokePlayingTrack();
    return track != nil && (SGKaraokeLinesForTrack(track) != nil || SGLyricsLoadFailed(track));
}

BOOL SGRPlayerLyricsOpen(void) {
    return sg_open && !sg_queuePage;
}

BOOL SGRPlayerPageOpen(void) {
    return sg_open;
}

BOOL SGRPlayerQueueShown(void) {
    return sg_wide ? !sg_open : sg_open && sg_queuePage;
}

// Puts the overlay's own views where the measurements say, without animating. The thumbnail is laid out
// at the size and place Spotify draws its cover at and moved by its transform alone, so a pass that
// runs while it is up leaves it exactly where the eye has it: the two are worked out from one
// measurement. Bounds and a center, not a frame, since both views can be under a transform.
static void place(SGRPlayerLyricsOverlay *overlay, UIView *host, SGRLyricsLayout l) {
    overlay.frame = l.wide ? host.bounds : CGRectUnion(l.cover, CGRectUnion(l.thumb, l.stage));
    CGRect cover = [overlay convertRect:l.cover fromView:host], stage = [overlay convertRect:l.stage fromView:host];
    overlay.thumb.bounds = (CGRect){CGPointZero, cover.size};
    overlay.thumb.center = CGPointMake(CGRectGetMidX(cover), CGRectGetMidY(cover));
    overlay.cover.frame = overlay.thumb.bounds;
    SGRShadowPlate *plate = SGRShadowPlateIn(overlay.thumb, &kPlateKey);
    plate.bounds = overlay.thumb.bounds;
    plate.center = CGPointMake(CGRectGetMidX(overlay.thumb.bounds), CGRectGetMidY(overlay.thumb.bounds));
    overlay.stage.bounds = (CGRect){CGPointZero, stage.size};
    overlay.stage.center = CGPointMake(CGRectGetMidX(stage), CGRectGetMidY(stage));
}

// Where the thumbnail's view has to go to land on `l.thumb`, as a transform about its own center: the
// shadow and the corners travel with it that way, instead of a shadow redrawn on every frame.
static CGAffineTransform thumbTransform(SGRLyricsLayout l) {
    CGFloat scale = l.cover.size.width > 0 ? l.thumb.size.width / l.cover.size.width : 1;
    CGAffineTransform move = CGAffineTransformMakeTranslation(round(CGRectGetMidX(l.thumb) - CGRectGetMidX(l.cover)),
                                                             round(CGRectGetMidY(l.thumb) - CGRectGetMidY(l.cover)));
    return CGAffineTransformConcat(CGAffineTransformMakeScale(scale, scale), move);
}

// The thumbnail where it stands while the page is up: moved with the queue page's list.
static CGAffineTransform pageThumbTransform(SGRLyricsLayout l) {
    return CGAffineTransformConcat(thumbTransform(l), CGAffineTransformMakeTranslation(0, -pageShift()));
}

// The thumbnail and the title row fade as the list carries them out of the page: up past its top, or down toward the
// progress bar, where the Music app's list fades them under its edges. They stand at the page's very top, and the Music
// app's list (whose first item they are) clips them there, so going up they are gone within kQueueRideFade rather than
// drawn over the grabber and the status bar. Under a live header row (PlayerArtwork.x) they are gone as they reach its
// bottom, sooner when there is less room, rather than drawn over its controls.
static CGFloat pageRideAlpha(SGRLyricsLayout l) {
    CGFloat shift = pageShift();
    if (shift > 0) {
        CGFloat fade = MIN(kQueueRideFade, l.clear);
        return fade > 0 ? MAX(0, MIN(1, 1 - shift / fade)) : 0;
    }
    CGFloat room = l.stage.size.height - l.head - kQueueRideFade;
    return MAX(0, MIN(1, 1 - (-shift - room) / kQueueRideFade));
}

// The corners as they will be drawn: a radius under a scale is drawn scaled, so the thumbnail asks for
// the radius it wants divided by the shrink, and the two ends of the animation are 12pt and 8pt corners.
static CGFloat thumbRadius(SGRLyricsLayout l, BOOL open) {
    if (!open) return SGRRadiusArtwork;
    CGFloat scale = l.cover.size.width > 0 ? l.thumb.size.width / l.cover.size.width : 1;
    return scale > 0 ? SGRRadiusCover / scale : SGRRadiusArtwork;
}

#pragma mark - the lines on their own

// After kRest without a touch while the song plays (kRestSinging while Sing is on), everything but the lines fades
// -- the header row, the thumbnail, the title row and the controls -- and the lines grow up and down into the whole
// safe area, the way the Music app leaves its lyrics alone. What brings it back or sends it away is as in the Music
// app: a tap on a line seeks there and changes
// nothing; a tap under the lines, where the controls were, brings it all back; a scroll decides as the finger lifts,
// a flick on toward the lines to come sending the controls away at once and a flick back bringing them back, while
// a scroll that stops dead changes nothing. A pause brings it back and keeps it; VoiceOver, a sheet over the
// player and the app in the background keep it up.
// Sing's mic stays with the lines only with Keep the mic or while Sing is on, and a touch on it is the mic's.
//
// The tap is a recognizer on the player that recognizes with any other, and a button takes its own tap:
// UIKit gives a control its tap over a tap recognizer above it. A faded view takes no touch (UIKit's hit
// test skips it), so a tap where a button was only wakes. A drag or a second finger fails it, and so does a touch
// over the lines' own place or on a line, which is the lines' own tap to seek with (SGRKaraokeView's touchIsOnLine:).

// What fades: every view of Spotify's bottom stack but the chips (gone while the lines are up), which is the
// title row, the progress bar, the buttons, the footer and a volume row where the phone has one; the header
// row's unit; and the thumbnail. Each fades by its alpha and the stack is left alone. Without the stack, the
// units by name. Only views on screen are taken, and only the ones faded (sg_faded) come back, so nothing
// Spotify keeps hidden is shown. Keeping the title, the header row, the thumbnail and the title row stay.
static NSHashTable<UIView *> *sg_faded;

static NSArray<UIView *> *fadingViews(void) {
    BOOL keeps = keepsTitle();
    UIView *floating = sg_floating.viewIfLoaded, *info = keeps ? sg_info.viewIfLoaded : nil;
    NSMutableArray<UIView *> *views = [NSMutableArray array];
    SGRPlayerLyricsOverlay *overlay = objc_getAssociatedObject(sg_host, &kOverlayKey);
    UIView *header = keeps ? nil : sg_header.viewIfLoaded, *thumb = keeps ? nil : overlay.thumb;
    if (header && !header.hidden && header.alpha > 0.01) [views addObject:header];
    if (thumb && !thumb.hidden && thumb.alpha > 0.01) [views addObject:thumb];
    UIView *stack = SGRFindByIdentifier(sg_host, @"npv.bottomStackView", &kStackKey);
    if (stack) {
        for (UIView *view in stack.subviews) {
            if ([floating isDescendantOfView:view] || [info isDescendantOfView:view]) continue;
            if (!view.hidden && view.alpha > 0.01) [views addObject:view];
        }
        return views;
    }
    static NSArray<NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @[@"InformationElementsUnit", @"DurationElementUnit", @"PlaybackControlsElementsUnit", @"FooterElementsUnit"];
    });
    // A unit's view answers to its controller as its next responder, wherever the unit sits in the tree.
    SGForEachView(sg_host, ^(UIView *view) {
        UIResponder *owner = view.nextResponder;
        if (![owner isKindOfClass:UIViewController.class] || ((UIViewController *)owner).viewIfLoaded != view) return;
        if (view == info) return;
        NSString *name = NSStringFromClass(owner.class);
        for (NSString *unit in names) {
            if ([name hasSuffix:unit] && !view.hidden && view.alpha > 0.01) [views addObject:view];
        }
    });
    return views;
}

static void fadeControls(BOOL faded) {
    if (!sg_faded) sg_faded = [NSHashTable weakObjectsHashTable];
    if (faded) {
        for (UIView *view in fadingViews()) {
            view.alpha = 0;
            [sg_faded addObject:view];
        }
    } else {
        for (UIView *view in sg_faded) view.alpha = 1;
        [sg_faded removeAllObjects];
    }
}

BOOL SGRPlayerLyricsFadeView(UIView *view, BOOL fits) {
    if (!view) return NO;
    if (!fits) {
        view.alpha = 0;
        [sg_faded removeObject:view];
        return YES;
    }
    if (!sg_alone) return NO;
    view.alpha = 0;
    if (!sg_faded) sg_faded = [NSHashTable weakObjectsHashTable];
    [sg_faded addObject:view];
    return YES;
}

// Where the lines go on their own: the whole safe area, kLyricsBottom in at both ends, over everything that
// faded. The safe area keeps them from under the status bar and the Dynamic Island. Keeping the title, they
// start where they did under it and grow down alone.
static CGRect aloneStage(UIView *host, SGRLyricsLayout l) {
    CGRect safe = UIEdgeInsetsInsetRect(host.bounds, host.safeAreaInsets);
    CGFloat top = keepsTitle() ? CGRectGetMinY(l.stage) : CGRectGetMinY(safe) + kLyricsBottom;
    return CGRectMake(CGRectGetMinX(l.stage), top, l.stage.size.width, CGRectGetMaxY(safe) - kLyricsBottom - top);
}

// The lines' tap seeks alone or not: a tap on a line is the lines', never the wake's (SGRPlayerWake).
static void letLinesSeek(SGRPlayerLyricsOverlay *overlay, BOOL seek) {
    for (UIGestureRecognizer *recognizer in overlay.lyrics.gestureRecognizers) {
        if ([recognizer isKindOfClass:UITapGestureRecognizer.class]) recognizer.enabled = seek;
    }
}

static void setAlone(BOOL alone, BOOL animated);

// Keeping the title, the lines alone rest their sung line where the Music app's does (kAloneLineTop); otherwise at
// their own share of the height.
static void anchorLines(SGRPlayerLyricsOverlay *overlay, SGRLyricsLayout l) {
    BOOL fixed = sg_alone && keepsTitle() && !l.wide;
    UIView *player = overlay.superview ?: overlay.lyrics.window;
    CGFloat sung = MAX(1, round(player.bounds.size.height * kSungLineShare - overlay.lyrics.lineAscent));
    overlay.lyrics.anchorTop = fixed ? MAX(1, kAloneLineTop - CGRectGetMinY(l.stage)) : l.wide || sg_alone ? 0 : sung;
}

// A sheet, a menu or an alert over the player: the top controller on screen is not one the player is drawn
// in. The queue, devices and ⋯ sheets can be presented from the player's topmost parent rather than the
// player, which the player's own presentedViewController would miss, and Sing's explanation is an alert on
// the top controller (SGRSingButton.m).
static BOOL coveredBySheet(void) {
    UIViewController *top = SGTopController();
    UIView *host = sg_host;
    if (!top.viewIfLoaded || !host || [host isDescendantOfView:top.viewIfLoaded]) return NO;
    static NSUInteger logged;
    if (logged++ < 3) SGLog(@"redesign player: %@ over the player keeps the controls up", NSStringFromClass(top.class));
    return YES;
}

// Whether the clock runs: the lines up with the controls, the song playing with the app in front, no finger
// on the player and VoiceOver off (which keeps the controls up, and starts the clock again when it goes).
static BOOL mayCount(void) {
    SPTPlayerState *state = SGPlayerState();
    UIView *host = sg_host;
    return !sg_wide && SGRLyricsHideMode() != SGRLyricsHideOff && sg_open && !sg_queuePage && !sg_alone && !sg_touching && host.window && state && !state.isPaused
        && !UIAccessibilityIsVoiceOverRunning()
        && UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
}

// Whether the controls may fade as it runs out: not under a sheet, nor while Sing gets ready.
static BOOL mayRest(void) {
    return mayCount() && !coveredBySheet() && SGSingCurrentState() != SGSingStatePreparing;
}

// The clock starts again at every touch. Run out while something keeps the controls up (a sheet, Sing getting
// ready, lines still being measured), it starts over, so they fade once that has gone.
static void restartRestAfter(NSTimeInterval wait) {
    [sg_rest invalidate];
    sg_rest = nil;
    if (!mayCount()) return;
    sg_rest = [NSTimer scheduledTimerWithTimeInterval:wait repeats:NO block:^(NSTimer *timer) {
        sg_rest = nil;
        if (mayRest()) setAlone(YES, YES);
        if (!sg_alone) restartRestAfter(kRest);
    }];
}

static void restartRest(void) {
    restartRestAfter(kRest);
}

// Sing on, the vocals down: the Music app gives the controls a second longer when the song starts playing again.
static BOOL singing(void) {
    SGSingState sing = SGSingCurrentState();
    return sing >= SGSingStateWaiting && sing <= SGSingStateHot;
}

// A scroll through the lines decides as the finger lifts. Going on toward the lines to come, the controls go at once
// (whether the song plays or not, as the Music app's do) and stay gone until a flick back or the lines go back to the
// song; going back, they come back and the clock starts again.
static void linesFlicked(CGFloat velocity) {
    if (velocity > 0) {
        if (sg_flickedAlone) return;
        sg_flickedAlone = YES;
        if (sg_wide || SGRLyricsHideMode() == SGRLyricsHideOff || !sg_open || UIAccessibilityIsVoiceOverRunning() || coveredBySheet()
            || SGSingCurrentState() == SGSingStatePreparing) return;
        setAlone(YES, YES);
    } else if (velocity < 0) {
        sg_flickedAlone = NO;
        setAlone(NO, YES);
        restartRest();
    }
}

@interface SGRPlayerTouchWatcher : UIGestureRecognizer <UIGestureRecognizerDelegate>
@end

// Only while waiting. A subsequent touch may be outside the host (e.g. on a sheet);
// observe its arrival without entering recognition or delaying another recognizer.
@interface SGRPendingPreview : UIGestureRecognizer <UIGestureRecognizerDelegate>
@property (copy) NSString *track;
@end
static SGRPendingPreview *sg_pendingPreview;
static void forgetPreview(void) {
    [sg_pendingPreview.view removeGestureRecognizer:sg_pendingPreview];
    sg_pendingPreview = nil;
}
@implementation SGRPendingPreview
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    forgetPreview();
    return NO;
}
@end

// Sees every touch on the player and takes none. It never recognizes: it holds the clock while a finger is
// down, so a hold on Sing's slider that runs past the rest fades nothing under it, and starts the clock once
// the last finger lifts. Nothing can end its watch early, or a scroll or a hold that recognized would start
// the clock under the finger.
@implementation SGRPlayerTouchWatcher
- (instancetype)init {
    if (!(self = [super initWithTarget:nil action:nil])) return nil;
    self.delegate = self;
    self.cancelsTouchesInView = NO;
    self.delaysTouchesBegan = NO;
    self.delaysTouchesEnded = NO;
    return self;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}
- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)other {
    return NO;
}
- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)other {
    return NO;
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    sg_touching = YES;
    SGRProgressVisibilityChanged();
    [sg_rest invalidate];
    sg_rest = nil;
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self lifted:event];
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self lifted:event];
}
- (void)lifted:(UIEvent *)event {
    for (UITouch *touch in [event touchesForGestureRecognizer:self]) {
        if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled) return;
    }
    self.state = UIGestureRecognizerStateFailed;
}
// After the last finger, or the watch ended any other way.
- (void)reset {
    [super reset];
    if (!sg_touching) return;
    sg_touching = NO;
    if (!sg_alone) restartRest();
}
@end

@interface SGRPlayerWake : UITapGestureRecognizer <UIGestureRecognizerDelegate>
@end

// Takes no touch from anything under it, and lets every other recognizer have the same tap.
@implementation SGRPlayerWake
- (instancetype)init {
    if (!(self = [super initWithTarget:nil action:nil])) return nil;
    [self addTarget:self action:@selector(sgr_woke)];
    self.delegate = self;
    self.cancelsTouchesInView = NO;
    self.delaysTouchesEnded = NO;
    self.enabled = NO;
    return self;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}
// Sing's mic and its slider stay while the lines are alone, and a touch on them is theirs alone. So is a tap on a
// line: it seeks there and the lines stay alone. As in the Music app, only
// a tap under the lines' place with the controls up, where the controls were, brings them back, and not while a
// flick on sent them away (sg_flickedAlone).
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    UIView *host = sg_host;
    if (!host) return NO;
    for (UIView *v = touch.view; v; v = v.superview) {
        if ([v isKindOfClass:SGRSingButton.class]) return NO;
    }
    SGRPlayerLyricsOverlay *overlay = objc_getAssociatedObject(host, &kOverlayKey);
    // Plain text never seeks or resumes following the song after a flick.
    if (overlay.lyrics.untimed) return YES;
    if (sg_flickedAlone) return NO;
    if (overlay.superview && [overlay.lyrics touchIsOnLine:touch]) return NO;
    SGRLyricsLayout l = layoutIn(host, sg_wide);
    if (l.ok && [touch locationInView:host].y <= CGRectGetMaxY(l.stage)) return NO;
    return YES;
}
- (void)sgr_woke {
    sg_flickedAlone = NO;
    setAlone(NO, YES);
    restartRest();
}
@end

static void setAlone(BOOL alone, BOOL animated) {
    UIView *host = sg_host;
    // The two columns deliberately keep the cover and controls beside the lines, even while browsing.
    if (alone && sg_wide) return;
    if (alone == sg_alone || !host || (alone && (!sg_open || sg_queuePage))) return;
    SGRLyricsLayout l = layoutIn(host, sg_wide);
    // Going alone needs somewhere to put the lines. Coming back never waits for it: the controls and the
    // lines' tap are given back even when the player can no longer be measured.
    if (alone && !l.ok) return;
    static NSUInteger fadeGeneration;
    NSUInteger generation = ++fadeGeneration;
    sg_alone = alone;
    // Keeping the title, the header itself moves as the lines go alone (layoutIn), so it is measured again.
    if (keepsTitle()) {
        SGRLyricsLayout moved = layoutIn(host, sg_wide);
        if (moved.ok) l = moved;
    }
    if (!alone) SGRProgressControlsFaded(NO);
    if (alone) {
        [sg_rest invalidate];
        sg_rest = nil;
        l.stage = aloneStage(host, l);
    }
    SGRPlayerLyricsOverlay *overlay = objc_getAssociatedObject(host, &kOverlayKey);
    // Layout and opacity have their own timing; Reduce Motion dissolves the layout in place.
    void (^move)(void) = ^{
        if (!overlay.superview || !l.ok) return;
        if (keepsTitle()) placeTitleRow(l);
        place(overlay, host, l);
        anchorLines(overlay, l);
        overlay.thumb.transform = thumbTransform(l);
        // The lines take the new height in this same spring, so the sung line rides with the stage rather than
        // springing to the new anchor at the next line (SGRKaraokeView's layoutSubviews).
        [overlay.lyrics layoutIfNeeded];
    };
    void (^fade)(void) = ^{
        if (overlay.superview) {
            // The mic goes with the controls as the Music app's does, unless it is to stay or Sing is on.
            SGSingState sing = SGSingCurrentState();
            overlay.lyrics.keepsSing = SGFlag(SGRKeyLyricsKeepMic, YES) || sing >= SGSingStateWaiting;
            overlay.lyrics.extrasHidden = alone;
        }
        fadeControls(alone);
    };
    sg_wake.enabled = alone;
    // The lines' tap seeks whether or not they are alone (SGRPlayerWake leaves a tap on a line to them).
    if (overlay) letLinesSeek(overlay, YES);
    if (animated) {
        SGRAnimateLayout(host, move, nil);
        // Going, the controls take their time, since nobody waits on them; coming back at a touch, they answer at
        // once, from wherever the fade out has got to.
        SGRAnimate(alone ? SGRMotionFade : SGRMotionRespond, fade, ^(BOOL finished) {
            if (alone && finished && generation == fadeGeneration) SGRProgressControlsFaded(YES);
        });
    } else {
        move();
        fade();
        if (alone) SGRProgressControlsFaded(YES);
    }
    SGLog(@"redesign player: the lines %@", alone ? @"on their own" : @"with the controls");
}

#pragma mark - the lines or the queue

// The queue page shares nothing with the two columns' list: it is the Music app's (PlayerQueue.m), with its toggles and
// rows of its own. Contained by the player that shows it, so UIKit hands it traits and its appearance.
static UIViewController *queuePageOf(SGRPlayerLyricsOverlay *overlay) {
    UIViewController *page = objc_getAssociatedObject(overlay, &kQueuePageKey);
    if (!page) {
        page = SGRPlayerQueuePage();
        page.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        objc_setAssociatedObject(overlay, &kQueuePageKey, page, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIViewController *player = sg_player;
    if (player && page.parentViewController != player) {
        if (page.parentViewController) {
            [page willMoveToParentViewController:nil];
            [page removeFromParentViewController];
        }
        [player addChildViewController:page];
        [page didMoveToParentViewController:player];
    }
    return page;
}

// The lines' handlers, set each time they come into the stage: a scroll decides by its flick as the finger lifts
// (linesFlicked); once the lines follow the song again, a tap under them can bring the controls back.
static void armLines(SGRPlayerLyricsOverlay *overlay) {
    sg_flickedAlone = NO;
    overlay.lyrics.browsingBegan = nil;
    overlay.lyrics.browsingFlicked = ^(CGFloat velocity) { linesFlicked(velocity); };
    overlay.lyrics.browsingEnded = ^{ sg_flickedAlone = NO; };
}

// The one column's stage shows the lines or the queue page, crossfading when animated. The one going leaves the stage,
// so the lines' display link stops while the queue shows and the queue's list stops asking for covers.
static void fillStage(SGRPlayerLyricsOverlay *overlay, BOOL queue, BOOL animated) {
    // Made the first time the queue is asked for; the lines alone never make it.
    UIView *page = queue ? queuePageOf(overlay).view : ((UIViewController *)objc_getAssociatedObject(overlay, &kQueuePageKey)).viewIfLoaded;
    UIView *lines = overlay.madeLyrics;
    BOOL wasIn = queue ? page.superview == overlay.stage : lines.superview == overlay.stage;
    UIView *going = queue ? lines : page;
    BOOL fades = animated && going.superview == overlay.stage;
    UIView *showing = queue ? page : overlay.lyrics;   // the lines' getter puts them in the stage
    if (queue && !wasIn) [overlay.stage addSubview:page];
    if (!wasIn) showing.alpha = fades ? 0 : 1;
    showing.frame = overlay.stage.bounds;
    showing.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    if (!queue) armLines(overlay);
    void (^swap)(void) = ^{
        showing.alpha = 1;
        going.alpha = 0;
    };
    void (^gone)(BOOL) = ^(BOOL finished) {
        // The lines faded back in by their alpha: their corner buttons' glass drawn again (SGRRefreshGlass).
        if (fades && !queue && sg_open && !sg_queuePage) [overlay.madeLyrics refreshGlass];
        // Shown again before the fade ended: it stays.
        if (sg_open && !sg_wide && sg_queuePage == (going == page)) return;
        if (going.superview == overlay.stage) [going removeFromSuperview];
        going.alpha = 1;
    };
    if (fades) SGRAnimate(SGRMotionFade, swap, gone);
    else {
        swap();
        gone(YES);
    }
}

// The layout the queue page was last placed with, for moving the thumbnail and the title row as its list scrolls.
static SGRLyricsLayout sg_pageLayout;

static void ridePage(void) {
    SGRPlayerLyricsOverlay *overlay = objc_getAssociatedObject(sg_host, &kOverlayKey);
    SGRLyricsLayout l = sg_pageLayout;
    if (!overlay.superview || sg_moving || !l.ok || !sg_open || !sg_queuePage) return;
    overlay.thumb.transform = pageThumbTransform(l);
    placeTitleRow(l);
    CGFloat alpha = pageRideAlpha(l);
    if (overlay.thumb.alpha != alpha) overlay.thumb.alpha = alpha;
    UIView *info = sg_info.viewIfLoaded;
    if (info && info.alpha != alpha) info.alpha = alpha;
}

// The queue page told the room over its toggles, and given the way to move the thumbnail and title with its list.
static void configurePage(SGRPlayerLyricsOverlay *overlay, SGRLyricsLayout l) {
    sg_pageLayout = l;
    SGRPlayerQueuePageConfigure(queuePageOf(overlay), l.head, ^(CGFloat shift) {
        // Every pixel of the list's move (PlayerQueue.m reports it to the pixel), not every half point.
        if (fabs(shift - sg_pageShift) < 0.01) return;
        sg_pageShift = shift;
        ridePage();
    });
}

// Back to rest, the thumbnail and the title row seen whole.
static void stopRiding(void) {
    sg_pageShift = 0;
    SGRPlayerLyricsOverlay *overlay = objc_getAssociatedObject(sg_host, &kOverlayKey);
    if (overlay.thumb.alpha < 1 && !sg_alone) overlay.thumb.alpha = 1;
    UIView *info = sg_info.viewIfLoaded;
    if (info && info.alpha < 1 && !sg_alone) info.alpha = 1;
}

// The open page turns from the lines to the queue or back, the thumbnail and the title row staying where they are.
static void switchPage(BOOL queue) {
    SGRPlayerLyricsOverlay *overlay = objc_getAssociatedObject(sg_host, &kOverlayKey);
    if (!sg_open || sg_wide || sg_queuePage == queue || !overlay.superview) return;
    setAlone(NO, NO);
    stopRiding();
    sg_queuePage = queue;
    // The queue's stage starts at the thumbnail's top, the lines' under the title row.
    SGRLyricsLayout l = layoutIn(sg_host, NO);
    if (l.ok) {
        place(overlay, sg_host, l);
        overlay.thumb.transform = thumbTransform(l);
        placeTitleRow(l);
    }
    fillStage(overlay, queue, YES);
    if (queue && l.ok) configurePage(overlay, l);
    if (queue) {
        [sg_rest invalidate];
        sg_rest = nil;
    } else {
        if (l.ok) anchorLines(overlay, l);
        restartRest();
    }
    SGRPlayerLyricsChanged();
    SGLog(@"redesign player: the page shows the %@", queue ? @"queue" : @"lyrics");
}

static void setOpen(BOOL open, BOOL animated) {
    UIView *host = sg_host;
    if (open == sg_open) return;
    if (!host) {
        SGLog(@"redesign player: the lyrics were asked for before the player laid out");
        return;
    }
    SGRLyricsLayout l = layoutIn(host, sg_wide);
    if (open && !l.ok) {
        SGLog(@"redesign player: the lyrics have nowhere to go (stage %.0fx%.0f, lift %.0f)", l.stage.size.width, l.stage.size.height, l.lift);
        return;
    }
    // The thumbnail is the Kit's picture drawn again, and Spotify's cover goes as it appears: without a
    // picture there would be a hole where the cover was, so the cover stays and the lyrics wait.
    UIImage *picture = SGRNowPlayingArtwork(NULL, NULL);
    if (open && !picture) {
        SGLog(@"redesign player: no artwork read yet, the lyrics stay down");
        return;
    }
    NSUInteger generation = ++sg_openGeneration;
    if (!open) setAlone(NO, NO);
    // Closing from a scrolled queue page, the thumbnail flies home from where the list carried it.
    CGFloat riding = pageShift();
    stopRiding();
    sg_open = open;
    SGRPlayerLyricsChanged();

    SGRPlayerLyricsOverlay *overlay = overlayIn(host);
    place(overlay, host, l);
    CGAffineTransform away = thumbTransform(l);
    // Over an animated artwork the cover is hidden, so the thumbnail fades where it sits rather than flying
    // to or from an empty slot.
    BOOL fades = SGRPlayerMotionShowing();
    // The state it starts from, so the animation has both ends of every value and nothing jumps into it.
    overlay.thumb.transform = open && !fades ? CGAffineTransformIdentity
                            : CGAffineTransformConcat(away, CGAffineTransformMakeTranslation(0, open ? 0 : -riding));
    overlay.thumb.alpha = open && fades ? 0 : 1;
    overlay.cover.layer.cornerRadius = thumbRadius(l, fades || !open);
    // Under Reduce Motion the lines only fade, without growing.
    CGAffineTransform entering = SGRReduceMotion() ? CGAffineTransformIdentity : CGAffineTransformMakeScale(kLyricsEnterScale, kLyricsEnterScale);
    if (open) {
        overlay.cover.image = SGRNowPlayingArtwork(NULL, NULL);
        overlay.stage.alpha = 0;
        overlay.stage.transform = entering;
        fillStage(overlay, sg_queuePage, NO);
        if (sg_queuePage) configurePage(overlay, l);
        // Spotify's cover goes the moment the redesign's own takes its place: the same picture at the
        // same size with the same corners, so there is nothing to see in the swap. Coming back it waits
        // for the thumbnail to land on it, or the two would be on screen at once, one of them half size.
        replaceCoverList(YES);
    }

    // Moves and fades apart, as in setAlone: Reduce Motion takes the move and keeps the thumbnail's fade over
    // an animated artwork and the chips'.
    void (^move)(void) = ^{
        overlay.thumb.transform = open || fades ? away : CGAffineTransformIdentity;
        overlay.cover.layer.cornerRadius = thumbRadius(l, open || fades);
        placeTitleRow(l);
    };
    void (^fade)(void) = ^{
        overlay.thumb.alpha = !open && fades ? 0 : 1;
        sg_floating.viewIfLoaded.alpha = open ? 0 : 1;
    };
    void (^show)(void) = ^{
        overlay.stage.alpha = open ? 1 : 0;
        overlay.stage.transform = open ? CGAffineTransformIdentity : entering;
    };
    void (^settled)(BOOL) = ^(BOOL finished) {
        if (generation != sg_openGeneration) return;
        sg_moving = NO;
        // The stage faded in by its alpha, which can leave the corner buttons' glass undrawn (SGRRefreshGlass).
        if (sg_open && !sg_queuePage) [overlay.madeLyrics refreshGlass];
        if (sg_open) return;   // opened again while it was going away
        replaceCoverList(NO);
        // The queue page leaves the stage with the page, and the next one opens on the lines unless it is asked for.
        UIViewController *queuePage = objc_getAssociatedObject(overlay, &kQueuePageKey);
        if (queuePage.viewIfLoaded.superview == overlay.stage) [queuePage.view removeFromSuperview];
        sg_queuePage = NO;
        // Detaching the karaoke view resets its browsing position. Keep it in the window, invisible,
        // until UIKit commits the interactive dismissal.
        if (overlay == sg_dismissingPage) overlay.hidden = YES;
        else [overlay removeFromSuperview];
        // The window may have resized while the animation owned placement.
        [host setNeedsLayout];
    };

    if (!animated) {
        move();
        fade();
        show();
        settled(YES);
    } else {
        sg_moving = YES;
        // Settled once both the layout transition and the fade are done.
        __block NSInteger running = 2;
        void (^done)(BOOL) = ^(BOOL finished) {
            if (--running == 0) settled(finished);
        };
        SGRAnimateLayout(host, move, done);
        SGRAnimate(SGRMotionFade, fade, done);
        // The lines come in behind the cover leaving, and go before it comes back.
        [UIView animateWithDuration:open ? kLyricsIn : kLyricsOut delay:open ? kLyricsInDelay : 0
                            options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:show completion:nil];
    }
    if (open) restartRest();
    else {
        [sg_rest invalidate];
        sg_rest = nil;
    }
    SGLog(@"redesign player: %@ %@, thumbnail %.0fx%.0f at %.0f,%.0f, title row up %.0f and right %.0f, stage %.0fx%.0f",
          sg_queuePage ? @"queue" : @"lyrics", open ? @"up" : @"away", l.thumb.size.width, l.thumb.size.height, l.thumb.origin.x, l.thumb.origin.y,
          -l.lift, l.shift, l.stage.size.width, l.stage.size.height);
}

#pragma mark - the two columns

BOOL SGRPlayerTwoColumns(void) {
    return sg_wide;
}

BOOL SGRPlayerQueueSideShown(void) {
    return sg_wide && !sg_open;
}

// The side column's lyrics unless the queue was picked or the track has none: lines still being looked for keep the
// lyrics up through the grace a new track has (SGRPlayerLyricsNone), as the narrow player's lines stay up.
static BOOL sideWantsLyrics(void) {
    if (sg_sidePick == SGRSidePickQueue) return NO;
    return SGRPlayerLyricsAvailable() || (sg_open && !SGRPlayerLyricsNone());
}

// The queue shares its sheet's controller, contained by the existing player so UIKit delivers traits and lifecycle.
static UIViewController *queueListOf(SGRPlayerLyricsOverlay *overlay) {
    UIViewController *list = objc_getAssociatedObject(overlay, &kQueueKey);
    if (!list) {
        list = SGRPlayerQueueList();
        list.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        [sg_player addChildViewController:list];
        [list didMoveToParentViewController:sg_player];
        objc_setAssociatedObject(overlay, &kQueueKey, list, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return list;
}

// The side column shows the lines or the queue, crossfading when animated; the one going leaves the column, so the
// lines' display link stops while the queue shows.
static void showSide(SGRPlayerLyricsOverlay *overlay, BOOL lyrics, BOOL animated) {
    UIView *queue = queueListOf(overlay).view;
    UIView *showing = lyrics ? overlay.lyrics : queue, *going = lyrics ? queue : overlay.madeLyrics;
    if (showing.superview != overlay.stage) {
        showing.alpha = animated ? 0 : 1;
        [overlay.stage addSubview:showing];
    }
    showing.frame = overlay.stage.bounds;
    showing.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    BOOL changed = sg_open != lyrics;
    sg_open = lyrics;
    void (^swap)(void) = ^{
        showing.alpha = 1;
        going.alpha = 0;
    };
    void (^gone)(BOOL) = ^(BOOL finished) {
        if (animated && lyrics && sg_open) [overlay.madeLyrics refreshGlass];
        // Shown again before the fade ended: it stays.
        if (sg_wide && (going == queue ? !sg_open : sg_open)) return;
        [going removeFromSuperview];
        going.alpha = 1;
    };
    if (animated && going.superview) SGRAnimate(SGRMotionFade, swap, gone);
    else {
        swap();
        gone(YES);
    }
    if (!changed) return;
    SGRPlayerLyricsChanged();
    SGLog(@"redesign player: the side column shows the %@", lyrics ? @"lyrics" : @"queue");
}

static void refreshSide(BOOL animated) {
    SGRPlayerLyricsOverlay *overlay = objc_getAssociatedObject(sg_host, &kOverlayKey);
    if (sg_wide && overlay.superview) showSide(overlay, sideWantsLyrics(), animated);
}

static void pickSide(SGRSidePick pick) {
    sg_sidePick = pick;
    refreshSide(YES);
}

// VoiceOver reads the leading column before the side column: it would otherwise go by position, row by row, and read
// the lines at the top of the side column before the controls at the foot of the leading one. The player's own views
// in the order they stand, then the overlay. Left alone when Spotify gives the player an order of its own.
static void orderForVoiceOver(UIView *host, UIView *overlay) {
    if (host.accessibilityElements && !sg_orderedForVoiceOver) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGLog(@"redesign player: the player has an accessibility order of Spotify's, kept"); });
        return;
    }
    NSMutableArray<UIView *> *views = [NSMutableArray array];
    for (UIView *view in host.subviews) if (view != overlay) [views addObject:view];
    [views sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGFloat ya = CGRectGetMinY(a.frame), yb = CGRectGetMinY(b.frame);
        return ya < yb ? NSOrderedAscending : ya > yb ? NSOrderedDescending : NSOrderedSame;
    }];
    [views addObject:overlay];
    if (![host.accessibilityElements isEqualToArray:views]) host.accessibilityElements = views;
    sg_orderedForVoiceOver = YES;
}

static void leaveWide(UIView *host) {
    if (!sg_wide) return;
    sg_wide = NO;
    sg_open = NO;
    SGRPlayerLyricsOverlay *overlay = objc_getAssociatedObject(host, &kOverlayKey);
    UIView *queue = queueListOf(overlay).view, *lines = overlay.madeLyrics;
    [queue removeFromSuperview];
    [lines removeFromSuperview];
    queue.alpha = lines.alpha = 1;
    [overlay removeFromSuperview];
    overlay.thumb.isAccessibilityElement = YES;
    placeColumn(host, NO);
    placeTitleRow((SGRLyricsLayout){0});
    if (sg_orderedForVoiceOver) host.accessibilityElements = nil;
    sg_orderedForVoiceOver = NO;
    replaceCoverList(NO);
    sg_floating.viewIfLoaded.alpha = 1;
    SGRPlayerLyricsChanged();
    SGRPlayerLookChanged();
    SGLog(@"redesign player: one column again (%.0f pt wide)", host.bounds.size.width);
}

// The columns put in place without animating: Spotify's stack in the leading one, the cover over it, the side column
// beside them. Nothing until the player can be measured and the cover's picture has been read.
static void placeWide(UIView *host) {
    // Fit uses Spotify's vertical geometry, not our narrowed width. Reject before touching its stack,
    // so a missing cover or a short opening frame cannot install and restore constraints on every pass.
    SGRLyricsLayout l = layoutIn(host, YES);
    UIImage *picture = SGRNowPlayingArtwork(NULL, NULL);
    if (!l.ok || !picture) {
        if (!l.ok) leaveWide(host);
        return;
    }
    placeColumn(host, YES);
    BOOL entering = !sg_wide;
    sg_wide = YES;
    SGRPlayerLyricsOverlay *overlay = overlayIn(host);
    // The cover stands where the column wants it, untransformed, with the player's own corners.
    l.cover = l.thumb;
    place(overlay, host, l);
    overlay.thumb.transform = CGAffineTransformIdentity;
    overlay.thumb.alpha = 1;
    overlay.thumb.isAccessibilityElement = NO;
    overlay.cover.layer.cornerRadius = thumbRadius(l, NO);
    if (overlay.cover.image != picture) overlay.cover.image = picture;
    overlay.stage.alpha = 1;
    overlay.stage.transform = CGAffineTransformIdentity;
    placeTitleRow(l);
    sg_floating.viewIfLoaded.alpha = 1;
    replaceCoverList(YES);
    showSide(overlay, sideWantsLyrics(), NO);
    orderForVoiceOver(host, overlay);
    if (!entering) return;
    // The footer lays out again for its queue glyph.
    SGRPlayerLookChanged();
    SGLog(@"redesign player: two columns, the stack %@, the cover %@, the side %@", NSStringFromCGRect(wideColumn(host)),
          NSStringFromCGRect(l.thumb), NSStringFromCGRect(l.stage));
}

void SGRPlayerToggleLyrics(void) {
    forgetPreview();
    if (sg_wide) {
        pickSide(SGRSidePickLyrics);
        return;
    }
    if (sg_open && sg_queuePage) {
        if (SGRPlayerLyricsAvailable()) switchPage(NO);
        return;
    }
    if (!sg_open && !SGRPlayerLyricsAvailable()) return;
    if (!sg_open) sg_queuePage = NO;
    setOpen(!sg_open, YES);
}

// Up with the lines in the one column: the page turns to them, or opens on them.
static void openLines(BOOL animated) {
    if (sg_open) {
        switchPage(NO);
        return;
    }
    sg_queuePage = NO;
    setOpen(YES, animated);
}

void SGRPlayerToggleQueuePage(void) {
    forgetPreview();
    if (sg_wide) {
        pickSide(SGRSidePickQueue);
        return;
    }
    if (sg_open && sg_queuePage) {
        setOpen(NO, YES);
        return;
    }
    if (sg_open) {
        switchPage(YES);
        return;
    }
    sg_queuePage = YES;
    setOpen(YES, YES);
    // Nowhere to put it yet (the player not laid out, no cover read): the next page opens on the lines again.
    if (!sg_open) sg_queuePage = NO;
}

static void answerPreview(void) {
    if (!sg_pendingPreview || ![sg_pendingPreview.track isEqual:SGKaraokePlayingTrack()]) return;
    if (!SGRPlayerLyricsOpen() && sg_host.window && SGRPlayerLyricsAvailable() && !coveredBySheet()) {
        if (sg_wide) pickSide(SGRSidePickLyrics);
        else openLines(YES);
    }
    if (SGRPlayerLyricsOpen()) forgetPreview();
}

void SGRPlayerOpenPreviewLyrics(UIView *preview) {
    NSString *track = SGKaraokePlayingTrack();
    if (SGRPlayerLyricsOpen() || !track || !preview.window || ![preview isDescendantOfView:sg_host]) return;
    forgetPreview();
    sg_pendingPreview = [[SGRPendingPreview alloc] initWithTarget:nil action:nil];
    sg_pendingPreview.delegate = sg_pendingPreview;
    sg_pendingPreview.track = track;
    [preview.window addGestureRecognizer:sg_pendingPreview];
    answerPreview();
}

void SGRPlayerToggleQueueSide(void) {
    if (sg_wide) pickSide(SGRSidePickQueue);
}

void SGRPlayerShowLyricsOnOpen(void) {
    sg_lyricsOnOpenUntil = CACurrentMediaTime() + kLyricsOnOpenWindow;
}

// The mini player's ask, once the player it opened is up and settled: the lyrics in the side column, or opened as the
// narrow player opens them.
static void answerLyricsOnOpen(UIView *host) {
    if (!sg_lyricsOnOpenUntil || !host.window || SGRPlayerIsTransitioning()) return;
    BOOL current = CACurrentMediaTime() < sg_lyricsOnOpenUntil;
    sg_lyricsOnOpenUntil = 0;
    if (!current) return;
    if (sg_wide) {
        pickSide(SGRSidePickLyrics);
        return;
    }
    // After this pass: the lines open with an animation of their own.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!SGRPlayerLyricsOpen() && !sg_wide && SGRPlayerLyricsAvailable()) openLines(YES);
    });
}

// A layout pass, a new track or a turn of the phone: the state is put back where it belongs without
// animating, since the frames it is measured from have just changed.
static void replace(void) {
    UIView *host = sg_host;
    if (!host || sg_moving || sg_placingColumn) return;   // a pass in the middle of the transition would cut it short
    if (wideIn(host)) {
        // The narrow player's lines, if they were up, give their place to the side column's.
        if (!sg_wide && sg_open) setOpen(NO, NO);
        placeWide(host);
        answerLyricsOnOpen(host);
        return;
    }
    leaveWide(host);
    answerLyricsOnOpen(host);
    SGRLyricsLayout l = layoutIn(host, NO);
    if (sg_open && !l.ok) return;
    placeTitleRow(l);
    sg_floating.viewIfLoaded.alpha = sg_open ? 0 : 1;
    if (!sg_open) return;
    SGRPlayerLyricsOverlay *overlay = objc_getAssociatedObject(host, &kOverlayKey);
    if (!overlay.superview) return;
    if (overlay.superview == host && host.subviews.lastObject != overlay) [host bringSubviewToFront:overlay];
    if (sg_alone) {
        l.stage = aloneStage(host, l);
        fadeControls(YES);
    }
    place(overlay, host, l);
    overlay.thumb.transform = pageThumbTransform(l);
    overlay.cover.layer.cornerRadius = thumbRadius(l, YES);
    // The lines' getter would put them back in the stage: with the queue up, only the queue is laid out.
    if (sg_queuePage) {
        UIView *page = queuePageOf(overlay).view;
        if (page.superview == overlay.stage) page.frame = overlay.stage.bounds;
        if (!sg_moving) {
            if (fabs(sg_pageLayout.head - l.head) >= 0.5 || !sg_pageLayout.ok) configurePage(overlay, l);
            sg_pageLayout = l;
            ridePage();
        }
    } else {
        anchorLines(overlay, l);
        overlay.lyrics.frame = overlay.stage.bounds;
    }
    replaceCoverList(YES);
}

#pragma mark - the units

%hook _TtC19NowPlaying_ViewImpl24NowPlayingViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *host = ((UIViewController *)self).viewIfLoaded;
    if (!host || host.bounds.size.height < kLivingHeight) return;
    sg_player = (UIViewController *)self;
    if (sg_host != host) {
        forgetPreview();
        leaveWide(sg_host);
        sg_host = host;
        [host addGestureRecognizer:[SGRPlayerTouchWatcher new]];
        SGRPlayerWake *wake = [SGRPlayerWake new];
        [host addGestureRecognizer:wake];
        sg_wake = wake;
        SGLog(@"redesign player: the lyrics have the player's view %.0fx%.0f", host.bounds.size.width, host.bounds.size.height);
    }
    replace();
    SGRProgressVisibilityChanged();
}

// The bar morphs back out of a full size cover as the player closes, so the thumbnail is put away first. The two
// columns have no morph (a regular width has none, PlayerMorph.x) and close as they are; only the side column's pick
// is forgotten, so the next player opens on its default.
- (void)viewWillDisappear:(BOOL)animated {
    forgetPreview();
    if (sg_open && !sg_wide) {
        BOOL queuePage = sg_queuePage;
        UIViewController *player = (UIViewController *)self;
        id<UIViewControllerTransitionCoordinator> coordinator = player.transitionCoordinator;
        UIView *host = player.viewIfLoaded;
        SGRPlayerLyricsOverlay *page = objc_getAssociatedObject(host, &kOverlayKey);
        if (coordinator.initiallyInteractive && page.superview == sg_host &&
            host.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPhone && host.bounds.size.height > host.bounds.size.width) {
            BOOL alone = sg_alone;
            NSString *track = SGURIString(SGPlayerState().track.URI);
            sg_dismissingPage = page;
            if (![coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
                if (sg_dismissingPage != page) return;
                sg_dismissingPage = nil;
                // Shown again only at the end (below), so the held page stays suspended until the restore is placed.
                if (context.isCancelled && sg_host == host && !sg_wide && host.bounds.size.height > host.bounds.size.width && queuePage) {
                    [UIView performWithoutAnimation:^{
                        sg_queuePage = YES;
                        setOpen(YES, NO);
                        if (!sg_open) sg_queuePage = NO;
                    }];
                } else if (context.isCancelled && sg_host == host && !sg_wide && host.bounds.size.height > host.bounds.size.width &&
                    [track isEqual:SGURIString(SGPlayerState().track.URI)] && SGKaraokeLinesForTrack(SGKaraokePlayingTrack()).count) {
                    [UIView performWithoutAnimation:^{
                        setOpen(YES, NO);
                        if (alone) setAlone(YES, NO);
                    }];
                }
                if (page.superview != sg_host || !sg_open) [page removeFromSuperview];
                page.hidden = NO;
            }]) sg_dismissingPage = nil;
        }
        setOpen(NO, NO);
    }
    sg_sidePick = SGRSidePickNone;
    // The landscape screen outlives the lines for a track without lyrics, but not the player.
    SGRPlayerShowLandscape(NO);
    %orig;
}
%end

// The ordinary player's units and the AI DJ's (DJMInformationUnitViewController, DJMDurationElementsUnit, which
// hold the same title row and progress bar) are measured the same way, so the DJ's player has these lyrics too.
// The title's arranged view, nil when the row has no title yet.
static UIView *informationUnitLaidOut(UIViewController *unit) {
    sg_info = unit;
    UIView *host = unit.viewIfLoaded;
    // The title and the artist are two labels of one arranged element view, which is what moves.
    UIView *label = SGRFindByIdentifier(host, @"now-playing-title-label", &kTitleKey);
    UIView *element = nil;
    for (UIView *v = label; v && v != host; v = v.superview) {
        if ([v.superview isKindOfClass:UIStackView.class]) { element = v; break; }
    }
    SGRShownTitleWatch(host);
    // The row's view in the unit's, inset so the title starts at the player's margin, its trailing buttons as far in.
    UIView *row = element;
    while (row && row.superview != host) row = row.superview;
    // Only once the row has placed the title: the inset is measured from where it stands. A unit made while another
    // player's is up (a song started after the app opened on a video podcast, 9.2.0) lays out once, before its row has
    // placed anything, and its title stayed 24 pt in over a bar 32 in: the unit is asked for another pass a second
    // on, three times at most, by when the row has dropped the podcast's thumbnail (a pass at once still found it,
    // the title 60 pt in).
    static char kTitlePassesKey;
    if (row && element.bounds.size.width <= 0) {
        NSInteger passes = [objc_getAssociatedObject(host, &kTitlePassesKey) integerValue];
        if (passes < 3) {
            objc_setAssociatedObject(host, &kTitlePassesKey, @(passes + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            __weak UIView *weakHost = host;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [weakHost setNeedsLayout]; });
        }
    }
    if (row && element.bounds.size.width > 0) {
        objc_setAssociatedObject(host, &kTitlePassesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // Where Spotify put the title, the slide this file gives it beside the thumbnail left out.
        CGRect placed = CGRectMake(element.center.x - element.bounds.size.width / 2, 0, element.bounds.size.width, 0);
        CGRect inRow = [element.superview convertRect:placed toView:row];
        BOOL rtl = host.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
        SGRPlayerHoldMargin(row, rtl ? CGRectGetMaxX(row.bounds) - CGRectGetMaxX(inRow) : CGRectGetMinX(inRow) - CGRectGetMinX(row.bounds));
    }
    if (element && sg_titleElement != element) {
        sg_titleElement = element;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGLog(@"redesign player: the title rides on %@ %@", NSStringFromClass(element.class), NSStringFromCGRect(element.frame)); });
    }
    replace();
    return element;
}

static void durationUnitLaidOut(UIViewController *unit) {
    sg_duration = unit;
    replace();
}

// The ordinary player's ⋯ beside its title (PlayerMenu.m); the AI DJ's keeps its own in its header.
%hook _TtC20NowPlaying_ModesImpl23InformationElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *title = informationUnitLaidOut((UIViewController *)self);
    if (title) SGRPlayerMenuInTitleRow(title);
}
%end

%hook _TtC20NowPlaying_ModesImpl19DurationElementUnit
- (void)viewDidLayoutSubviews {
    %orig;
    durationUnitLaidOut((UIViewController *)self);
}
%end

// The header row (the down arrow, Playing from, the ⋯; PlayerHeader.x has its tree), which fades with the
// controls while the lines are alone.
%hook _TtC20NowPlaying_ModesImpl18HeaderElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    sg_header = (UIViewController *)self;
    replace();
}
%end

// The DJ player units are other classes, hooked only when the build has them (see %ctor).
%group SGRDJInformationHooks
%hook SGRDJInformationUnit
- (void)viewDidLayoutSubviews {
    %orig;
    informationUnitLaidOut((UIViewController *)self);
}
%end
%end

// The DJ's header row fades with the rest while the lines are alone.
%group SGRDJHeaderFadeHooks
%hook SGRDJHeaderFadeUnit
- (void)viewDidLayoutSubviews {
    %orig;
    sg_header = (UIViewController *)self;
    replace();
}
%end
%end

%group SGRDJDurationHooks
%hook SGRDJDurationUnit
- (void)viewDidLayoutSubviews {
    %orig;
    durationUnitLaidOut((UIViewController *)self);
}
%end
%end

// The chips over the title (Switch to video and whatever else a track brings) sit in the middle of the
// room the lines take, so they go while the lines are up. The row keeps its height: the rest of the
// bottom stack stays where it was, which is the whole point of lifting only the title out of it.
%hook _TtC20NowPlaying_ModesImpl20FloatingElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    sg_floating = (UIViewController *)self;
    replace();
}
%end

#pragma mark - the track changing under them

@interface SGRPlayerLyricsWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGRPlayerLyricsWatcher {
    NSString *_track;
    BOOL _graceOver;   // the track playing has had its kLyricsGrace
    NSUInteger _checkGeneration;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    // An edit of a local file's names gives it a new lyrics key, and the sources search again under it.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(editsChanged:) name:SGLocalFileEditsDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(linesKept:) name:SGKaraokeLinesKeptNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(becameActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    return self;
}

// A rename is looked up like a new track, so lines that stay up with none for the new names go once the
// look for them ends, as a new track's do after the grace.
- (void)editsChanged:(NSNotification *)note {
    if (![note.object isKindOfClass:NSString.class] || ![note.object isEqualToString:_track]) return;
    SGRPlayerLyricsChanged();
}

// Lines kept for the track playing, or the look for them over with none. The glyph is told only when they
// are here, since SGRPlayerLyricsChanged sets the animated artwork's blur each time.
- (void)linesKept:(NSNotification *)note {
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    if (![note.object isEqual:SGKaraokePlayingTrack()]) return;
    if (SGRPlayerLyricsAvailable()) {
        SGRPlayerLyricsChanged();
        answerPreview();
        // The two columns' side shows the lines that came, unless the queue was picked.
        refreshSide(YES);
    } else {
        [self closeIfNone];
    }
    SGRPlayerLandscapeLinesChanged();
}

- (BOOL)none {
    return UIApplication.sharedApplication.applicationState == UIApplicationStateActive
        && _graceOver && !SGRPlayerLyricsAvailable() && !SGKaraokeLooking(SGKaraokePlayingTrack());
}

// The lines go once the grace is over and nothing is looking for the track's own any more.
- (void)closeIfNone {
    if (!sg_open || sg_queuePage || ![self none]) return;
    if (sg_wide) {
        SGLog(@"redesign player: no lyrics for the track that came on, the queue is beside it");
        refreshSide(YES);
        return;
    }
    SGLog(@"redesign player: no lyrics for the track that came on, the cover is back");
    setOpen(NO, YES);
}

// A background skip gets a fresh grace on return, not the remainder of an expired background check.
- (void)restartChecks {
    _graceOver = NO;
    NSUInteger generation = ++_checkGeneration;
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    SGRPlayerLyricsChanged();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kLyricsGrace * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self->_checkGeneration != generation || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
        self->_graceOver = YES;
        [self closeIfNone];
        SGRPlayerLandscapeLinesChanged();
    });
}

- (void)becameActive:(NSNotification *)note {
    [self restartChecks];
    // This preserves an in-flight request and its retry pause; it does not forget good lines.
    SGKaraokeRequestLyrics(SGKaraokePlayingTrack());
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    // A pause brings the controls back and keeps them; playing again starts the clock, a second longer with Sing on.
    if (state.isPaused) {
        setAlone(NO, YES);
        [sg_rest invalidate];
        sg_rest = nil;
    } else if (!sg_rest && !sg_alone) {
        restartRestAfter(singing() ? kRestSinging : kRest);
    }
    NSString *track = SGURIString(state.track.URI);
    if (sg_pendingPreview && ![track isEqualToString:_track]) forgetPreview();
    if (!track || [track isEqualToString:_track]) return;
    _track = track;
    // The lines already up wait out a grace for the new track's before they go, a track after it its own.
    [self restartChecks];
}

@end

static SGRPlayerLyricsWatcher *sg_watcher;

BOOL SGRPlayerLyricsNone(void) {
    return [sg_watcher none];
}

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    Class djInformation = SGRDJClass(@"DJMInformationUnitViewController");
    if (djInformation) { %init(SGRDJInformationHooks, SGRDJInformationUnit = djInformation); }
    Class djDuration = SGRDJClass(@"DJMDurationElementsUnit");
    if (djDuration) { %init(SGRDJDurationHooks, SGRDJDurationUnit = djDuration); }
    Class djHeader = SGRDJClass(@"DJMHeaderElementsUnitViewController");
    if (djHeader) { %init(SGRDJHeaderFadeHooks, SGRDJHeaderFadeUnit = djHeader); }
    sg_watcher = [SGRPlayerLyricsWatcher new];
    SGAddPlayerStateObserver(sg_watcher);
    // The mini player's ask for the lyrics is answered once the player it opened has settled, which may come after the
    // player's last layout pass.
    [NSNotificationCenter.defaultCenter addObserverForName:SGPlayerTransitionEndedNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{ answerLyricsOnOpen(sg_host); });
    }];
    // In the background the controls stay up; back in front the clock starts again.
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        reportPlayerGeometry();
        forgetPreview();
        setAlone(NO, NO);
        [sg_rest invalidate];
        sg_rest = nil;
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        restartRest();
        // The lyrics button asked again on the way back and twice after, as the lines can land in the meantime;
        // it stayed dimmed after an instrumental heard in the background.
        SGRPlayerLyricsChanged();
        for (NSNumber *wait in @[@1, @3]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) SGRPlayerLyricsChanged();
            });
        }
    }];
    // VoiceOver keeps the controls up: turned on, it brings them back.
    [NSNotificationCenter.defaultCenter addObserverForName:UIAccessibilityVoiceOverStatusDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        setAlone(NO, YES);
        restartRest();
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:SGRNowPlayingArtworkDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        answerPreview();
        if (!sg_open && !sg_wide) {
            if (sg_host.window && wideIn(sg_host)) [sg_host setNeedsLayout];
            return;
        }
        SGRPlayerLyricsOverlay *overlay = objc_getAssociatedObject(sg_host, &kOverlayKey);
        overlay.cover.image = SGRNowPlayingArtwork(NULL, NULL);
    }];
    SGRequireClasses(@[
        @"_TtC19NowPlaying_ViewImpl24NowPlayingViewController",
        @"_TtC20NowPlaying_ModesImpl23InformationElementsUnit",
        @"_TtC20NowPlaying_ModesImpl19DurationElementUnit",
        @"_TtC20NowPlaying_ModesImpl20FloatingElementsUnit",
        @"_TtC20NowPlaying_ModesImpl18HeaderElementsUnit",
    ]);
}
