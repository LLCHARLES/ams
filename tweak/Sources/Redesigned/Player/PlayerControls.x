// Player redesign: previous, play and next as bare glyphs, the way the Music app draws them, shuffle and
// repeat left out on request, and the timestamps under the slider in digits of one width, so they stop
// twitching every second, their changed characters rolling into place unless Rolling time digits is off
// (SGRRefinements.h).
//
// The glyphs are drawn over Spotify's controls rather than instead of them: each button keeps its
// action, its enabled state, its accessibility and the Gestures zones around it, and the glyph takes no
// touches. Previous and next get theirs inside the button's content view, so the button's own press
// and disabled look carry over; Spotify's icon under it goes transparent on every pass (SPTEncoreIconView
// is a Swift class, which SGRSuppress cannot keep). Play loses its white disc, a plain UIImageView the
// size of the button, which SGRSuppress keeps transparent, and the glyph over it follows the player's state.
//
// Tree (trees/clean/player/01.txt): PlaybackControlsElementsUnit's view holds
// id=SPTNowPlayingPreviousTrackButton 56x56 > UIView > StackView > StackView > SPTEncoreIconView (:257),
// id=SPTNowPlayingPlayButton (PlayButtonView 64x64, :266) > CondensedButton (a UIButton,
// objc-meta-Spotify.txt:207312) > UIImageView 64x64 and a hidden SpinnerView, next to a hidden UIView
// holding a UIImageView (:277), and id=SPTNowPlayingNextTrackButton. DurationElementUnit's view holds
// id=now-playing-time-take-label and id=now-playing-time-remaning-label, SPTEncoreLabels whose UILabel
// is id=...-internal (:227). The sticky header has a play button of its own (:492), which a search
// inside the unit's view never reaches.
#import <UIKit/UIGestureRecognizerSubclass.h>
#import <stdatomic.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRPress.h"
#import "Redesigned/Kit/SGRRefinements.h"
#import "Shared/Haptics/Haptics.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/AudioQuality.h"
#import "Shared/SponsorBlock/SponsorBlock.h"
#import "Player.h"
#import "PlayerMix.h"
#import "Shared/AutoMix/AutoMixPreview.h"

static const CGFloat kSkipGlyphSize = 32, kPlayGlyphSize = 44;
// The platter the Music app fades in behind a pressed transport glyph (SGRPress.h), about twice the glyph.
static const CGFloat kSkipPlatter = 64, kPlayPlatter = 76;
// A spinner that is still up this long after a state change is buffering, not a track starting.
static const NSTimeInterval kSpinnerCheck = 0.6;

// After a tap the glyph shows what the tap asked for, and a state still saying the opposite is taken for
// one sent before the player caught up, for this long; after it the player's word is final.
static const NSTimeInterval kTapTrust = 1.2;

static char kPreviousKey, kNextKey, kPlayKey, kGlyphKey, kTakeKey, kRemainingKey, kRowKey, kShuffleKey, kRepeatKey;
static __weak UIView *sg_playView;
static __weak UIButton *sg_playButton;
static CFTimeInterval sg_tappedUntil;
static BOOL sg_tappedPaused;
static __weak SGRGlyphView *sg_playGlyph;
static __weak UIView *sg_controlsHost;

static NSMutableSet<NSString *> *sg_loggedMessages;
#define kLogFormat @"redesign player: %@ not found, left as Spotify's"

SGRGlyphView *SGRPlayerGlyphFor(UIView *owner, const void *key, NSString *symbol, CGFloat size) {
    SGRGlyphView *glyph = objc_getAssociatedObject(owner, key);
    if (!glyph) {
        glyph = [[SGRGlyphView alloc] initWithSymbol:symbol pointSize:size weight:UIImageSymbolWeightRegular];
        objc_setAssociatedObject(owner, key, glyph, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return glyph;
}

// Centered by the autoresizing mask as well as here: the unit lays out before the buttons in its row
// have a size, so a center set then is the middle of nothing, (0, 0), and no later pass of the unit's
// comes to move it (trees/continuous/1.txt, 2026-09-17: glyphs at {-23.7, -14.7} in 56pt buttons).
void SGRPlayerPlaceGlyph(UIView *view, UIView *host, CGFloat dy) {
    if (view.superview != host) {
        view.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin
                              | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        [host addSubview:view];
    } else if (host.subviews.lastObject != view) {
        [host bringSubviewToFront:view];
    }
    view.center = CGPointMake(CGRectGetMidX(host.bounds), CGRectGetMidY(host.bounds) + dy);
}

#pragma mark - previous and next

static void skipGlyph(UIView *host, NSString *identifier, const void *findKey, NSString *symbol, SGRPressOptions nudge) {
    UIView *button = SGRFindByIdentifier(host, identifier, findKey);
    UIView *content = button.subviews.firstObject;
    if (!content) {
        SGLogOnce(&sg_loggedMessages, identifier, kLogFormat);
        return;
    }
    static Class icon;
    if (!icon) icon = NSClassFromString(@"SPTEncoreIconView");
    SGRGlyphView *glyph = SGRPlayerGlyphFor(button, &kGlyphKey, symbol, kSkipGlyphSize);
    SGForEachView(content, ^(UIView *view) {
        if (view != glyph && [view isKindOfClass:icon]) SGRVanish(view);
    });
    SGRPlayerPlaceGlyph(glyph, content, 0);
    // The touches are the button's; the platter goes in with the glyph, under it.
    SGRPressGlyph(button, glyph, content, kSkipPlatter, SGRPressScale | nudge);
}

#pragma mark - shuffle and repeat

// Each switched on under Hide on the player (SGRKeyPlayerHideShuffle, SGRKeyPlayerHideRepeat), read at launch. By
// alpha in their slots: the row is Spotify's stack of five, and setting `hidden` in an Encore stack crashes. Kept by
// SGRSuppress, since Spotify's state render sets a button's alpha back to 1 when shuffle or repeat changes.
static BOOL sg_hideShuffle, sg_hideRepeat;
// The ordinary player's controls, apart from sg_controlsHost, which the DJ's set too.
static __weak UIView *sg_buttonsHost;
static NSString *const kShuffleID = @"Components.UI.ShuffleButton", *const kRepeatID = @"Nowplaying-RepeatButton";

static BOOL isHiddenButton(UIView *view) {
    NSString *identifier = view.accessibilityIdentifier;
    return (sg_hideShuffle && [identifier isEqualToString:kShuffleID])
        || (sg_hideRepeat && [identifier isEqualToString:kRepeatID]);
}

static BOOL isShuffleOrRepeat(UIView *view) {
    NSString *identifier = view.accessibilityIdentifier;
    return [identifier isEqualToString:kShuffleID] || [identifier isEqualToString:kRepeatID];
}

// Spotify also swaps in a new button a moment after the controls lay out (seen for repeat on 9.1.90: the instance
// found leaves the window 40 ms later and another arrives at alpha 1), with no layout pass after it. The new one is
// caught as it arrives, hidden if its switch says so, and the controls are asked to lay out again, so previous and
// next are placed for the row as it is now (spreadSkips): a shown one ends the spread its empty end allowed. The class
// is an Encore button's, taken from the first shuffle or repeat found (`class`, not a KVO class it may be observed
// through), since its name carries a build hash. It is the class of every Encore button, the playlist, album and
// artist headers' shuffle among them, so only one inside the player's controls counts; any other pays a window check
// and an identifier compare as it moves.
%group SGRPlayerButtonArrival
%hook SGRPlayerButton
- (void)didMoveToWindow {
    %orig;
    UIView *view = (UIView *)self;
    UIView *host = sg_buttonsHost;
    if (!view.window || !isShuffleOrRepeat(view) || !host || ![view isDescendantOfView:host]) return;
    if (isHiddenButton(view)) SGRSuppress(view);
    [host setNeedsLayout];
}
%end
%end

static void watchArrivals(UIView *button) {
    static BOOL hooked;
    if (!button || hooked) return;
    hooked = YES;
    %init(SGRPlayerButtonArrival, SGRPlayerButton = button.class);
}

// Whether an end of the row is empty for previous and next to spread over: it holds the hidden button, or no control
// at all. Not whether the button is there at this pass: between taking repeat out and putting the new one in
// (SGRPlayerButtonArrival) Spotify can lay the controls out, in the same holder or a bare placeholder in its place (the
// ends Spotify leaves where an account has no shuffle or repeat look the same), and a pass that went by the button
// would put previous and next back with nothing to spread them again. An end holding another control (a podcast's)
// is not empty.
static BOOL emptyEnd(UIView *end, UIView *hiddenButton) {
    if (!end) return NO;
    if (hiddenButton) return YES;
    __block BOOL control = NO;
    SGForEachView(end, ^(UIView *view) {
        if (!control && ([view isKindOfClass:UIControl.class] || view.accessibilityIdentifier.length)) control = YES;
    });
    return !control;
}

// Each is looked for only in its own end of the row, so a row without it (a podcast's) costs a walk of one
// element, not the unit; one switched off is hidden. YES when both ends of the row are empty (emptyEnd): both
// switched off, or Spotify built the row without them (a Free account's).
static BOOL shuffleAndRepeatGone(UIView *host, UIStackView *row) {
    sg_buttonsHost = host;
    NSArray<UIView *> *arranged = row.arrangedSubviews;
    UIView *first = arranged.firstObject, *last = arranged.lastObject;
    UIView *shuffle = SGRFindByIdentifier(first, kShuffleID, &kShuffleKey);
    UIView *repeat = SGRFindByIdentifier(last, kRepeatID, &kRepeatKey);
    watchArrivals(shuffle ?: repeat);
    if (!sg_hideShuffle) shuffle = nil;
    if (!sg_hideRepeat) repeat = nil;
    if (shuffle) SGRSuppress(shuffle);
    if (repeat) SGRSuppress(repeat);
    return first != last && emptyEnd(first, shuffle) && emptyEnd(last, repeat);
}

#pragma mark - previous and next, with shuffle and repeat gone

// The Music app's three transport glyphs stand well apart; Spotify's previous and next stay next to play with the
// empty slots of shuffle and repeat outside them. With both slots empty, each moves out until its center is a third of
// the room between the player's margins (SGRPlayerSideMargin) from play's, kSpreadReachMax at most, less where that
// would take either past the row's edge; one already farther out stays. Play keeps its place and every button its
// size. A translation on the row's slot, set in the unit's own layout pass: the stack places its slots by center and
// bounds, which a transform leaves alone, so Spotify's layout stays underneath and identity puts it back exactly. In
// landscape, with either shown, or on a row whose ends hold other controls (a podcast's 15 s skips), the slots are
// Spotify's.
// The emptied ends stay where the stack put them, and next's moves under repeat's (the last of the row is on top):
// an empty view that takes touches swallows them, so the ends take none while the two are spread (quietEnds).
static const CGFloat kSpreadReachMax = 140;
static char kSpreadSlotsKey, kSpreadShiftKey, kQuietEndsKey;

// The row's own slot that holds `view`, or nil.
static UIView *slotOf(UIStackView *row, UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        if (v.superview == row) return v;
    }
    return nil;
}

// Moves `slot` by `dx` across, only over a transform this file set (or none), and remembers it on the row to undo.
static void shiftSlot(UIStackView *row, UIView *slot, CGFloat dx) {
    NSValue *mine = objc_getAssociatedObject(slot, &kSpreadShiftKey);
    CGAffineTransform expected = mine ? mine.CGAffineTransformValue : CGAffineTransformIdentity;
    if (!CGAffineTransformEqualToTransform(slot.transform, expected)) return;
    CGAffineTransform shift = CGAffineTransformMakeTranslation(dx, 0);
    if (!CGAffineTransformEqualToTransform(slot.transform, shift)) slot.transform = shift;
    objc_setAssociatedObject(slot, &kSpreadShiftKey, dx ? [NSValue valueWithCGAffineTransform:shift] : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSHashTable<UIView *> *shifted = objc_getAssociatedObject(row, &kSpreadSlotsKey);
    if (!shifted) {
        shifted = [NSHashTable weakObjectsHashTable];
        objc_setAssociatedObject(row, &kSpreadSlotsKey, shifted, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (dx) [shifted addObject:slot];
    else [shifted removeObject:slot];
}

// The row's two ends take no touches while `quiet`, and get them back otherwise, as does an end turned off here that is
// no longer one (Spotify may reuse it for another button). Only what this file turned off is turned on again.
static void quietEnds(UIStackView *row, BOOL quiet) {
    NSHashTable<UIView *> *quieted = objc_getAssociatedObject(row, &kQuietEndsKey);
    NSArray<UIView *> *arranged = row.arrangedSubviews;
    NSArray<UIView *> *ends = quiet && arranged.count > 1 ? @[arranged.firstObject, arranged.lastObject] : @[];
    for (UIView *end in quieted.allObjects) {
        if ([ends containsObject:end]) continue;
        end.userInteractionEnabled = YES;
        [quieted removeObject:end];
    }
    for (UIView *end in ends) {
        BOOL mine = [quieted containsObject:end];
        if (!mine && !end.userInteractionEnabled) continue;
        if (end.userInteractionEnabled) end.userInteractionEnabled = NO;
        if (mine) continue;
        if (!quieted) {
            quieted = [NSHashTable weakObjectsHashTable];
            objc_setAssociatedObject(row, &kQuietEndsKey, quieted, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        [quieted addObject:end];
    }
}

static void spreadSkips(UIView *host, UIStackView *row, BOOL endsEmpty) {
    UIView *play = slotOf(row, SGRFindByIdentifier(host, @"SPTNowPlayingPlayButton", &kPlayKey));
    UIView *previous = slotOf(row, SGRFindByIdentifier(host, @"SPTNowPlayingPreviousTrackButton", &kPreviousKey));
    UIView *next = slotOf(row, SGRFindByIdentifier(host, @"SPTNowPlayingNextTrackButton", &kNextKey));
    // An iPhone in landscape is compact in height.
    BOOL portrait = row.traitCollection.verticalSizeClass != UIUserInterfaceSizeClassCompact;
    CGFloat previousShift = 0, nextShift = 0;
    BOOL spread = endsEmpty && portrait && play && previous && next && previous != play && next != play && previous != next;
    if (spread) {
        CGFloat width = row.bounds.size.width, playX = play.center.x;
        // From play's center to the farthest a button's center can go on its side with the button still in the row.
        CGFloat (^room)(UIView *) = ^CGFloat(UIView *slot) {
            return (slot.center.x < playX ? playX : width - playX) - slot.bounds.size.width / 2;
        };
        CGFloat inside = MIN(width, host.bounds.size.width - 2 * SGRPlayerSideMargin);
        CGFloat reach = MIN(MIN(inside / 3, kSpreadReachMax), MIN(room(previous), room(next)));
        CGFloat (^outward)(UIView *) = ^CGFloat(UIView *slot) {
            CGFloat offset = slot.center.x - playX;
            CGFloat more = MAX(0, reach - fabs(offset));
            return offset < 0 ? -more : more;
        };
        previousShift = outward(previous);
        nextShift = outward(next);
    }
    // A slot shifted before that is no longer previous or next (the row was rebuilt) goes back first.
    NSHashTable<UIView *> *shifted = objc_getAssociatedObject(row, &kSpreadSlotsKey);
    for (UIView *slot in shifted.allObjects) {
        if (slot != previous && slot != next) shiftSlot(row, slot, 0);
    }
    if (previous) shiftSlot(row, previous, previousShift);
    if (next) shiftSlot(row, next, nextShift);
    quietEnds(row, spread);
    if (previousShift || nextShift) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGLog(@"redesign player: shuffle and repeat gone, previous and next moved %.1f and %.1fpt out in a %.0fpt row", previousShift, nextShift, row.bounds.size.width); });
    }
}

#pragma mark - play

static BOOL spinnerShowing(UIButton *button) {
    for (UIView *sub in button.subviews) {
        if (!sub.hidden && sub.alpha > 0.01 && [NSStringFromClass(sub.class) containsString:@"SpinnerView"]) return YES;
    }
    return NO;
}

static NSString *symbolFor(BOOL paused) {
    return paused ? @"play.fill" : @"pause.fill";
}

static void refreshPlayGlyph(BOOL animated) {
    SGRGlyphView *glyph = sg_playGlyph;
    SPTPlayerState *state = SGPlayerState();
    if (!glyph || !state) return;
    glyph.alpha = spinnerShowing(sg_playButton) ? 0 : 1;
    CFTimeInterval now = CACurrentMediaTime();
    if (now < sg_tappedUntil) {
        if (state.isPaused != sg_tappedPaused) return;
        sg_tappedUntil = 0;
    }
    [glyph setSymbol:symbolFor(state.isPaused) animated:animated];
}

// The player's state reaches the glyph a beat after the tap (the request goes through the player core
// and comes back as a state), which read as a slow button; Spotify's own disc turns at the touch. So the
// glyph turns at the touch too, to the opposite of what it shows, and the state settles it after.
static void playTapped(void) {
    SGRGlyphView *glyph = sg_playGlyph;
    if (!glyph || glyph.alpha == 0) return;
    sg_tappedPaused = ![glyph.symbol isEqualToString:@"play.fill"];
    sg_tappedUntil = CACurrentMediaTime() + kTapTrust;
    [glyph setSymbol:symbolFor(sg_tappedPaused) animated:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kTapTrust * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ refreshPlayGlyph(YES); });
}

void SGRPlayerPlayGlyphIn(UIView *host) {
    // A state that lands after the layout asks this unit to lay out again (the watcher below).
    sg_controlsHost = host;
    UIView *play = SGRFindByIdentifier(host, @"SPTNowPlayingPlayButton", &kPlayKey);
    if (!play) {
        SGLogOnce(&sg_loggedMessages, @"SPTNowPlayingPlayButton", kLogFormat);
        return;
    }
    // Before the player has reported a state the glyph could only guess, so the disc stays.
    SPTPlayerState *state = SGPlayerState();
    if (!state) return;
    UIButton *button = nil;
    for (UIView *sub in play.subviews) {
        if ([sub isKindOfClass:UIButton.class]) button = (UIButton *)sub;
    }
    UIImageView *disc = nil;
    for (UIView *sub in button.subviews) {
        if ([sub isKindOfClass:UIImageView.class] && CGSizeEqualToSize(sub.bounds.size, button.bounds.size)) disc = (UIImageView *)sub;
    }
    if (!disc) {
        SGLogOnce(&sg_loggedMessages, @"the play button's disc", kLogFormat);
        return;
    }
    SGRSuppress(disc);
    // The holder Spotify crossfades a snapshot of the disc in when play turns to pause.
    for (UIView *sub in play.subviews) {
        if (object_getClass(sub) != UIView.class) continue;
        for (UIView *image in sub.subviews) {
            if ([image isKindOfClass:UIImageView.class]) SGRSuppress(image);
        }
    }

    // Inside the button, over the disc it replaces, so it follows the button's own press.
    SGRGlyphView *glyph = SGRPlayerGlyphFor(play, &kGlyphKey, symbolFor(state.isPaused), kPlayGlyphSize);
    SGRPlayerPlaceGlyph(glyph, button, 0);
    SGRPressGlyph(play, glyph, button, kPlayPlatter, SGRPressScale);
    sg_playView = play;
    sg_playButton = button;
    sg_playGlyph = glyph;
    refreshPlayGlyph(NO);

    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"redesign player: play glyph over %@ (disc %@ suppressed), spinner %@", NSStringFromClass(play.class), NSStringFromClass(disc.class), spinnerShowing(button) ? @"showing" : @"hidden"); });
}

%hook _TtC20NowPlaying_ModesImpl28PlaybackControlsElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *host = ((UIViewController *)self).viewIfLoaded;
    if (!host) return;
    // The unit lays out before its row does, and the glyphs are centered on the buttons in it.
    UIStackView *row = (UIStackView *)SGFindRemembered(host, &kRowKey, ^BOOL(UIView *v) { return SGIsRow(v); });
    [row layoutIfNeeded];
    skipGlyph(host, @"SPTNowPlayingPreviousTrackButton", &kPreviousKey, @"backward.fill", SGRPressNudgeBack);
    skipGlyph(host, @"SPTNowPlayingNextTrackButton", &kNextKey, @"forward.fill", SGRPressNudgeForward);
    SGRPlayerPlayGlyphIn(host);
    BOOL endsEmpty = shuffleAndRepeatGone(host, row);
    if (row) spreadSkips(host, row, endsEmpty);
    SGRPlayerFitSpeedLabel(host);
}
%end

@interface SGRPlayerControlsWatcher : NSObject <SGPlayerStateObserver>
@end

static void updateSeek(SPTPlayerState *state);

@implementation SGRPlayerControlsWatcher

- (void)playerStateDidReport:(SPTPlayerState *)state {
    updateSeek(state);
    SGRProgressPlaybackChanged(state.duration, state.playbackSpeed);
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    // The first state can land after the controls laid out, which left the disc for want of one.
    if (!sg_playGlyph) [sg_controlsHost setNeedsLayout];
    refreshPlayGlyph(YES);
    // Spotify raises its spinner a moment after a state says loading, and drops it a moment after.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSpinnerCheck * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ refreshPlayGlyph(YES); });
}

@end

static SGRPlayerControlsWatcher *sg_controlsWatcher;

#pragma mark - times

// Rolling time digits (SGRRefinements.h), read at launch.
static BOOL sg_rollingDigits;

static UILabel *monospaced(UIView *host, NSString *identifier, const void *findKey) {
    UILabel *label = (UILabel *)SGRFindByIdentifier(host, identifier, findKey);
    if (![label isKindOfClass:UILabel.class]) {
        SGLogOnce(&sg_loggedMessages, identifier, kLogFormat);
        return nil;
    }
    if (sg_rollingDigits) SGRRollDigits(label);
    else SGRMonospacedDigits(label);
    return label;
}

// The action the play button's own UIButton sends (objc-methods.txt: -[PlayButtonView uiButtonTapped]).
// Only the player's button turns the glyph: the sticky header and every page with a play button of
// its own use the same class.
%hook _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView
- (void)uiButtonTapped {
    %orig;
    if ((UIView *)self != sg_playView) return;
    playTapped();
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"redesign player: play glyph turned at the tap"); });
}
%end

#pragma mark - tap to seek

// Spotify's slider only drags. A tap in the band around it seeks: anywhere across the duration unit's height,
// up to kSeekReach past either end of the bar, moving at most kSeekSlop and lifting within kSeekLongest. A tap
// on the thumb is the thumb's, and a tap on a time is Spotify's, which turns the remaining time into the length.
static const CGFloat kSeekReach = 12, kSeekSlop = 10, kThumbSlop = 6;
static const NSTimeInterval kSeekLongest = 0.5;
// The tap is played to the slider as a short drag, so Spotify's unit seeks the way it does at the end of one.
// Meanwhile the slider says it is still tracking, until the player's position is this near the place tapped or
// for this long at most, so the unit does not put the thumb back to the old place first. A drag that did not
// seek by kSeekCheck is seeked directly.
static const NSInteger kSeekNear = 1500;
static const NSTimeInterval kSeekHold = 2, kSeekCheck = 1;

static char kSliderKey, kSeekTapKey, kTakeTimeKey, kRemainingTimeKey, kStepKey;
static __weak UISlider *sg_seekSlider;
static NSInteger sg_seekTarget;
static CFTimeInterval sg_seekHeldUntil;
static CFAbsoluteTime sg_seekBeganAt;
static NSString *sg_seekTrack;
static BOOL sg_sendingSeekEvents;
// Commands can arrive off main; only their generation crosses threads. The slider and hold stay on main.
static atomic_uint_fast64_t sg_seekGeneration;

static void cancelSeek(void) {
    atomic_fetch_add(&sg_seekGeneration, 1);
    sg_seekHeldUntil = 0;
    UISlider *slider = sg_seekSlider;
    sg_seekSlider = nil;
    if (slider) SGRProgressRailChanged(slider, slider.isTracking);
    sg_seekTrack = nil;
}

// An arrival is remembered by canceling the check, not judged again against a target playback has passed.
// Every report is watched, even when Spotify does not ask the slider whether it is tracking.
static void updateSeek(SPTPlayerState *state) {
    if (!sg_seekHeldUntil) return;
    if (![sg_seekTrack isEqualToString:SGURIString(state.track.URI)]) {
        cancelSeek();
        return;
    }
    // A queued report keeps its anchor even if main resumes after playback has passed the target.
    // Reject reports from before this tap. Sing's positionAsOfTimestamp hook already applies the same
    // lead correction karaoke uses; subtracting it again here would count it twice.
    NSDate *timestamp = state.timestamp;
    if (!timestamp || timestamp.timeIntervalSinceReferenceDate < sg_seekBeganAt) return;
    NSInteger at = (NSInteger)(state.positionAsOfTimestamp * 1000);
    if (at >= 0 && labs(at - sg_seekTarget) < kSeekNear) cancelSeek();
}

static CGFloat thumbCentre(UISlider *slider, float value) {
    CGRect bounds = slider.bounds;
    return CGRectGetMidX([slider thumbRectForBounds:bounds trackRect:[slider trackRectForBounds:bounds] value:value]);
}

// Where along the song a point on the slider is, over the thumb's travel rather than the slider's width, so
// either end of the bar is the song's start or end exactly.
CGFloat SGRSeekShareAt(UISlider *slider, CGPoint point) {
    CGFloat start = thumbCentre(slider, slider.minimumValue), end = thumbCentre(slider, slider.maximumValue);
    if (end - start < 1) return NAN;
    return MIN(1, MAX(0, (point.x - start) / (end - start)));
}

// Whether a tap at `point` in the duration unit's view seeks.
BOOL SGRSeekTapLands(UIView *unit, UISlider *slider, CGPoint point) {
    // The AI DJ's unit keeps a slider in a hidden element on a live stream: nothing to seek there.
    if (!slider.window || !slider.enabled || ![slider isDescendantOfView:unit] || !SGShownUnder(slider, unit) || !CGRectContainsPoint(unit.bounds, point)) return NO;
    CGRect bar = [unit convertRect:slider.bounds fromView:slider];
    if (point.x < CGRectGetMinX(bar) - kSeekReach || point.x > CGRectGetMaxX(bar) + kSeekReach) return NO;
    CGRect bounds = slider.bounds;
    CGRect thumb = [slider thumbRectForBounds:bounds trackRect:[slider trackRectForBounds:bounds] value:slider.value];
    if (CGRectContainsPoint(CGRectInset([unit convertRect:thumb fromView:slider], -kThumbSlop, -kThumbSlop), point)) return NO;
    // The audio quality badge between the times opens its details.
    UIView *badge = SGAudioQualityShownBadge(unit);
    if (badge && [badge pointInside:[unit convertPoint:point toView:badge] withEvent:nil]) return NO;
    for (UIView *time in @[SGRFindByIdentifier(unit, @"now-playing-time-take-label", &kTakeTimeKey) ?: NSNull.null,
                           SGRFindByIdentifier(unit, @"now-playing-time-remaning-label", &kRemainingTimeKey) ?: NSNull.null]) {
        if ([time isKindOfClass:UIView.class] && !time.hidden && CGRectContainsPoint([unit convertRect:time.bounds fromView:time], point)) return NO;
    }
    return YES;
}

static BOOL seekHeld(void) {
    if (!sg_seekHeldUntil) return NO;
    updateSeek(SGPlayerState());
    if (sg_seekHeldUntil && CACurrentMediaTime() >= sg_seekHeldUntil) cancelSeek();
    return sg_seekHeldUntil != 0;
}

// Whether Spotify listens to the slider's control events, which is how a played drag reaches it.
static BOOL listensToSlider(UISlider *slider) {
    __block BOOL listens = NO;
    [slider enumerateEventHandlers:^(UIAction *action, id target, SEL selector, UIControlEvents events, BOOL *stop) {
        if (events & (UIControlEventTouchUpInside | UIControlEventValueChanged)) listens = *stop = YES;
    }];
    return listens;
}

static void seekTo(UISlider *slider, CGFloat share) {
    SPTPlayerState *state = SGPlayerState();
    if (!state || state.duration <= 0 || isnan(share)) return;
    cancelSeek();
    NSInteger ms = (NSInteger)(share * state.duration * 1000);
    SGPlayFeedback(SGFeedbackSkip);
    BOOL played = listensToSlider(slider);
    static NSUInteger logged;
    if (logged++ < 3) SGLog(@"redesign player: a tap seeks to %.3f of the song, %@", share, played ? @"played to the slider as a drag" : @"directly (nothing listens to the slider)");
    if (!played) {
        SGKaraokeSeek(ms);
        return;
    }
    // The value-changed target reads this exact seek, even within the last playback pixel.
    objc_setAssociatedObject(slider, &kStepKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [slider setValue:slider.minimumValue + share * (slider.maximumValue - slider.minimumValue) animated:NO];
    sg_seekSlider = slider;
    sg_seekTarget = ms;
    NSString *track = [SGURIString(state.track.URI) copy];
    sg_seekTrack = track;
    sg_seekHeldUntil = CACurrentMediaTime() + kSeekHold;
    sg_seekBeganAt = CFAbsoluteTimeGetCurrent();
    SGRProgressRailChanged(slider, YES);
    uint64_t generation = atomic_load(&sg_seekGeneration);
    sg_sendingSeekEvents = YES;
    [slider sendActionsForControlEvents:UIControlEventTouchDown];
    [slider sendActionsForControlEvents:UIControlEventValueChanged];
    [slider sendActionsForControlEvents:UIControlEventTouchUpInside];
    sg_sendingSeekEvents = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSeekCheck * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != atomic_load(&sg_seekGeneration)) return;
        updateSeek(SGPlayerState());
        if (generation != atomic_load(&sg_seekGeneration) || ![track isEqualToString:SGURIString(SGPlayerState().track.URI)]) return;
        NSInteger at = SGKaraokePositionMs();
        if (at < 0) return;
        SGLog(@"redesign player: the played drag did not seek (at %ld ms, not %ld), seeking directly", (long)at, (long)ms);
        cancelSeek();
        SGKaraokeSeek(ms);
    });
}

// All of Spotify's shorter seek selectors forward here (Shared/Sing/Sing.x). A later seek elsewhere
// supersedes this check. The command sent by our own control events still waits for arrival; dispatch
// alone is not an acknowledgment. The hold also waits, so the thumb cannot jump to its old position.
%hook SPTEsperantoPlayer
- (id)seekTo:(double)position relative:(long long)relative options:(id)options creatorTimestampPositionMs:(double)creator {
    if (!NSThread.isMainThread || !sg_sendingSeekEvents) {
        uint64_t generation = atomic_fetch_add(&sg_seekGeneration, 1) + 1;
        void (^releaseHold)(void) = ^{
            if (generation == atomic_load(&sg_seekGeneration)) cancelSeek();
        };
        if (NSThread.isMainThread) releaseHold();
        else dispatch_async(dispatch_get_main_queue(), releaseHold);
    }
    return %orig;
}
%end

// A recognizer of its own rather than a tap: UIKit lets a slider keep a single tap from a tap recognizer
// over it, and the band reaches past the slider.
@interface SGRSeekTap : UIGestureRecognizer
@property (nonatomic, weak) UISlider *slider;
@end

@implementation SGRSeekTap {
    CGPoint _start;
    CFTimeInterval _began;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UIView *unit = self.view;
    UITouch *touch = touches.anyObject;
    CGPoint point = [touch locationInView:unit];
    if (touches.count > 1 || [event touchesForGestureRecognizer:self].count > 1 || !SGRSeekTapLands(unit, self.slider, point)) {
        self.state = UIGestureRecognizerStateFailed;
        return;
    }
    _start = point;
    _began = CACurrentMediaTime();
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGPoint point = [touches.anyObject locationInView:self.view];
    if (hypot(point.x - _start.x, point.y - _start.y) > kSeekSlop) self.state = UIGestureRecognizerStateFailed;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    BOOL tap = CACurrentMediaTime() - _began <= kSeekLongest;
    self.state = tap ? UIGestureRecognizerStateEnded : UIGestureRecognizerStateFailed;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    self.state = UIGestureRecognizerStateFailed;
}

- (void)sgr_seek {
    UISlider *slider = self.slider;
    if (slider) seekTo(slider, SGRSeekShareAt(slider, [self.view convertPoint:_start toView:slider]));
}
@end

// The progress bar's slider in the duration unit (01.txt:224).
static NSString *const kSliderID = @"SPTNowPlayingSliderV2";

static void watchSlider(UIView *host) {
    UISlider *slider = (UISlider *)SGRFindByIdentifier(host, kSliderID, &kSliderKey);
    if (![slider isKindOfClass:UISlider.class]) return;
    SGRSeekTap *tap = objc_getAssociatedObject(host, &kSeekTapKey);
    if (!tap) {
        tap = [[SGRSeekTap alloc] initWithTarget:nil action:nil];
        [tap addTarget:tap action:@selector(sgr_seek)];
        [host addGestureRecognizer:tap];
        objc_setAssociatedObject(host, &kSeekTapKey, tap, OBJC_ASSOCIATION_ASSIGN);
        SGLog(@"redesign player: a tap around the progress bar seeks");
    }
    tap.slider = slider;
}

#pragma mark - scrubbing

// While a finger scrubs, the Music app's bar grows thicker, its fill turns whole white, and the times under it turn
// white and step down with it, and all of it goes back when the finger lifts. The track grows through the slider's
// own track rect, about its middle, so the thumb and the place a tap seeks to stay where they were; only a real drag
// does it, never the drag a tap to seek plays to the slider (seekTo sends events, it does not track).
static const CGFloat kScrubTimeDrop = 3;
// The Music app keeps its time row clear of the bar: the times, and the audio quality badge between them, stand this
// much lower than Spotify lays them out, by a translation of theirs, so Spotify's layout stays underneath.
static const CGFloat kTimesDrop = 8;
static const NSUInteger kScrubUnitReach = 6;
static char kScrubTakeKey, kScrubTakeLabelKey, kScrubRemainingKey, kScrubRemainingLabelKey, kScrubColorKey;
static __weak UISlider *sg_scrubSlider;

// The view a few levels up the slider that holds the times: the ordinary duration unit's or the AI DJ's.
static UIView *timesAround(UISlider *slider) {
    NSUInteger levels = 0;
    for (UIView *v = slider.superview; v && levels < kScrubUnitReach; v = v.superview, levels++) {
        if (SGRFindByIdentifier(v, @"now-playing-time-take-label", &kScrubTakeKey)) return v;
    }
    return nil;
}

// Spotify's color is kept on the label to go back to; a pass of Spotify's that paints its own over the white
// meanwhile is painted over again (`animated` NO).
static void brighten(UIView *view, BOOL on, BOOL animated) {
    if (![view isKindOfClass:UILabel.class]) return;
    UILabel *label = (UILabel *)view;
    UIColor *kept = objc_getAssociatedObject(label, &kScrubColorKey);
    UIColor *to = on ? SGRPrimary() : kept;
    if (on && !kept && label.textColor) objc_setAssociatedObject(label, &kScrubColorKey, label.textColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!on) objc_setAssociatedObject(label, &kScrubColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!to || [label.textColor isEqual:to]) return;
    if (!animated || !label.window) {
        label.textColor = to;
        return;
    }
    [UIView transitionWithView:label duration:on ? 0.2 : SGRCrossfade
        options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
        animations:^{ label.textColor = to; } completion:nil];
}

// The times' translation: lowered at rest, a little more while a finger scrubs (not under Reduce Motion).
static CGAffineTransform timesDrop(BOOL scrubbing) {
    return CGAffineTransformMakeTranslation(0, kTimesDrop + (scrubbing && !SGRReduceMotion() ? kScrubTimeDrop : 0));
}

#pragma mark - the bar's colors

// The Music app's bars are translucent (PlayerVolume.m takes the same colors): the fill a light white the background
// shows through, the track dimmer, both more opaque under Increase Contrast; a scrub lights the fill whole.
static const CGFloat kBarFillAlpha = 0.6, kBarTrackAlpha = 0.2, kBarFillContrastAlpha = 0.85, kBarTrackContrastAlpha = 0.35;

UIColor *SGRPlayerBarFill(BOOL lit) {
    return [UIColor colorWithWhite:1 alpha:lit ? 1 : SGRIncreaseContrast() ? kBarFillContrastAlpha : kBarFillAlpha];
}

UIColor *SGRPlayerBarTrack(void) {
    return [UIColor colorWithWhite:1 alpha:SGRIncreaseContrast() ? kBarTrackContrastAlpha : kBarTrackAlpha];
}

// How much a finger dragging a bar thickens its track; the stretched middle the caps leave a track image.
static const CGFloat kBarDragGrow = 1.75, kBarStretch = 1;

UIImage *SGRPlayerBarImage(UIColor *color, CGFloat height) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(height, height)];
    UIImage *drawn = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [color setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, height, height) cornerRadius:height / 2] fill];
    }];
    CGFloat cap = floor((height - kBarStretch) / 2);
    return [drawn resizableImageWithCapInsets:UIEdgeInsetsMake(0, cap, 0, cap)];
}

CGFloat SGRPlayerBarDragHeight(CGFloat height) {
    return round(height * kBarDragGrow);
}

static char kBarKey, kBarMinKey, kBarMaxKey, kHeldKey;
static char kLayoutKey;
static BOOL sg_mixProgress;
static NSUInteger sg_mixRevision = 1;
@interface SGRSliderLayout : NSObject {
@public
    BOOL colored, contrast;
    NSUInteger mixRevision, idleRevision;
}
@end
@implementation SGRSliderLayout
@end

static void invalidateColor(UISlider *slider) {
    SGRSliderLayout *layout = objc_getAssociatedObject(slider, &kLayoutKey);
    if (layout) {
        layout->colored = NO;
        layout->idleRevision = 0;
    }
}
static CGFloat sg_scrubHeight;

// The sibling escapes the slider's highlighted opacity. Only the two native track images give
// way: PlayerMix's bands are still behind the translucent rail, in their original slider.
@interface SGRHeldBar : UIView
@property (nonatomic, strong) UIView *rail;
@property (nonatomic, strong) CALayer *fill, *remaining;
@property (nonatomic, strong) NSHashTable<UIImageView *> *tracks;
@property (nonatomic) CGFloat restHeight, heldHeight;
@property (nonatomic) NSUInteger generation;
@end
@implementation SGRHeldBar
@end

static void updateHeldBar(UISlider *slider) {
    SGRHeldBar *bar = objc_getAssociatedObject(slider, &kHeldKey);
    if (!bar) return;
    CGRect rect = [slider trackRectForBounds:slider.bounds];
    BOOL rtl = thumbCentre(slider, slider.minimumValue) > thumbCentre(slider, slider.maximumValue);
    CGFloat range = slider.maximumValue - slider.minimumValue;
    CGFloat share = range > 0 ? (slider.value - slider.minimumValue) / range : 0;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    rect = [slider convertRect:rect toView:slider.superview];
    bar.frame = CGRectMake(rect.origin.x, CGRectGetMidY(rect)-bar.heldHeight/2, rect.size.width, bar.heldHeight);
    CGFloat width = rect.size.width * share, remaining = rect.size.width-width;
    bar.fill.frame = CGRectMake(rtl ? remaining : 0, 0, width, bar.heldHeight);
    bar.remaining.frame = CGRectMake(rtl ? 0 : width, 0, remaining, bar.heldHeight);
    [CATransaction commit];
}

static void hideTrackImages(UISlider *slider, SGRHeldBar *bar) {
    UIImage *min = slider.currentMinimumTrackImage, *max = slider.currentMaximumTrackImage;
    SGForEachView(slider, ^(UIView *v) {
        if (![v isKindOfClass:UIImageView.class] || v.hidden) return;
        UIImageView *image = (UIImageView *)v;
        // UIKit clips each full-width track in a separate container on iOS 26/27. Match the
        // assigned image as well for sliders that fit it directly into the played segment.
        if (!(image.image && (image.image == min || image.image == max)) &&
            !(v.superview.clipsToBounds && [v.superview.superview isKindOfClass:NSClassFromString(@"_UISlideriOSVisualElement")])) return;
        [bar.tracks addObject:image];
        image.hidden = YES;
    });
}

static void removeHeldBar(UISlider *slider) {
    SGRHeldBar *bar = objc_getAssociatedObject(slider, &kHeldKey);
    if (!bar) return;
    for (UIImageView *image in bar.tracks) image.hidden = NO;
    [bar removeFromSuperview];
    objc_setAssociatedObject(slider, &kHeldKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void setHeldBar(UISlider *slider, BOOL on) {
    SGRHeldBar *bar = objc_getAssociatedObject(slider, &kHeldKey);
    if (!bar) {
        if (!on) return;
        bar = [SGRHeldBar new];
        bar.userInteractionEnabled = NO;
        bar.accessibilityElementsHidden = YES;
        bar.tracks = [NSHashTable weakObjectsHashTable];
        bar.restHeight = [slider maximumTrackImageForState:UIControlStateNormal].size.height ?: SGRPlayerBarHeight;
        bar.heldHeight = sg_scrubHeight;
        bar.rail = [UIView new];
        bar.rail.clipsToBounds = YES;
        bar.rail.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [bar addSubview:bar.rail];
        bar.fill = [CALayer layer];
        bar.fill.backgroundColor = SGRPlayerBarFill(YES).CGColor;
        bar.remaining = [CALayer layer];
        bar.remaining.backgroundColor = SGRPlayerBarTrack().CGColor;
        [bar.rail.layer addSublayer:bar.fill];
        [bar.rail.layer addSublayer:bar.remaining];
        [slider.superview insertSubview:bar aboveSubview:slider];
        objc_setAssociatedObject(slider, &kHeldKey, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        updateHeldBar(slider);
        bar.rail.frame = CGRectInset(bar.bounds, 0, (bar.heldHeight-bar.restHeight)/2);
        bar.rail.layer.cornerRadius = bar.restHeight/2;
        bar.fill.opacity = CGColorGetAlpha(SGRPlayerBarFill(NO).CGColor);
        hideTrackImages(slider, bar);
    }
    NSUInteger generation = ++bar.generation;
    void (^geometry)(void) = ^{
        CGFloat height = on ? bar.heldHeight : bar.restHeight;
        bar.rail.frame = CGRectInset(bar.bounds, 0, (bar.heldHeight-height)/2);
        bar.rail.layer.cornerRadius = height/2;
        bar.fill.opacity = CGColorGetAlpha(SGRPlayerBarFill(on).CGColor);
    };
    SGRAnimateLayout(bar, ^{
        // The transition snapshots the rail. Don't also interpolate its bounds during the dissolve.
        if (SGRReduceMotion()) [UIView performWithoutAnimation:geometry];
        else geometry();
    }, ^(BOOL finished) {
        if (!on && generation == bar.generation && bar == objc_getAssociatedObject(slider, &kHeldKey))
            removeHeldBar(slider);
    });
}

// What a track of the bar shows: Spotify's image (`spotify`), the one drawn from it (`drawn`) and its color.
@interface SGRBarTrack : NSObject
@property (nonatomic, strong) UIImage *spotify, *drawn;
@property (nonatomic, strong) UIColor *color;
@end
@implementation SGRBarTrack
@end

// Spotify draws its bar with track images (01.txt:1907, 7x7 each); a new image of Spotify's is drawn again in the
// bar's color, and one already drawn only when the color changes. A bar with no image takes the color as its tint.
static void colorTrack(UISlider *slider, BOOL minimum, UIColor *color) {
    const void *key = minimum ? &kBarMinKey : &kBarMaxKey;
    UIControlState state = UIControlStateNormal;
    UIImage *shown = minimum ? [slider minimumTrackImageForState:state] : [slider maximumTrackImageForState:state];
    SGRBarTrack *track = objc_getAssociatedObject(slider, key);
    if (!shown) {
        UIColor *tint = minimum ? slider.minimumTrackTintColor : slider.maximumTrackTintColor;
        if ([tint isEqual:color]) return;
        if (minimum) slider.minimumTrackTintColor = color;
        else slider.maximumTrackTintColor = color;
        return;
    }
    if (!track) {
        track = [SGRBarTrack new];
        objc_setAssociatedObject(slider, key, track, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (shown == track.drawn && [track.color isEqual:color]) return;
    if (shown != track.drawn) track.spotify = shown;
    track.color = color;
    UIImage *image = SGRPlayerBarImage(color, track.spotify.size.height);
    if (minimum) [slider setMinimumTrackImage:image forState:state];
    else [slider setMaximumTrackImage:image forState:state];
    track.drawn = minimum ? [slider minimumTrackImageForState:state] : [slider maximumTrackImageForState:state];
}

static void colorBar(UISlider *slider) {
    if (slider == sg_scrubSlider || !objc_getAssociatedObject(slider, &kBarKey)) return;
    colorTrack(slider, YES, SGRPlayerBarFill(NO));
    colorTrack(slider, NO, SGRPlayerBarTrack());
}

static void brightenTimes(UIView *unit, BOOL on, BOOL animated) {
    brighten(SGRFindByIdentifier(unit, @"now-playing-time-take-label-internal", &kScrubTakeLabelKey), on, animated);
    brighten(SGRFindByIdentifier(unit, @"now-playing-time-remaning-label-internal", &kScrubRemainingLabelKey), on, animated);
}

static void scrubLook(UISlider *slider, BOOL on) {
    if (on) {
        if (sg_scrubSlider && sg_scrubSlider != slider) scrubLook(sg_scrubSlider, NO);
        sg_scrubSlider = slider;
    } else {
        if (sg_scrubSlider != slider) return;
        sg_scrubSlider = nil;
    }
    if (!on || objc_getAssociatedObject(slider, &kBarKey)) setHeldBar(slider, on);
    invalidateColor(slider);
    SGRAnimateLayout(slider, ^{
        [slider setNeedsLayout];
        [slider layoutIfNeeded];
    }, nil);
    colorBar(slider);
    UIView *unit = timesAround(slider);
    if (!unit) return;
    brightenTimes(unit, on, YES);
    UIView *take = SGRFindByIdentifier(unit, @"now-playing-time-take-label", &kScrubTakeKey);
    UIView *remaining = SGRFindByIdentifier(unit, @"now-playing-time-remaning-label", &kScrubRemainingKey);
    CGAffineTransform drop = timesDrop(on);
    SGRAnimate(SGRMotionPress, ^{
        take.transform = drop;
        remaining.transform = drop;
    }, nil);
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"redesign player: a scrub thickens the bar, times %@", take ? @"brightened and lowered" : @"not found"); });
}

// Spotify writes the times as the thumb moves, which can bring its own color back.
static void keepScrubLook(UIView *host) {
    UISlider *slider = sg_scrubSlider;
    if (!slider || (host && ![slider isDescendantOfView:host])) return;
    UIView *unit = timesAround(slider);
    if (unit) brightenTimes(unit, YES, NO);
}

// Spotify sets its progress bars on every frame it plays, the player's and the bar's over the tabs alike. A bar
// moves a pixel in about a fifth of a second, so nearly all of those set a place that draws the same pixels, and
// each one still lays the slider out and commits, which redraws the glass around it at the display's rate for as
// long as music plays. A set that lands on the pixel the bar is drawn at is dropped; the next pixel is taken.
@interface SGRBarStep : NSObject {
@public
    float minimum, maximum;
    CGFloat width, scale;
}
@end
@implementation SGRBarStep
@end

static BOOL sameBarPixel(UISlider *slider, float value) {
    CGFloat width = slider.bounds.size.width;
    float minimum = slider.minimumValue, maximum = slider.maximumValue;
    CGFloat scale = slider.window.screen.scale;
    SGRBarStep *step = objc_getAssociatedObject(slider, &kStepKey);
    if (!(scale > 0 && width > 0 && maximum > minimum && isfinite(value))) {
        if (step) step->width = 0;
        return NO;
    }
    if (step && step->width == width && step->scale == scale && step->minimum == minimum && step->maximum == maximum) {
        // Compare with the actual control, not a cached request: UIKit can move it during a scrub.
        double drawn = slider.value;
        if (value <= minimum || value >= maximum) return drawn == value;
        double pixels = width * scale / ((double)maximum - minimum);
        return lround((drawn - minimum) * pixels) == lround(((double)value - minimum) * pixels);
    }
    if (!step) {
        step = [SGRBarStep new];
        objc_setAssociatedObject(slider, &kStepKey, step, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    step->scale = scale;
    step->minimum = minimum;
    step->maximum = maximum;
    step->width = width;
    return NO;
}

%hook _TtCO17NowPlaying_ECMKit11ProgressBar6Slider
- (void)setMinimumTrackImage:(UIImage *)image forState:(UIControlState)state {
    %orig;
    invalidateColor((UISlider *)self);
}
- (void)setMaximumTrackImage:(UIImage *)image forState:(UIControlState)state {
    %orig;
    invalidateColor((UISlider *)self);
}
- (void)setMinimumTrackTintColor:(UIColor *)color {
    %orig;
    invalidateColor((UISlider *)self);
}
- (void)setMaximumTrackTintColor:(UIColor *)color {
    %orig;
    invalidateColor((UISlider *)self);
}
- (void)setAccessibilityIdentifier:(NSString *)identifier {
    %orig;
    SGRSliderLayout *layout = objc_getAssociatedObject(self, &kLayoutKey);
    if (layout) layout->idleRevision = layout->mixRevision = 0;
}
- (void)setValue:(float)value animated:(BOOL)animated {
    if (SGRWritingProgress) SGRProgressSliderWrote((UISlider *)self);
    UISlider *slider = (UISlider *)self;
    if (animated || slider.isTracking) {
        SGRBarStep *step = objc_getAssociatedObject(slider, &kStepKey);
        if (step) step->width = 0;
    } else if (sameBarPixel(slider, value)) return;
    %orig;
}

- (BOOL)isTracking {
    return ((UISlider *)self == sg_seekSlider && seekHeld()) || %orig;
}

- (CGRect)trackRectForBounds:(CGRect)bounds {
    CGRect track = %orig;
    if ((UISlider *)self != sg_scrubSlider || track.size.height <= 0) return track;
    CGFloat height = sg_scrubHeight;
    return CGRectMake(track.origin.x, CGRectGetMidY(track) - height / 2, track.size.width, height);
}

// PlayerScroll.x and Shared/Haptics/ControlHaptics.x hook the same tracking; all call through.
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    cancelSeek();
    UISlider *slider = (UISlider *)self;
    // Spotify can select a taller image on touch down. Grow from the normal track, not from that image.
    CGFloat rest = [slider maximumTrackImageForState:UIControlStateNormal].size.height ?: [slider trackRectForBounds:slider.bounds].size.height;
    BOOL tracking = %orig;
    if (tracking) {
        sg_scrubHeight = SGRPlayerBarDragHeight(rest);
        SGRProgressRailChanged(slider, YES);
        scrubLook(slider, YES);
    }
    return tracking;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    BOOL tracking = %orig;
    if ((UISlider *)self == sg_scrubSlider) {
        updateHeldBar((UISlider *)self);
        keepScrubLook(nil);
    }
    return tracking;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    objc_setAssociatedObject(self, &kStepKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig;
    scrubLook((UISlider *)self, NO);
    SGRProgressRailChanged((UISlider *)self, NO);
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    objc_setAssociatedObject(self, &kStepKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig;
    scrubLook((UISlider *)self, NO);
    SGRProgressRailChanged((UISlider *)self, NO);
}

- (void)didMoveToWindow {
    %orig;
    SGRProgressOutputMounted((UIView *)self);
    objc_setAssociatedObject(self, &kStepKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!((UIView *)self).window) {
        scrubLook((UISlider *)self, NO);
        removeHeldBar((UISlider *)self);
    }
}

- (void)willMoveToSuperview:(UIView *)parent {
    if (parent != ((UISlider *)self).superview) {
        scrubLook((UISlider *)self, NO);
        removeHeldBar((UISlider *)self);
    }
    %orig;
}

// The player's bar in its translucent colors, before it lays its tracks out; AutoMix's transition bands behind the knob
// (PlayerMix.x), on the player's own bar only.
- (void)layoutSubviews {
    UISlider *slider = (UISlider *)self;
    SGRSliderLayout *layout = objc_getAssociatedObject(self, &kLayoutKey);
    if (!layout) {
        layout = [SGRSliderLayout new];
        objc_setAssociatedObject(self, &kLayoutKey, layout, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (layout->idleRevision != sg_mixRevision) {
        BOOL contrast = SGRIncreaseContrast();
        if (!layout->colored || layout->contrast != contrast) {
            colorBar(slider);
            layout->contrast = contrast;
            layout->colored = slider != sg_scrubSlider;
        }
    }
    %orig;
    SGRProgressRailChanged(slider, slider.isTracking || slider == sg_scrubSlider);
    // At rest neither track color nor a disabled band depends on the value
    // or bounds. UIKit and the tracker still get every layout, including resizes.
    if (layout->idleRevision == sg_mixRevision) return;
    // Register once even when off. When enabled the band's owner also reads its
    // private transition generation, which can change without the slider moving.
    if (sg_mixProgress || layout->mixRevision != sg_mixRevision) {
        if ([slider.accessibilityIdentifier isEqualToString:kSliderID]) SGRPlayerMixSliderLaidOut(slider);
        layout->mixRevision = sg_mixRevision;
    }
    SGRHeldBar *bar = objc_getAssociatedObject(slider, &kHeldKey);
    if (bar) {
        updateHeldBar(slider);
        hideTrackImages(slider, bar);
    } else if (layout->colored && !sg_mixProgress) {
        layout->idleRevision = sg_mixRevision;
    }
}
%end

// The ordinary player's duration unit and the AI DJ's (DJMDurationElementsUnit) hold the same progress bar and times.
static char kDurationHostKey;

static void durationLaidOut(UIViewController *unit) {
    UIView *host = unit.viewIfLoaded;
    if (!host) return;
    if (!objc_getAssociatedObject(host, &kDurationHostKey)) objc_setAssociatedObject(host, &kDurationHostKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // The bar's element, its times at its edges, inset to the player's margin.
    UIView *bar = SGRFindByIdentifier(host, kSliderID, &kSliderKey);
    // The bar the player shows (the mini player's has the same identifier and no times), drawn translucent.
    if ([bar isKindOfClass:UISlider.class] && !objc_getAssociatedObject(bar, &kBarKey)) {
        objc_setAssociatedObject(bar, &kBarKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        invalidateColor((UISlider *)bar);
        [bar setNeedsLayout];
    }
    while (bar && bar.superview != host) bar = bar.superview;
    if (bar) SGRPlayerHoldMargin(bar, 0);
    watchSlider(host);
    UILabel *taken = monospaced(host, @"now-playing-time-take-label-internal", &kTakeKey);
    monospaced(host, @"now-playing-time-remaning-label-internal", &kRemainingKey);
    keepScrubLook(host);
    // The times lowered, by a scrub's step more while one goes on here.
    UISlider *scrubbed = sg_scrubSlider;
    CGAffineTransform drop = timesDrop(scrubbed && [scrubbed isDescendantOfView:host]);
    for (UIView *time in @[SGRFindByIdentifier(host, @"now-playing-time-take-label", &kTakeTimeKey) ?: NSNull.null,
                           SGRFindByIdentifier(host, @"now-playing-time-remaning-label", &kRemainingTimeKey) ?: NSNull.null]) {
        if ([time isKindOfClass:UIView.class] && !CGAffineTransformEqualToTransform(time.transform, drop)) time.transform = drop;
    }
    SGAudioQualityPlaceRedesignedBadge(host, kTimesDrop);
    // Whether Spotify's font has digits of one width shows in the descriptor's feature settings.
    if (!taken) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"redesign player: monospaced times in %@ %.0fpt, features %@", taken.font.fontName, taken.font.pointSize, taken.font.fontDescriptor.fontAttributes[UIFontDescriptorFeatureSettingsAttribute]); });
}

%hook _TtC20NowPlaying_ModesImpl19DurationElementUnit
- (void)viewDidLayoutSubviews {
    %orig;
    durationLaidOut((UIViewController *)self);
}
%end

// On a change of text size the unit is laid out before its times take their new size, and is not laid out again
// (9.2.0 simulator, 2026-11-18): the elapsed time's own layout places the badge on its baseline again.
%hook SPTEncoreLabel
- (void)layoutSubviews {
    %orig;
    UIView *time = (UIView *)self;
    if (![time.accessibilityIdentifier isEqualToString:@"now-playing-time-take-label"]) return;
    for (UIView *view = time.superview; view; view = view.superview) {
        if (!objc_getAssociatedObject(view, &kDurationHostKey)) continue;
        SGAudioQualityPlaceRedesignedBadge(view, kTimesDrop);
        return;
    }
}
%end

#pragma mark - SponsorBlock marks

// SponsorBlock's segments on the bar (Shared/SponsorBlock/SponsorBlockMarkers.m), installed only with the progress
// bar switch on. Without an episode bar they lie under the translucent rail as AutoMix's bands do (PlayerMix.x), the
// played part's light white over them as over the background, and take the track's height when a scrub thickens it
// (trackRectForBounds: above).
static const double kSponsorBlockMarksOpacity = 0.8;

%group SGRSponsorBlockMarks
%hook _TtCO17NowPlaying_ECMKit11ProgressBar6Slider
- (void)layoutSubviews {
    %orig;
    SGSponsorBlockMarksLaidOut((UISlider *)self);
}

- (void)didMoveToWindow {
    %orig;
    if (((UIView *)self).window) SGSponsorBlockMarksShown((UISlider *)self, kSponsorBlockMarksOpacity);
}
%end
%end

%ctor {
    if (!SGRedesignedUI() || !SGSponsorBlockMarkersEnabled() || !NSClassFromString(@"_TtCO17NowPlaying_ECMKit11ProgressBar6Slider")) return;
    %init(SGRSponsorBlockMarks);
}

#pragma mark - Podcast buffering

static Class sg_episodeSlider, sg_episodeAudio;

%group SGRBufferingHooks
%hook SGRSliderBufferingView
- (void)setFrame:(CGRect)frame {
    UIView *band = (UIView *)self;
    UIView *slider = band.superview;
    if ([slider isKindOfClass:sg_episodeSlider]) {
        // Spotify follows UIKit's track rect, but the chapters draw in a sibling below it.
        for (UIView *audio in slider.subviews) {
            if (![audio isKindOfClass:sg_episodeAudio]) continue;
            CGRect track = audio.frame;
            BOOL rtl = slider.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
            CGFloat left = CGRectGetMinX(frame), right = CGRectGetMaxX(frame);
            if (rtl) left = MIN(right, MAX(left, CGRectGetMinX(track)));
            else right = MAX(left, MIN(right, CGRectGetMaxX(track)));
            frame = CGRectMake(left, track.origin.y, right - left, track.size.height);
            band.layer.maskedCorners = rtl ? kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner
                                           : kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner;
            band.layer.cornerRadius = audio.layer.cornerRadius;
            band.clipsToBounds = YES;
            break;
        }
    }
    %orig(frame);
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    sg_episodeSlider = NSClassFromString(@"_TtCO17NowPlaying_ECMKit11ProgressBar6Slider");
    sg_episodeAudio = NSClassFromString(@"_TtCO17NowPlaying_ECMKit11ProgressBar9AudioView");
    Class band = NSClassFromString(@"NowPlaying_ECMKit.SliderBufferingAnimationView");
    if (band && sg_episodeSlider && sg_episodeAudio) { %init(SGRBufferingHooks, SGRSliderBufferingView = band); }
}

#pragma mark - Duration hooks

// The DJ unit is another class, hooked only when the build has it (see %ctor).
%group SGRDJControlsDurationHooks
%hook SGRDJControlsDurationUnit
- (void)viewDidLayoutSubviews {
    %orig;
    durationLaidOut((UIViewController *)self);
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    sg_mixProgress = SGFlag(SGKeyAutoMixShowProgress, NO);
    [NSNotificationCenter.defaultCenter addObserverForName:UIAccessibilityDarkerSystemColorsStatusDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        sg_mixRevision++;
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:SGAutoMixPlayerOptionsDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        sg_mixProgress = SGFlag(SGKeyAutoMixShowProgress, NO);
        sg_mixRevision++;
    }];
    %init;
    sg_hideShuffle = SGHidden(SGRKeyPlayerHideShuffle);
    sg_hideRepeat = SGHidden(SGRKeyPlayerHideRepeat);
    sg_rollingDigits = SGEnabled(SGRKeyPlayerRollingDigits);
    Class djDuration = SGRDJClass(@"DJMDurationElementsUnit");
    if (djDuration) { %init(SGRDJControlsDurationHooks, SGRDJControlsDurationUnit = djDuration); }
    sg_controlsWatcher = [SGRPlayerControlsWatcher new];
    SGAddPlayerStateObserver(sg_controlsWatcher);
    SGRequireClasses(@[
        @"_TtC20NowPlaying_ModesImpl28PlaybackControlsElementsUnit",
        @"_TtC20NowPlaying_ModesImpl19DurationElementUnit",
        @"_TtC28EncoreConsumerMobile_BaseKit14PlayButtonView",
        @"SPTEncoreIconView",
        @"_TtCO17NowPlaying_ECMKit11ProgressBar6Slider",
    ]);
}
