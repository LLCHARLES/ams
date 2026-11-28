// The redesign's Player page in Mod Settings (App/Pages.m opens it in place of the native look's).
//
// It leads with a miniature of the whole player, pinned over the rows: the header (the album the song is from, as the
// player's header has only its grabber otherwise), the background chosen on the page edge to edge, the cover, the
// title and the artist (gliding when too long) with the ⋯ beside them, Switch to video over them unless it is hidden,
// the translucent progress with the time played and the time left, and the
// transport row with shuffle and repeat left out as their chips say, previous and next spread apart when both are, as
// in the player (PlayerControls.x). The progress is where the track was when the page appeared. With no track, the
// card shows the last one played (Shared/Player/SGLastTrack.h), its cover fetched and its Canvas looked up as the
// playing one's would be, and with none ever played, Not Playing over a gradient of the accent. About
// kPreviewExpandedHeight tall at the top of the page, it shrinks as the rows scroll up to about kPreviewCompactHeight,
// the cover moving from above the title to beside it, and the rows then scroll under it.
//
// The background is the player's own: a field of the same kind (Still, Colors, Fluid), for Animated the clip the
// player is playing (SGRPlayerMotionPreview) in place of the field, or, while the player has none, the shown track's
// clip looked up for the card while it is on screen, Fluid until it comes in and for a track with none, as in the
// player; the clip crosses over the field as it arrives, its poster first while its video decodes. And for Visualizer
// the hills over Fluid held still (SGRPlayerVisualiserPreview), moving with the song. It moves under the field's own
// conditions (in a window, Spotify in front, Reduce Motion and Low Power Mode off, below serious heat). Another track shown reads the
// background again, and an answer that comes for the one before is dropped. The card works only while the page is on
// screen: away, its clip and hills are taken off and nothing it asked for is shown when it comes.
//
// Under Animated a tap on the card, or on its Without a clip button, shows the song as it would be without a clip,
// what Song without a clip picks (the cover art over Fluid, the full-screen cover, or the Visualizer), and a tap again
// shows it as it is; picking a choice there shows it too. It is the card's alone: nothing is asked of the player, and
// another background ends it. Under Low Power Mode, serious heat or Reduce Motion it is the cover art, as the player shows then.
//
// Under the card a segmented control picks the background, all five of them: the names are one word each, each segment
// as wide as its name, so they fit side by side at an iPhone's width, and every choice stays one tap away with the
// card showing it at once. A note under the control says what the choice does; it is given the room of the longest
// note, so the rows under it hold still as it changes.
//
// Under the header: the rows that follow the choice (Animated's sources, Song without a clip, whose choice the open
// player follows at once, SGRPlayerStillChanged and SGRPlayerAnimatedVisualiserChanged, and its Low Data Mode switch;
// Fluid's sliders and their Reset, which the card and the player follow as they move, SGRFluid.h, Grain among them
// only while Smooth draws), the Controls section, whose Header glass and Music app icons switches the open player
// follows at once (SGRPlayerLookChanged), the Mini player section (Redesigned/NowPlayingBar/NowPlayingBarSettings.m),
// then the sections either look shares, the Buttons chips among them (SGRPlayerButtonsSection).
//
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRMotionBudget.h"
#import "Redesigned/Kit/SGRFluid.h"
#import "Redesigned/Kit/SGRFluidGPU.h"
#import "Redesigned/Kit/SGRRefinements.h"
#import "Redesigned/NowPlayingBar/NowPlayingBar.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/Player/PlayerSettings.h"
#import "Shared/Player/SGLastTrack.h"
#import "Player.h"
#import "PlayerLyricLine.h"

extern NSString *const SGRKeyPlayerMusicClose;

// The card's height at the top of the page and once the rows have scrolled up, each capped by the room between the
// bars: expanded it takes at most kPreviewExpandedShare of it, compact kPreviewCompactShare, so the settings always
// keep the rest to scroll in. Compact never goes under what its layout needs at the text size (minimumHeight).
static const CGFloat kPreviewExpandedHeight = 480, kPreviewCompactHeight = 236;
static const CGFloat kPreviewExpandedShare = 0.7, kPreviewCompactShare = 0.42;
static const CGFloat kPinnedGap = 8;     // the page's color above and below the card in its pinned place
static const CGFloat kCardRadius = 26;   // continuous, the radius of the page's own cards and then some
// Inside the card: its side padding, the room over the header row and under the transport row.
static const CGFloat kCardPadding = 16, kCardTop = 12, kCardBottom = 10;
// The header row, and the room either side of its middle (the album's name, the demo's button).
static const CGFloat kHeaderRow = 32, kHeaderSide = 38;
static const CGFloat kCompactCover = 64;   // the cover beside the title, compact
// Between the two the cover waits at its compact size above the words while they move beside it: from this expansion
// down to the next one.
static const CGFloat kCoverParkedAbove = 0.6, kCoverParkedBelow = 0.4;
static const CGFloat kMoreGlyph = 18, kMoreSlot = 30;
static const CGFloat kTransportRow = 44, kSkipGlyph = 22, kPlayGlyph = 30, kSideGlyph = 17;
static const CGFloat kProgressLine = 4;
// The cover's foot under the full-screen cover, darkened for the words over it.
static const CGFloat kStillFootDim = 0.55;
// The Buttons chips: their height (a touch target), the gap between two, their redraw when one is tapped.
static const CGFloat kChipHeight = 44, kChipGap = 8;
static const NSTimeInterval kChipTransition = 0.2;

// What each background does, in SGRPlayerBackgroundKind's order.
static NSArray<NSString *> *backgroundNotes(void) {
    return @[
        SGL(@"settings.player.bg_desc.still", @"The cover, blurred and held still."),
        SGL(@"settings.player.bg_desc.colors", @"The cover's colors, drifting slowly."),
        SGL(@"settings.player.bg_desc.fluid", @"The cover itself, blurred and slowly turning. It rests while a song is paused."),
        SGL(@"settings.player.bg_desc.animated", @"Play the song's Canvas or the album's moving cover when available. The player's ⋯ menu switches between this, Fluid and Visualizer."),
        SGL(@"settings.player.bg_desc.visualizer", @"The song's sound in Hills, Bars, Nebula or Halo, or its synced lyrics in Lyrics, Poster or Cut, over Fluid held still. Choose a style below; it settles on pause or silence."),
        SGL(@"settings.player.bg_desc.black", @"Pure black, nothing of the cover."),
        SGL(@"settings.player.bg_desc.photo", @"A photo of your own, darkened so the words over it stay easy to read."),
    ];
}

// "Behind the player": the artwork's choices, black, or a photo, in that order.
static NSArray<NSString *> *behindNames(void) {
    return @[SGL(@"settings.player.behind.artwork", @"Artwork"), SGL(@"settings.player.behind.black", @"Black"),
             SGL(@"settings.player.behind.photo", @"Your Photo")];
}

// The segment of an artwork's choice; none is lit under black or a photo.
static NSInteger segmentOf(SGRPlayerBackgroundKind kind) {
    return SGRPlayerBackgroundFromArtwork(kind) ? kind : UISegmentedControlNoSegment;
}

#pragma mark - Song without a clip

typedef NS_ENUM(NSInteger, SGRNoClip) {
    SGRNoClipStill = SGRPlayerBackgroundStill,
    SGRNoClipColours = SGRPlayerBackgroundColours,
    SGRNoClipFluid = SGRPlayerBackgroundFluid,
    SGRNoClipFullScreen,
    SGRNoClipVisualiser,
};

static NSArray<NSString *> *noClipNames(void) {
    NSArray *backgrounds = SGRPlayerBackgroundNames();
    return @[backgrounds[SGRPlayerBackgroundStill], backgrounds[SGRPlayerBackgroundColours], backgrounds[SGRPlayerBackgroundFluid],
             SGL(@"settings.player.no_clip.full_screen", @"Full-screen cover"), backgrounds[SGRPlayerBackgroundVisualiser]];
}

// The full-screen cover wins over the Visualizer, as SGRPlayerReconcileFallbackSwitches keeps it, so both saved on by an
// older build read as the full-screen cover without anything stored here.
static SGRNoClip noClipStored(void) {
    if (SGRPlayerStillOn()) return SGRNoClipFullScreen;
    return SGRPlayerAnimatedVisualiserOn() ? SGRNoClipVisualiser : (SGRNoClip)SGRPlayerNoClipBackground();
}

// One switch turned on at most, the other one first turned off and followed by the player, so the two are never on
// together, not even between the two writes. A switch already as wanted is not written.
static void pickNoClip(SGRNoClip choice) {
    if (choice != SGRNoClipFullScreen && SGRPlayerStillOn()) {
        SGSetEnabled(SGRKeyPlayerAnimatedStill, NO);
        SGRPlayerStillChanged();
    }
    if (choice != SGRNoClipVisualiser && SGRPlayerAnimatedVisualiserOn()) {
        SGSetEnabled(SGRKeyPlayerAnimatedVisualiser, NO);
        SGRPlayerAnimatedVisualiserChanged();
    }
    if (choice == SGRNoClipFullScreen && !SGRPlayerStillOn()) {
        SGSetEnabled(SGRKeyPlayerAnimatedStill, YES);
        SGRPlayerStillChanged();
    }
    if (choice == SGRNoClipVisualiser && !SGRPlayerAnimatedVisualiserOn()) {
        SGSetEnabled(SGRKeyPlayerAnimatedVisualiser, YES);
        SGRPlayerAnimatedVisualiserChanged();
    }
    if (choice <= SGRNoClipFluid) SGRSetPlayerNoClipBackground((SGRPlayerBackgroundKind)choice);
    SGRPlayerReconcileFallbackSwitches();
}

// Reduce Motion, Low Power Mode or serious heat keeps the cover art, whatever the choice (PlayerMotion.x, motionAllowed).
static BOOL noClipMotionAllowed(void) {
    return !SGRReduceMotion() && !SGRMotionHeldForPowerOrHeat();
}

#pragma mark - the card

// The type of the card, at the text size of `traits` up to the largest each part has room for.
static UIFont *cardFont(UIFontTextStyle style, CGFloat size, UIFontWeight weight, CGFloat largest, UITraitCollection *traits) {
    return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:[UIFont systemFontOfSize:size weight:weight]
                                                       maximumPointSize:largest compatibleWithTraitCollection:traits];
}

static UIImageView *glyphView(NSString *symbol, CGFloat size, UIImageSymbolWeight weight) {
    UIImageView *view = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol withConfiguration:
                          [UIImageSymbolConfiguration configurationWithPointSize:size weight:weight]]];
    view.tintColor = SGRPrimary();
    view.contentMode = UIViewContentModeCenter;
    return view;
}

static void setGlyph(UIImageView *view, NSString *symbol) {
    view.image = [UIImage systemImageNamed:symbol withConfiguration:view.image.symbolConfiguration];
    [view sizeToFit];
}

static NSString *timeText(NSTimeInterval seconds) {
    long whole = lround(MAX(0, seconds));
    return [NSString stringWithFormat:@"%ld:%02ld", whole / 60, whole % 60];
}

static CGFloat mix(CGFloat a, CGFloat b, CGFloat t) { return a + (b - a) * t; }
static CGRect mixRect(CGRect a, CGRect b, CGFloat t) {
    return CGRectMake(round(mix(a.origin.x, b.origin.x, t)), round(mix(a.origin.y, b.origin.y, t)),
                      round(mix(a.size.width, b.size.width, t)), round(mix(a.size.height, b.size.height, t)));
}

@interface SGRPlayerPreview : UIView <SGPlayerStateObserver>
// The height the compact layout needs at the card's text size.
@property (nonatomic, readonly) CGFloat minimumHeight;
// The song shown without a clip; only under Animated.
@property (nonatomic, readonly) BOOL demo;
// On screen: the card follows the player, the page's switches and the system's motion settings. Off, it does nothing,
// its clip and hills off it.
- (void)setActive:(BOOL)active;
- (void)reloadBackgroundAnimated:(BOOL)animated;
// The header's glass, the add button and the buttons left out, read again.
- (void)reloadLook;
- (void)setDemo:(BOOL)demo;
@end

@implementation SGRPlayerPreview {
    UIView *_canvas;   // everything the card draws: one element for VoiceOver, the demo's button beside it
    UIView *_background; // fixed-height render surface, bottom-aligned and clipped as the card collapses
    SGRArtworkField *_field;
    UIView *_motion, *_visualiser, *_backdrop;
    UIImageView *_still;          // the full-screen cover, the demo's
    CAGradientLayer *_stillDim;
    UILabel *_context;
    UIButton *_demoButton;
    UIImageView *_cover;
    UIView *_chip;
    UIImageView *_chipGlyph;
    UILabel *_chipLabel;
    SGMarqueeLabel *_title, *_artist;
    UIImageView *_more, *_star;   // the star add button, before the ⋯, while Star add button is on
    BOOL _starAdd;
    UIView *_progress, *_progressFill;
    UILabel *_elapsed, *_remaining;
    UIImageView *_shuffle, *_previous, *_play, *_next, *_repeat;
    UIContentSizeCategory _fontsFor;
    CGSize _demoSize;
    NSString *_demoText;
    CGFloat _chipWidth, _chipHeight, _titleHeight, _artistHeight, _timeHeight;
    CGFloat _position;
    BOOL _paused, _active, _demo, _previewMiss;
    BOOL _hideShuffle, _hideRepeat, _hideVideo;
    NSString *_track;      // the shown track
    NSString *_artworkOf;  // the last track whose cover the card asked for
    // Advanced as another track is shown and as the card goes off screen: an answer for an older one is dropped.
    NSUInteger _generation;
    NSArray<id> *_observers;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.clipsToBounds = YES;
    self.layer.cornerRadius = kCardRadius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.backgroundColor = SGRNeutralField();

    _canvas = [[UIView alloc] initWithFrame:self.bounds];
    _canvas.isAccessibilityElement = YES;
    _canvas.accessibilityTraits = UIAccessibilityTraitImage;
    _canvas.accessibilityLabel = SGL(@"settings.player.preview.a11y", @"Player preview");
    [self addSubview:_canvas];

    _background = [UIView new];
    [_canvas addSubview:_background];
    _field = [[SGRArtworkField alloc] initWithFrame:frame];
    _field.showsBackdrop = YES;
    [_background addSubview:_field];

    _still = [UIImageView new];
    _still.contentMode = UIViewContentModeScaleAspectFill;
    _still.clipsToBounds = YES;
    _still.hidden = YES;
    _stillDim = [CAGradientLayer layer];
    _stillDim.colors = @[(id)UIColor.clearColor.CGColor, (id)[UIColor colorWithWhite:0 alpha:kStillFootDim].CGColor];
    _stillDim.locations = @[@0.4, @1];
    [_still.layer addSublayer:_stillDim];
    [_canvas addSubview:_still];

    // The header: the album the song is from.
    _context = [UILabel new];
    _context.textColor = SGRSecondary();
    _context.textAlignment = NSTextAlignmentCenter;
    [_canvas addSubview:_context];

    _cover = [UIImageView new];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.cornerCurve = kCACornerCurveContinuous;
    _cover.backgroundColor = SGRSolidGlassFill();
    [_canvas addSubview:_cover];

    // Switch to video, the chip Spotify puts over the title of a song with a music video.
    _chip = [UIView new];
    _chip.backgroundColor = SGRSolidGlassFill();
    _chipGlyph = glyphView(@"play.rectangle.fill", 11, UIImageSymbolWeightSemibold);
    _chipLabel = [UILabel new];
    _chipLabel.textColor = SGRPrimary();
    _chipLabel.text = SGL(@"settings.player.hide_video_switch.title", @"Switch to video");
    [_chip addSubview:_chipGlyph];
    [_chip addSubview:_chipLabel];
    [_canvas addSubview:_chip];

    // The words glide as the player's own do.
    _title = [SGMarqueeLabel new];
    _title.textColor = SGRPrimary();
    _artist = [SGMarqueeLabel new];
    _artist.textColor = SGRSecondary();
    _more = glyphView(@"ellipsis", kMoreGlyph, UIImageSymbolWeightSemibold);
    _star = glyphView(@"star", kMoreGlyph, UIImageSymbolWeightSemibold);
    [_canvas addSubview:_title];
    [_canvas addSubview:_artist];
    [_canvas addSubview:_more];
    [_canvas addSubview:_star];

    // The player's slider as it is drawn at rest: a track, and in it a fill up to where the song is.
    _progress = [UIView new];
    _progress.backgroundColor = SGRPlayerBarTrack();
    _progress.clipsToBounds = YES;
    _progressFill = [UIView new];
    _progressFill.backgroundColor = SGRPlayerBarFill(NO);
    [_progress addSubview:_progressFill];
    _elapsed = [UILabel new];
    _remaining = [UILabel new];
    _remaining.textAlignment = NSTextAlignmentRight;
    for (UILabel *label in @[_elapsed, _remaining]) label.textColor = SGRSecondary();
    [_canvas addSubview:_progress];
    [_canvas addSubview:_elapsed];
    [_canvas addSubview:_remaining];

    _shuffle = glyphView(@"shuffle", kSideGlyph, UIImageSymbolWeightSemibold);
    _previous = glyphView(@"backward.fill", kSkipGlyph, UIImageSymbolWeightRegular);
    _play = glyphView(@"play.fill", kPlayGlyph, UIImageSymbolWeightRegular);
    _next = glyphView(@"forward.fill", kSkipGlyph, UIImageSymbolWeightRegular);
    _repeat = glyphView(@"repeat", kSideGlyph, UIImageSymbolWeightSemibold);
    for (UIView *glyph in @[_shuffle, _previous, _play, _next, _repeat]) [_canvas addSubview:glyph];

    // The demo's switch: shown under Animated, filled while the card shows the song without a clip.
    _demoButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _demoButton.accessibilityLabel = SGL(@"settings.player.preview.demo.a11y", @"Preview without a clip");
    [_demoButton addTarget:self action:@selector(toggleDemo) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_demoButton];
    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleDemo)]];

    SGAddPlayerStateObserver(self);
    [self readFonts];
    [self reloadLook];
    [self showArtwork:nil identity:nil];
    [self holdField];
    return self;
}

- (void)dealloc {
    for (id observer in _observers) [NSNotificationCenter.defaultCenter removeObserver:observer];
}

- (void)setActive:(BOOL)active {
    if (active == _active) return;
    _active = active;
    _generation++;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (id observer in _observers) [center removeObserver:observer];
    _observers = nil;
    if (!active) {
        SGRPlayerMotionPreviewStop();
        SGRPlayerVisualiserPreviewStop();
        // Off the page: the clip and the hills come off the card, so neither plays for it.
        [_motion removeFromSuperview];
        _motion = nil;
        [_visualiser removeFromSuperview];
        _visualiser = nil;
        [self holdField];
        return;
    }
    __weak SGRPlayerPreview *weakSelf = self;
    void (^background)(NSNotification *) = ^(NSNotification *note) {
        // Power and thermal changes can be posted off the main thread, which must not wait for main (AGENTS.md).
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf reloadBackgroundAnimated:YES]; });
    };
    _observers = @[
        [center addObserverForName:SGRNowPlayingArtworkDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) { [weakSelf artworkChanged]; }],
        [center addObserverForName:SGRVisualiserStyleDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) { [weakSelf updateAccessibilityValue]; }],
        [center addObserverForName:NSProcessInfoPowerStateDidChangeNotification object:nil queue:nil usingBlock:background],
        [center addObserverForName:NSProcessInfoThermalStateDidChangeNotification object:nil queue:nil usingBlock:background],
        [center addObserverForName:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil queue:nil usingBlock:background],
    ];
    [self reloadLook];
    [self reloadTrack];
    [self reloadBackgroundAnimated:NO];
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    if (!_active) return;
    NSString *was = _track;
    [self reloadTrack];
    if (_track == was || [_track isEqualToString:was]) return;
    // Another track: what was asked for the last one is dropped, and the background is read again once the player's
    // own observers have taken the track up (PlayerMotion.x lets the last clip go there).
    NSUInteger generation = _generation;
    __weak SGRPlayerPreview *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        SGRPlayerPreview *preview = weakSelf;
        if (preview && preview->_active && preview->_generation == generation) [preview reloadBackgroundAnimated:YES];
    });
}

// The Kit's cover of the shown track; a picture still the last track's is not taken for this one's.
- (void)artworkChanged {
    if (!_active) return;
    NSString *uri = nil, *identity = nil;
    UIImage *image = SGRNowPlayingArtwork(&uri, &identity);
    if (image && _track && [uri isEqualToString:_track]) [self showArtwork:image identity:identity];
}

// The cover and the field from `image`, or from the placeholder for nil.
- (void)showArtwork:(UIImage *)image identity:(NSString *)identity {
    static UIImage *placeholder;
    static UIColor *tint;
    if (!image && (!placeholder || ![tint isEqual:SGGreen()])) {
        tint = SGGreen();
        placeholder = SGPlaceholderArtwork(tint);
    }
    _cover.image = image ?: placeholder;
    _still.image = _cover.image;
    [_field setArtwork:_cover.image identity:image ? identity : @"placeholder" animated:self.window != nil];
}

- (void)readFonts {
    UITraitCollection *traits = self.traitCollection;
    if ([_fontsFor isEqualToString:traits.preferredContentSizeCategory]) return;
    _fontsFor = traits.preferredContentSizeCategory;
    _title.font = cardFont(UIFontTextStyleHeadline, 17, UIFontWeightSemibold, 22, traits);
    _artist.font = cardFont(UIFontTextStyleSubheadline, 15, UIFontWeightRegular, 19, traits);
    _context.font = cardFont(UIFontTextStyleCaption1, 12, UIFontWeightSemibold, 15, traits);
    _chipLabel.font = cardFont(UIFontTextStyleCaption2, 11, UIFontWeightSemibold, 14, traits);
    UIFont *time = SGMonospacedDigitsFont(cardFont(UIFontTextStyleCaption2, 11, UIFontWeightMedium, 14, traits));
    _elapsed.font = time;
    _remaining.font = time;
    _titleHeight = ceil(_title.font.lineHeight);
    _artistHeight = ceil(_artist.font.lineHeight);
    _timeHeight = ceil(time.lineHeight);
    _chipHeight = ceil(_chipLabel.font.lineHeight) + 8;
    _chipWidth = ceil(_chipGlyph.bounds.size.width + 4 + [_chipLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, _chipHeight)].width) + 16;
    _demoSize = CGSizeZero;
    [self updateDemoButton];
    [self setNeedsLayout];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    [self readFonts];
}

- (void)reloadLook {
    _context.alpha = SGEnabled(SGRKeyPlayerHideContext) ? 0 : 1;
    _context.accessibilityElementsHidden = SGEnabled(SGRKeyPlayerHideContext);
    _hideShuffle = SGHidden(SGRKeyPlayerHideShuffle);
    _hideRepeat = SGHidden(SGRKeyPlayerHideRepeat);
    _hideVideo = SGVideoSwitchHiddenForLook(YES);
    _shuffle.alpha = _hideShuffle ? 0 : 1;
    _repeat.alpha = _hideRepeat ? 0 : 1;
    _chip.hidden = _hideVideo;
    _starAdd = SGHidden(SGRKeyPlayerStarAdd);
    _star.hidden = !_starAdd;
    [self setNeedsLayout];
}

// The track, where it is and whether it plays, read again.
- (void)reloadTrack {
    SPTPlayerState *state = SGPlayerState();
    SGShownTrack *shown = SGShownTrackNow();
    // Advance before asking for artwork: a last-song image can answer synchronously from its cache.
    if (_track != shown.uri && ![_track isEqualToString:shown.uri]) {
        _generation++;
        _previewMiss = NO;
    }
    _track = shown.uri;
    _title.text = shown.title ?: SGL(@"settings.player.not_playing", @"Not Playing");
    _artist.text = shown.artist ?: @"";
    _context.text = shown.album ?: @"";
    BOOL timed = shown.current && state.duration > 0;
    _position = timed ? MIN(1, MAX(0, state.position / state.duration)) : 0;
    _elapsed.text = timeText(timed ? state.position : 0);
    _remaining.text = timed ? [@"-" stringByAppendingString:timeText(state.duration - state.position)] : @"-:--";
    _paused = !shown.current || state.isPaused;
    setGlyph(_play, _paused ? @"play.fill" : @"pause.fill");
    [self holdField];
    if (shown.current) {
        // The playing track's cover once the Kit has it; until then the last one stays, as in the player.
        _artworkOf = nil;
        if (!_cover.image) [self showArtwork:nil identity:nil];
        [self artworkChanged];
    } else if (shown.artworkURL) {
        // The last track's cover, the placeholder until it comes.
        NSString *uri = shown.uri;
        if (![_artworkOf isEqualToString:uri]) [self showArtwork:nil identity:nil];
        _artworkOf = uri;
        NSUInteger generation = _generation;
        __weak SGRPlayerPreview *weakSelf = self;
        SGShownTrackArtwork(shown, ^(UIImage *image) {
            SGRPlayerPreview *preview = weakSelf;
            SGShownTrack *now = SGShownTrackNow();
            if (image && preview && preview->_active && preview->_generation == generation && !now.current && [now.uri isEqualToString:uri])
                [preview showArtwork:image identity:[@"last:" stringByAppendingString:uri]];
        });
    } else {
        // Nothing ever played.
        _artworkOf = nil;
        [self showArtwork:nil identity:nil];
    }
    [self setNeedsLayout];
}

// The clip, the hills, black, a photo or the full-screen cover cover the field, which then holds still, as in the
// player; and so it does for a paused song, and for the demo where motion is not allowed.
- (void)holdField {
    // The visualizer still shows the field through its hills; a backdrop or full-screen still does not.
    _field.covered = !_active || _backdrop != nil || !_still.hidden || _motion != nil;
    _field.motionHeld = !_active || _paused || _motion != nil || _visualiser != nil || _backdrop != nil || !_still.hidden ||
        (_demo && !noClipMotionAllowed()) || ((_demo || _previewMiss) && SGRPlayerNoClipHoldEnabled());
    if (_active) SGRPlayerConfigureField(_field, _demo || _previewMiss);
}

- (BOOL)demoAvailable {
    return SGRPlayerBackground() == SGRPlayerBackgroundAnimated;
}

// What the demo shows: the choice, or the cover art where motion is not allowed.
- (SGRNoClip)demoShows {
    return noClipMotionAllowed() ? noClipStored() : (SGRNoClip)SGRPlayerNoClipBackground();
}

- (void)toggleDemo {
    [self setDemo:!_demo];
}

- (void)setDemo:(BOOL)demo {
    if (!self.demoAvailable) demo = NO;
    if (demo == _demo && !demo) return;
    _demo = demo;
    [self reloadBackgroundAnimated:YES];
}

- (void)updateDemoButton {
    BOOL on = _demo;
    NSString *text = SGL(@"settings.player.preview.demo", @"Without a clip");
    BOOL measure = CGSizeEqualToSize(_demoSize, CGSizeZero) || ![_demoText isEqualToString:text];
    _demoText = text;
    UIButtonConfiguration *look = on ? [UIButtonConfiguration filledButtonConfiguration] : [UIButtonConfiguration grayButtonConfiguration];
    look.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    look.baseBackgroundColor = on ? SGRPrimary() : SGRSolidGlassFill();
    look.baseForegroundColor = on ? UIColor.blackColor : SGRPrimary();
    look.contentInsets = NSDirectionalEdgeInsetsMake(4, 10, 4, 10);
    look.titleLineBreakMode = NSLineBreakByTruncatingTail;
    look.attributedTitle = [[NSAttributedString alloc] initWithString:text
                                                           attributes:@{NSFontAttributeName: _context.font ?: [UIFont systemFontOfSize:12]}];
    _demoButton.configuration = look;
    if (measure) _demoSize = [_demoButton sizeThatFits:CGSizeMake(CGFLOAT_MAX, kHeaderRow)];
    _demoButton.selected = on;
    _demoButton.accessibilityTraits = UIAccessibilityTraitButton | (on ? UIAccessibilityTraitSelected : 0);
    _demoButton.hidden = !self.demoAvailable;
    _context.hidden = !_demoButton.hidden;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    // On screen under Animated with no clip in: one is looked up, and shown once it is in.
    if (self.window && _active && !_motion && !_demo && SGRPlayerBackground() == SGRPlayerBackgroundAnimated) [self reloadBackgroundAnimated:NO];
}

// The background chosen, read again; a new one crosses over when animated. A clip is looked up only while the card
// is on screen, and one that comes for a track no longer shown, or after the card went off screen, is dropped.
- (void)reloadBackgroundAnimated:(BOOL)animated {
    if (!_active) return;
    SGRPlayerBackgroundKind kind = SGRPlayerBackground();
    if (!self.demoAvailable) _demo = NO;   // another background ends the demo
    if (kind != SGRPlayerBackgroundAnimated || _demo) SGRPlayerMotionPreviewStop();
    SGRNoClip shows = _demo ? [self demoShows] : SGRNoClipStill;
    NSString *track = _track;
    NSUInteger generation = _generation;
    __weak SGRPlayerPreview *weakSelf = self;
    _previewMiss = NO;
    void (^arrived)(BOOL) = !self.window || _demo ? nil : ^(BOOL found){
        SGRPlayerPreview *preview = weakSelf;
        if (!preview || !preview->_active || preview->_generation != generation || ![SGShownTrackNow().uri isEqualToString:track]) return;
        if (preview->_motion || preview->_demo || SGRPlayerBackground() != SGRPlayerBackgroundAnimated) return;
        if (found) [preview reloadBackgroundAnimated:YES];
        else {
            preview->_previewMiss = YES;
            [preview holdField];
        }
    };
    // Black or the photo lies over a field made as the artwork's last choice, as in the player.
    void (^apply)(void) = ^{
        [self->_backdrop removeFromSuperview];
        self->_backdrop = SGRPlayerBackdropPreview();
        if (self->_backdrop) [self->_background insertSubview:self->_backdrop aboveSubview:self->_field];
        // The last clip goes before another is asked for: the card plays one video at most.
        [self->_motion removeFromSuperview];
        self->_motion = nil;
        self->_motion = kind == SGRPlayerBackgroundAnimated && !self->_demo ? SGRPlayerMotionPreview(arrived) : nil;
        if (self->_motion) [self->_background insertSubview:self->_motion aboveSubview:self->_field];
        [self->_visualiser removeFromSuperview];
        BOOL hills = kind == SGRPlayerBackgroundVisualiser || shows == SGRNoClipVisualiser;
        self->_visualiser = hills ? SGRPlayerVisualiserPreview() : nil;
        if (self->_visualiser) [self->_background insertSubview:self->_visualiser aboveSubview:self->_field];
        self->_still.hidden = shows != SGRNoClipFullScreen;
        self->_cover.alpha = self->_still.hidden ? 1 : 0;
        [self holdField];
        [self updateDemoButton];
        [self setNeedsLayout];
        [self layoutIfNeeded];
    };
    [self updateAccessibilityValue];
    if (animated && self.window) {
        // A crossfade, which Reduce Motion keeps: nothing moves.
        [UIView transitionWithView:self duration:SGRCrossfade options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowAnimatedContent
                        animations:apply completion:nil];
    } else {
        apply();
    }
}

- (void)updateAccessibilityValue {
    // Describe what the card actually contains, even while the player's background change is pending.
    SGRPlayerBackgroundKind kind = SGRPlayerBackground();
    NSString *name = SGRPlayerBackgroundFromArtwork(kind) ? SGRPlayerBackgroundNames()[(NSUInteger)kind]
                   : behindNames()[kind == SGRPlayerBackgroundBlack ? 1 : 2];
    NSString *value = kind == SGRPlayerBackgroundVisualiser
        ? [NSString stringWithFormat:SGL(@"settings.player.bg_visualizer.format", @"Visualizer background, %@"), SGRVisualiserStyleNames()[[SGRVisualiserStyleIDs() indexOfObject:SGRVisualiserStyle()]]]
        : [name stringByAppendingString:SGL(@"settings.player.bg_suffix", @" background")];
    if (_demo) value = [NSString stringWithFormat:SGL(@"settings.player.preview.demo_value.format", @"%@, without a clip: %@"), value, noClipNames()[[self demoShows]]];
    _canvas.accessibilityValue = value;
}

// The words, the cover and Switch to video, compact beside each other or expanded the cover over them. Their
// transition follows the actual height, not the page's scroll fraction: a shorter screen never parks a cover
// above the words before there is room for it. Header and transport stay at the two ends.
- (void)layoutSubviews {
    [super layoutSubviews];
    [self readFonts];
    CGRect bounds = self.bounds;
    CGFloat w = bounds.size.width, h = bounds.size.height, p = kCardPadding;
    _canvas.frame = bounds;
    // A collapse moves the render surface; it never rebuilds the field's bitmaps or the video's/visualizer's geometry.
    CGRect backgroundBounds = CGRectMake(0, 0, w, kPreviewExpandedHeight);
    if (!CGRectEqualToRect(_background.bounds, backgroundBounds)) _background.bounds = backgroundBounds;
    _background.center = CGPointMake(w / 2, h - backgroundBounds.size.height / 2);
    if (!CGRectEqualToRect(_field.frame, backgroundBounds)) _field.frame = backgroundBounds;
    if (_field.backdropHeight != backgroundBounds.size.height) _field.backdropHeight = backgroundBounds.size.height;
    if (!CGRectEqualToRect(_motion.frame, backgroundBounds)) _motion.frame = backgroundBounds;
    if (!CGRectEqualToRect(_visualiser.frame, backgroundBounds)) _visualiser.frame = backgroundBounds;
    if (!CGRectEqualToRect(_backdrop.frame, backgroundBounds)) _backdrop.frame = backgroundBounds;
    _still.frame = bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _stillDim.frame = _still.bounds;
    [CATransaction commit];

    // The header.
    CGFloat middleX = p + kHeaderSide, middleWidth = MAX(0, w - 2 * middleX);
    _context.frame = CGRectMake(middleX, kCardTop, middleWidth, kHeaderRow);
    CGSize demo = _demoSize;
    demo = CGSizeMake(MIN(middleWidth, ceil(demo.width)), MIN(kHeaderRow, ceil(demo.height)));
    _demoButton.frame = CGRectMake(round((w - demo.width) / 2), kCardTop + round((kHeaderRow - demo.height) / 2), demo.width, demo.height);

    // The foot: the transport row, the times, the progress line over them.
    CGFloat transportY = h - kCardBottom - kTransportRow;
    CGFloat timeHeight = _timeHeight, timeY = transportY - 4 - timeHeight;
    CGFloat lineY = timeY - 4 - kProgressLine, inner = w - 2 * p;
    _progress.frame = CGRectMake(p, lineY, inner, kProgressLine);
    _progress.layer.cornerRadius = kProgressLine / 2;
    _progressFill.frame = CGRectMake(0, 0, round(inner * _position), kProgressLine);
    _elapsed.frame = CGRectMake(p, timeY, inner / 2, timeHeight);
    _remaining.frame = CGRectMake(p + inner / 2, timeY, inner / 2, timeHeight);
    // Five slots across; with shuffle and repeat both left out, previous and next stand a third of the row from play.
    CGFloat slot = inner / 5, playX = p + inner / 2, rowY = transportY + kTransportRow / 2;
    CGFloat skip = _hideShuffle && _hideRepeat ? MAX(slot, MIN(inner / 3, inner / 2 - kTransportRow / 2)) : slot;
    _shuffle.center = CGPointMake(p + slot / 2, rowY);
    _previous.center = CGPointMake(playX - skip, rowY);
    _play.center = CGPointMake(playX, rowY);
    _next.center = CGPointMake(playX + skip, rowY);
    _repeat.center = CGPointMake(p + inner - slot / 2, rowY);

    // The words over the progress line, and the cover.
    CGFloat titleHeight = _titleHeight, artistHeight = _artistHeight;
    CGFloat chipHeight = _hideVideo ? 0 : _chipHeight, chipGap = _hideVideo ? 0 : 6;
    CGFloat textHeight = chipHeight + chipGap + titleHeight + artistHeight;
    CGFloat textBottom = lineY - 12;
    CGFloat chipWidth = _chipWidth;

    // Expanded: the words across under the cover, which is as large a square as fits between them and the header.
    // The words end before the ⋯, and before the star too while it stands in front of the ⋯.
    CGFloat trailing = kMoreSlot * (_starAdd ? 2 : 1) + 8;
    CGFloat textWidth = inner - trailing;
    CGRect bigArtist = CGRectMake(p, textBottom - artistHeight, textWidth, artistHeight);
    CGRect bigTitle = CGRectMake(p, CGRectGetMinY(bigArtist) - titleHeight, textWidth, titleHeight);
    CGRect bigChip = CGRectMake(p, CGRectGetMinY(bigTitle) - chipGap - chipHeight, MIN(chipWidth, textWidth), chipHeight);
    CGFloat coverTop = kCardTop + kHeaderRow + 12, coverBottom = CGRectGetMinY(bigChip) - 14;
    CGFloat bigSide = MAX(0, MIN(coverBottom - coverTop, inner));
    CGRect bigCover = CGRectMake(round((w - bigSide) / 2), coverTop + round((coverBottom - coverTop - bigSide) / 2), bigSide, bigSide);

    // Compact: the cover beside the words, the two centered on each other.
    CGFloat rowHeight = MAX(kCompactCover, textHeight), rowTop = textBottom - rowHeight;
    CGRect smallCover = CGRectMake(p, rowTop + round((rowHeight - kCompactCover) / 2), kCompactCover, kCompactCover);
    CGFloat textX = CGRectGetMaxX(smallCover) + 12, smallWidth = MAX(0, w - p - trailing - textX);
    CGFloat textTop = rowTop + round((rowHeight - textHeight) / 2);
    CGRect smallChip = CGRectMake(textX, textTop, MIN(chipWidth, smallWidth), chipHeight);
    CGRect smallTitle = CGRectMake(textX, textTop + chipHeight + chipGap, smallWidth, titleHeight);
    CGRect smallArtist = CGRectMake(textX, CGRectGetMaxY(smallTitle), smallWidth, artistHeight);

    // From expanded the cover first shrinks to the compact size above the words, at the leading edge; the words then
    // move to the side, and the cover comes down beside them. It never lies over them on the way.
    CGFloat wordsTop = MIN(CGRectGetMinY(_hideVideo ? bigTitle : bigChip), textTop);
    CGRect parked = CGRectMake(p, wordsTop - 12 - kCompactCover, kCompactCover, kCompactCover);
    CGFloat compactHeight = MAX(self.minimumHeight, kPreviewCompactHeight);
    CGFloat t = MIN(1, MAX(0, (h - compactHeight) / (kPreviewExpandedHeight - compactHeight))), words;
    if (t >= kCoverParkedAbove) {
        CGFloat shrink = (t - kCoverParkedAbove) / (1 - kCoverParkedAbove);
        _cover.frame = mixRect(parked, bigCover, shrink);
        _cover.layer.cornerRadius = mix(SGRRadiusThumb, SGRRadiusArtwork, shrink);
        words = 1;
    } else {
        _cover.frame = t >= kCoverParkedBelow ? parked : mixRect(smallCover, parked, t / kCoverParkedBelow);
        _cover.layer.cornerRadius = SGRRadiusThumb;
        words = t >= kCoverParkedBelow ? (t - kCoverParkedBelow) / (kCoverParkedAbove - kCoverParkedBelow) : 0;
    }
    _chip.frame = mixRect(smallChip, bigChip, words);
    _chip.layer.cornerRadius = chipHeight / 2;
    _chipGlyph.center = CGPointMake(8 + _chipGlyph.bounds.size.width / 2, chipHeight / 2);
    CGFloat labelX = CGRectGetMaxX(_chipGlyph.frame) + 4;
    _chipLabel.frame = CGRectMake(labelX, 0, MAX(0, _chip.bounds.size.width - labelX - 8), chipHeight);
    _title.frame = mixRect(smallTitle, bigTitle, words);
    _artist.frame = mixRect(smallArtist, bigArtist, words);
    _more.center = CGPointMake(w - p - kMoreSlot / 2, round((CGRectGetMinY(_title.frame) + CGRectGetMaxY(_artist.frame)) / 2));
    _star.center = CGPointMake(_more.center.x - kMoreSlot, _more.center.y);
}

- (CGFloat)minimumHeight {
    [self readFonts];
    CGFloat titleHeight = _titleHeight, artistHeight = _artistHeight;
    CGFloat chip = _hideVideo ? 0 : _chipHeight + 6;
    CGFloat row = MAX(kCompactCover, chip + titleHeight + artistHeight);
    return kCardTop + kHeaderRow + 8 + row + 12 + kProgressLine + 4 + _timeHeight + 4 + kTransportRow + kCardBottom;
}

@end

#pragma mark - the Buttons chips

// The chips' row; the page draws it as the chips (SGRPlayerPage).
@interface SGRPlayerButtonsRow : SGModRow
@end
@implementation SGRPlayerButtonsRow
@end

// The chips in order, each selected while the player shows its button: while its hide key is off.
static NSArray<NSString *> *buttonKeys(void) {
    return @[SGRKeyPlayerHideShuffle, SGRKeyPlayerHideRepeat, SGKeyHideVideoSwitch];
}

static NSArray<NSString *> *buttonNames(void) {
    return @[SGL(@"settings.player.hide.shuffle.title", @"Shuffle"), SGL(@"settings.player.hide.repeat.title", @"Repeat"),
             SGL(@"settings.player.buttons.video", @"Video")];
}

@interface SGRPlayerButtonsCell : UITableViewCell
// After a chip stored its key.
@property (nonatomic, copy) void (^changed)(void);
- (void)readKeys;
@end

@implementation SGRPlayerButtonsCell {
    NSArray<UIButton *> *_chips;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (!(self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    NSMutableArray<UIButton *> *chips = [NSMutableArray array];
    [buttonNames() enumerateObjectsUsingBlock:^(NSString *name, NSUInteger i, BOOL *stop) {
        UIButton *chip = [UIButton buttonWithType:UIButtonTypeCustom];
        chip.tag = (NSInteger)i;
        chip.accessibilityLabel = name;
        [chip addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:chip];
        [chips addObject:chip];
    }];
    _chips = chips;
    [self readKeys];
    return self;
}

- (void)readKeys {
    NSArray<NSString *> *keys = buttonKeys();
    for (UIButton *chip in _chips) {
        NSString *key = keys[(NSUInteger)chip.tag];
        [self paint:chip selected:!([key isEqual:SGKeyHideVideoSwitch] ? SGVideoSwitchHiddenForLook(YES) : SGHidden(key))];
    }
    [self setNeedsLayout];
}

// Selected: the accent's fill and a check; not: the card's gray and the button crossed out.
- (void)paint:(UIButton *)chip selected:(BOOL)selected {
    __block UIFont *font;
    [self.traitCollection performAsCurrentTraitCollection:^{ font = SGTitleFont(); }];
    UIButtonConfiguration *look = selected ? [UIButtonConfiguration filledButtonConfiguration] : [UIButtonConfiguration grayButtonConfiguration];
    look.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    look.baseBackgroundColor = selected ? SGGreen() : [UIColor colorWithWhite:1 alpha:0.12];
    look.baseForegroundColor = selected ? SGOnAccent() : SGGrey();
    look.image = [UIImage systemImageNamed:selected ? @"checkmark" : @"eye.slash"
                         withConfiguration:[UIImageSymbolConfiguration configurationWithFont:font scale:UIImageSymbolScaleSmall]];
    look.imagePadding = 6;
    look.contentInsets = NSDirectionalEdgeInsetsMake(8, 14, 8, 14);
    look.attributedTitle = [[NSAttributedString alloc] initWithString:buttonNames()[(NSUInteger)chip.tag] attributes:@{NSFontAttributeName: font}];
    chip.configuration = look;
    chip.selected = selected;
    chip.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
}

- (void)chipTapped:(UIButton *)chip {
    BOOL shown = !chip.selected;
    SGSetEnabled(buttonKeys()[(NSUInteger)chip.tag], !shown);
    [[UISelectionFeedbackGenerator new] selectionChanged];
    [UIView transitionWithView:self.contentView duration:kChipTransition options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        [self paint:chip selected:shown];
        [self setNeedsLayout];
        [self layoutIfNeeded];
    } completion:nil];
    if (self.changed) self.changed();
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    [self readKeys];
}

// The chips side by side from the leading margin, the next on a new line once one would pass the trailing margin, so
// they stack where the text is large or the card narrow. Laid out at `width`; the height they take.
- (CGFloat)placeChipsInWidth:(CGFloat)width {
    UIEdgeInsets margins = self.contentView.layoutMargins;
    CGFloat left = margins.left, right = width - margins.right, x = left, y = kChipGap, line = 0;
    BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    for (UIButton *chip in _chips) {
        CGSize size = [chip sizeThatFits:CGSizeMake(right - left, CGFLOAT_MAX)];
        size = CGSizeMake(MIN(right - left, ceil(size.width)), MAX(kChipHeight, ceil(size.height)));
        if (x > left && x + size.width > right) {
            x = left;
            y += line + kChipGap;
            line = 0;
        }
        CGRect frame = CGRectMake(x, y, size.width, size.height);
        if (rtl) frame.origin.x = width - CGRectGetMaxX(frame);
        chip.frame = frame;
        x += size.width + kChipGap;
        line = MAX(line, size.height);
    }
    return y + line + kChipGap;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self placeChipsInWidth:self.contentView.bounds.size.width];
}

- (CGSize)systemLayoutSizeFittingSize:(CGSize)target withHorizontalFittingPriority:(UILayoutPriority)horizontal verticalFittingPriority:(UILayoutPriority)vertical {
    return CGSizeMake(target.width, [self placeChipsInWidth:target.width]);
}

@end

SGModSection *SGRPlayerButtonsSection(void) {
    SGRPlayerButtonsRow *row = [SGRPlayerButtonsRow new];
    row.title = SGL(@"settings.player.buttons.header", @"Buttons");
    row.searchIdentifier = @"spotifyglass.redesign.player.buttons";
    SGSearchKeywords(row, [buttonNames() componentsJoinedByString:@" "]);
    return SGNotedSection(row.title, @[row], SGL(@"settings.player.buttons.footer", @"The player shows the selected buttons. Applies after you restart Spotify."));
}

#pragma mark - the page

// SGModPage's row at a path of its table, as shown now.
@interface SGModPage (SGRPlayerRows)
- (SGModRow *)rowAt:(NSIndexPath *)path;
@end

@interface SGRPlayerPage : SGModPage
@property (nonatomic, strong) SGRPlayerPreview *preview;
@property (nonatomic, strong) UISegmentedControl *backgrounds;
- (void)backgroundChanged;
- (void)noClipPicked;
@end

@implementation SGRPlayerPage {
    UIView *_pinned;   // the card's place over the rows, in the page's color around it
    UIView *_header;   // the table's header: the room the card takes expanded, the segments and the note
    UILabel *_note;
    CGFloat _compact, _expanded;   // the card's heights
    CGFloat _headerWidth, _headerExtra;
    UIContentSizeCategory _headerCategory;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _pinned = [UIView new];
    _pinned.backgroundColor = self.tableView.backgroundColor;   // the rows scroll under it
    [_pinned addSubview:self.preview];
    [self.tableView addSubview:_pinned];
    _header = [UIView new];
    [_header addSubview:self.backgrounds];
    _note = [UILabel new];
    _note.font = SGSubtitleFont();
    _note.textColor = SGGrey();
    _note.numberOfLines = 0;
    [_header addSubview:_note];
    [self showNote];
    self.tableView.tableHeaderView = _header;
}

- (void)showNote {
    _note.text = backgroundNotes()[(NSUInteger)SGRPlayerBackground()];
    _headerWidth = 0;
    [self.view setNeedsLayout];
}

// The card's two heights for the room between the bars. The table's header keeps the height it is given, so it is
// sized here and given back to the table only when that changes (a table header set on every pass lays the table out
// again forever): the room the card takes beyond compact, then the segments and the note, whose room is that of the
// longest note at this width, so picking a background never moves the rows.
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    UITableView *table = self.tableView;
    CGFloat width = table.bounds.size.width, inset = table.layoutMargins.left;
    CGFloat cardWidth = width - 2 * inset;
    CGFloat room = table.bounds.size.height - table.safeAreaInsets.top - table.safeAreaInsets.bottom - table.contentInset.bottom;
    _compact = MAX(self.preview.minimumHeight, MIN(kPreviewCompactHeight, floor(room * kPreviewCompactShare) - 2 * kPinnedGap));
    _expanded = MAX(_compact, MIN(kPreviewExpandedHeight, floor(room * kPreviewExpandedShare) - 2 * kPinnedGap));

    // Scrolling invokes this every frame. Only a size, type or note change needs fonts and text measurement.
    CGFloat extra = _expanded - _compact;
    UIContentSizeCategory category = self.traitCollection.preferredContentSizeCategory;
    if (_headerWidth == width && _headerExtra == extra && [_headerCategory isEqualToString:category]) return;
    _headerWidth = width;
    _headerExtra = extra;
    _headerCategory = category;
    _note.font = SGSubtitleFont();
    CGFloat controlHeight = MAX(32, ceil([self.backgrounds sizeThatFits:CGSizeMake(cardWidth, CGFLOAT_MAX)].height));
    self.backgrounds.frame = CGRectMake(inset, _expanded - _compact + 4, cardWidth, controlHeight);
    CGFloat noteWidth = cardWidth - 2 * 4, noteRoom = 0;
    UILabel *measure = [UILabel new];
    measure.font = _note.font;
    measure.numberOfLines = 0;
    for (NSString *text in backgroundNotes()) {
        measure.text = text;
        noteRoom = MAX(noteRoom, ceil([measure sizeThatFits:CGSizeMake(noteWidth, CGFLOAT_MAX)].height));
    }
    CGFloat noteHeight = ceil([_note sizeThatFits:CGSizeMake(noteWidth, CGFLOAT_MAX)].height);
    CGFloat noteTop = CGRectGetMaxY(self.backgrounds.frame) + 8;
    _note.frame = CGRectMake(inset + 4, noteTop, noteWidth, noteHeight);
    CGSize size = CGSizeMake(width, noteTop + noteRoom);
    if (CGSizeEqualToSize(_header.bounds.size, size)) return;
    _header.frame = (CGRect){CGPointZero, size};
    table.tableHeaderView = _header;
}

// Pinned at compact height over the rows (SGPositionPinnedPreview), and taller by however much of the header's room
// beyond compact is still in sight, so the card shrinks as the rows scroll up and they then scroll under it. Scrolling
// lays the table out again, so this runs on every frame of it.
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UITableView *table = self.tableView;
    if (_expanded <= 0) return;
    SGPositionPinnedPreview(table, _pinned, _compact + 2 * kPinnedGap);
    CGFloat scrolled = table.contentOffset.y + table.adjustedContentInset.top, more = _expanded - _compact;
    CGFloat extra = MAX(0, MIN(more, more - scrolled));
    CGRect frame = _pinned.frame;
    // Cover the table under the translucent navigation/status bars too, not just the card's band.
    // The card stays at the same window position; rows and their touches stay below this opaque pane.
    CGFloat topCoverHeight = CGRectGetMinY(frame) - CGRectGetMinY(table.bounds);
    frame.origin.y -= topCoverHeight;
    frame.size.height += topCoverHeight + extra;
    _pinned.frame = frame;
    CGFloat inset = table.layoutMargins.left;
    CGRect card = CGRectMake(inset, topCoverHeight + kPinnedGap, frame.size.width - 2 * inset, _compact + extra);
    if (!CGRectEqualToRect(self.preview.frame, card)) self.preview.frame = card;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // The player's ⋯ menu can switch Animated and Fluid while the page is away.
    self.backgrounds.selectedSegmentIndex = segmentOf(SGRPlayerBackground());
    [self showNote];
    [self.preview setActive:YES];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.preview setActive:NO];
}

- (void)backgroundPicked {
    SGRSetPlayerBackground(self.backgrounds.selectedSegmentIndex);
    SGSetInt(SGRKeyPlayerArtworkBackground, self.backgrounds.selectedSegmentIndex);
    [self backgroundChanged];
}

// The card, the segments, the note and the rows that follow the choice, after it changed here or in a row.
- (void)backgroundChanged {
    SGRPlayerBackgroundDidChange();
    self.backgrounds.selectedSegmentIndex = segmentOf(SGRPlayerBackground());
    [self.preview reloadBackgroundAnimated:YES];
    [self showNote];
    [self refreshVisibility];
    [self.tableView reloadData];
}

// A choice of Song without a clip is shown on the card at once.
- (void)noClipPicked {
    [self.preview setDemo:YES];
    [self refreshVisibility];
    [self.tableView reloadData];
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    if (![[self rowAt:path] isKindOfClass:SGRPlayerButtonsRow.class]) return [super tableView:table cellForRowAtIndexPath:path];
    SGRPlayerButtonsCell *cell = [table dequeueReusableCellWithIdentifier:@"buttons"]
        ?: [[SGRPlayerButtonsCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"buttons"];
    cell.backgroundColor = SGCardBackground();
    __weak SGRPlayerPage *weakSelf = self;
    cell.changed = ^{ [weakSelf.preview reloadLook]; };
    [cell readKeys];
    return cell;
}

- (BOOL)tableView:(UITableView *)table shouldHighlightRowAtIndexPath:(NSIndexPath *)path {
    return ![[self rowAt:path] isKindOfClass:SGRPlayerButtonsRow.class];
}

@end

#pragma mark - switches the open player follows

static NSHashTable<UIView *> *sg_lookViews;

void SGRPlayerWatchLook(UIView *unitView) {
    if (!unitView) return;
    if (!sg_lookViews) sg_lookViews = [NSHashTable weakObjectsHashTable];
    [sg_lookViews addObject:unitView];
}

void SGRPlayerLookChanged(void) {
    for (UIView *view in sg_lookViews.allObjects) [view setNeedsLayout];
}

// One of Fluid's settings on a slider, written out with `unit` after the number.
static SGModRow *fluidSlider(NSString *title, SGRFluidSetting setting, NSString *unit) {
    SGRFluidLimits l = SGRFluidLimitsOf(setting);
    return SGSliderRow(title, nil, l.least, l.most, l.step, ^double { return SGRFluidValue(setting); },
                       ^(double value) { SGRSetFluidValue(setting, lround(value)); },
                       ^NSString *(double value) { return [NSString stringWithFormat:@"%.0f%@", value, unit]; });
}

SGModRow *SGRVisualiserStyleRow(void) {
    return SGMenuRow(SGL(@"settings.player.visualizer_style.title", @"Visualizer style"), SGRVisualiserStyleNames(), ^NSString *{
        return SGRVisualiserStyleNames()[[SGRVisualiserStyleIDs() indexOfObject:SGRVisualiserStyle()]];
    }, ^(NSInteger index) {
        NSArray<NSString *> *identifiers = SGRVisualiserStyleIDs();
        if (index >= 0 && (NSUInteger)index < identifiers.count) SGRPickVisualiserStyle(identifiers[(NSUInteger)index]);
    });
}

// A Poster or Cut parameter's rows (PlayerLyricStages.m), shown only while that style is chosen. The switches keep
// their value in the parameters' dictionary, so the search remembers them by the entry they store.
static SGModRow *visualiserSwitch(NSString *title, NSString *style, NSString *param) {
    SGModRow *row = SGBlockSwitchRow(title, nil, ^BOOL { return SGRVisualiserParam(style, param) != 0; },
                                     ^(BOOL on) { SGRSetVisualiserParam(style, param, on); });
    row.searchIdentifier = [NSString stringWithFormat:@"%@.%@.%@", SGRKeyVisualiserParams, style, param];
    row.visible = ^BOOL { return [SGRVisualiserStyle() isEqualToString:style]; };
    return row;
}

static SGModRow *visualiserSlider(NSString *title, NSString *style, NSString *param) {
    SGRVisualiserParamLimits l = SGRVisualiserParamLimitsOf(style, param);
    SGModRow *row = SGSliderRow(title, nil, l.least, l.most, l.step, ^double { return SGRVisualiserParam(style, param); },
                                ^(double value) { SGRSetVisualiserParam(style, param, value); },
                                ^NSString *(double value) { return [NSString stringWithFormat:@"%.0f%%", value * 100]; });
    row.visible = ^BOOL { return [SGRVisualiserStyle() isEqualToString:style]; };
    return row;
}

static SGModRow *visualiserColour(NSString *title, NSString *style, NSString *param) {
    SGModRow *row = SGStatActionRow(title, nil, ^NSString *{
        return [NSString stringWithFormat:@"#%06lX", lround(SGRVisualiserParam(style, param))];
    }, ^{
        SGPickColor(title, lround(SGRVisualiserParam(style, param)), ^(NSInteger rgb) { SGRSetVisualiserParam(style, param, rgb); });
    });
    row.swatch = ^UIColor *{ return SGColorRGB(lround(SGRVisualiserParam(style, param))); };
    row.visible = ^BOOL { return [SGRVisualiserStyle() isEqualToString:style]; };
    return row;
}

UIViewController *SGRVisualiserSettingsPage(void) {
    NSString *ink = SGL(@"settings.visualizer.ink.title", @"Type color");
    NSArray<SGModRow *> *poster = @[
        visualiserSwitch(SGL(@"settings.visualizer.halftone.title", @"Halftone"), SGRVisualiserPosterID, SGRVisualiserHalftone),
        visualiserColour(ink, SGRVisualiserPosterID, SGRVisualiserInk),
        visualiserSlider(SGL(@"settings.visualizer.backdrop.title", @"Print strength"), SGRVisualiserPosterID, SGRVisualiserBackdrop),
        visualiserSlider(SGL(@"settings.visualizer.ghost.title", @"Words ahead"), SGRVisualiserPosterID, SGRVisualiserGhost)];
    NSArray<SGModRow *> *cut = @[
        visualiserColour(ink, SGRVisualiserCutID, SGRVisualiserInk),
        visualiserSlider(SGL(@"settings.visualizer.shade.title", @"Background"), SGRVisualiserCutID, SGRVisualiserShade),
        visualiserSlider(SGL(@"settings.visualizer.motion.title", @"Motion"), SGRVisualiserCutID, SGRVisualiserMotion),
        visualiserSwitch(SGL(@"settings.visualizer.subtitle.title", @"Whole line"), SGRVisualiserCutID, SGRVisualiserSubtitle)];
    // Picking a style brings its rows in and takes the last one's away.
    __block __weak SGModPage *weakPage;
    SGModRow *style = SGRVisualiserStyleRow();
    void (^pick)(NSInteger) = style.chosen;
    style.chosen = ^(NSInteger index) {
        pick(index);
        [weakPage refreshVisibility];
    };
    SGModRow *shuffle = SGOptionRow(SGL(@"settings.player.visualizer_shuffle.title", @"Shuffle styles"),
                                    SGL(@"settings.player.visualizer_shuffle.subtitle", @"A different style with each song"), SGRKeyVisualiserShuffle);
    shuffle.changed = ^(BOOL on) { SGRVisualiserShuffleChanged(); };
    SGModRow *heat = SGOptionRow(SGL(@"settings.player.visualizer_heat.title", @"Ignore heat warnings"),
                                 SGL(@"settings.player.visualizer_heat.subtitle", @"Keeps the Visualizer moving while the iPhone is hot. Uses more battery."),
                                 SGRKeyVisualiserIgnoreHeat);
    heat.changed = ^(BOOL on) { SGRVisualiserIgnoreHeatChanged(); };
    SGModPage *page = [[SGModPage alloc] initWithTitle:SGL(@"settings.player.visualizers.title", @"Visualizers") intro:SGL(@"settings.player.visualizers.intro", @"Local styles for the redesigned player's Visualizer background.")
        sections:@[SGNotedSection(nil, @[style, shuffle],
            SGL(@"settings.player.visualizers.note", @"Hills: soft spectrum hills. Bars: a mirrored spectrum with the actual audio waveform. "
             @"Nebula: slow clouds in the cover's colors. Halo: a dim turning cover with a spectrum ring. Lyrics: the sung line, large, "
             @"over quieter hills. Poster: the line filled in word by word as a type poster over a print of the cover. Cut: one word "
             @"at a time over the cover, cut to the singing. The last three need synced lyrics.")),
                   SGNotedSection(SGL(@"settings.visualizer.style.choice.poster", @"Poster"), poster,
                                  SGL(@"settings.visualizer.poster.note", @"The sung line set word by word as a type poster over a print of the cover. Needs synced lyrics.")),
                   SGNotedSection(SGL(@"settings.visualizer.style.choice.cut", @"Cut"), cut,
                                  SGL(@"settings.visualizer.cut.note", @"One word at a time over the cover, cut to the singing. Needs synced lyrics.")),
                   SGSection(nil, @[heat])]
        footer:SGL(@"settings.player.visualizers.footer", @"The style changes immediately in existing player and preview visualizers. To show it, choose Visualizer "
                @"under Player > Background. This page leaves the background choice unchanged. Motion rests on pause or silence "
                @"and stops in the background, during player transitions, in Low Power Mode or when the device is hot.")];
    weakPage = page;
    return page;
}

SGModRow *SGRLyricsHideRow(void) {
    SGModRow *row = SGChoiceRow(SGL(@"settings.lyrics.hide_controls.title", @"Hide the controls"), SGL(@"settings.lyrics.hide_controls.room", @"A few seconds after the last touch, the lyrics take the room"),
                                SGRKeyLyricsAutoHide, @[SGL(@"common.off", @"Off"), SGL(@"settings.lyrics.hide_controls.all", @"Everything"), SGL(@"settings.lyrics.hide_controls.keep_title", @"Keep the title")], SGRLyricsHideMode());
    row.choiceNotes = @[SGL(@"settings.lyrics.hide_controls.off_note", @"The controls stay"), SGL(@"settings.lyrics.hide_controls.all_note", @"The lyrics take the whole player"), SGL(@"settings.lyrics.hide_controls.title_note", @"The cover, the title and the top row stay; in landscape, the title")];
    return row;
}

SGModRow *SGRLyricsKeepMicRow(void) {
    SGModRow *row = SGSwitchRow(SGL(@"settings.lyrics.keep_mic.title", @"Keep the mic"),
                                SGL(@"settings.lyrics.keep_mic.subtitle", @"Sing's mic stays when the controls are hidden. Off, it hides with them, as in Apple Music, and stays only while Sing is on."),
                                SGRKeyLyricsKeepMic);
    row.visible = ^BOOL { return SGRLyricsHideMode() != SGRLyricsHideOff; };
    return row;
}

UIViewController *SGRPlayerSettingsPage(NSArray *more) {
    NSArray *lineSizes = @[SGL(@"settings.player.lyric_line.size_19", @"19 pt"), SGL(@"settings.player.lyric_line.size_17", @"17 pt")];
    SGRPlayerPreview *preview = [[SGRPlayerPreview alloc] initWithFrame:CGRectMake(0, 0, 320, kPreviewCompactHeight)];
    __block __weak SGRPlayerPage *weakPlayerPage;
    UISegmentedControl *backgrounds = [[UISegmentedControl alloc] initWithItems:SGRPlayerBackgroundNames()];
    backgrounds.selectedSegmentIndex = segmentOf(SGRPlayerBackground());
    backgrounds.accessibilityLabel = SGL(@"settings.player.background.a11y", @"Background");
    backgrounds.apportionsSegmentWidthsByContent = YES;

    // What a song with no clip shows under Animated, also shown on the card when picked.
    SGModRow *noClip = SGMenuRow(SGL(@"settings.player.no_clip.title", @"Song without a clip"), noClipNames(), ^NSString *{
        return noClipNames()[noClipStored()];
    }, ^(NSInteger index) {
        if (index < SGRNoClipStill || index > SGRNoClipVisualiser) return;
        pickNoClip(index);
        SGRPlayerHoldField();
        [weakPlayerPage noClipPicked];
    });
    noClip.visible = ^BOOL { return SGRPlayerBackground() == SGRPlayerBackgroundAnimated; };
    noClip.searchIdentifier = @"spotifyglass.redesign.player.noClip";
    SGModRow *holdNoClip = SGOptionRow(SGL(@"settings.player.no_clip.hold", @"Keep background still"), nil, SGRKeyPlayerHoldNoClip);
    holdNoClip.visible = ^BOOL {
        SGRNoClip choice = noClipStored();
        return SGRPlayerBackground() == SGRPlayerBackgroundAnimated && (choice == SGRNoClipColours || choice == SGRNoClipFluid);
    };
    holdNoClip.changed = ^(BOOL on) {
        SGRPlayerHoldField();
        [weakPlayerPage.preview holdField];
    };
    SGModRow *visualiserStyle = SGRVisualiserStyleRow();
    visualiserStyle.visible = ^BOOL { return SGRPlayerBackground() == SGRPlayerBackgroundVisualiser; };
    SGModRow *visualizers = SGSearchIdentified(SGPageRow(SGL(@"settings.player.visualizers.title", @"Visualizers"),
        ^UIViewController *{ return SGRVisualiserSettingsPage(); }), @"page.visualizers");
    visualizers.visible = visualiserStyle.visible;

    // Black or a photo in place of the artwork; the photo is asked for the first time it is chosen.
    SGModRow *behind = SGMenuRow(SGL(@"settings.player.behind.title", @"Behind the Player"), behindNames(), ^NSString *{
        SGRPlayerBackgroundKind kind = SGRPlayerBackground();
        return behindNames()[kind == SGRPlayerBackgroundBlack ? 1 : kind == SGRPlayerBackgroundPhoto ? 2 : 0];
    }, ^(NSInteger index) {
        SGRPlayerPage *page = weakPlayerPage;
        if (index == 2) {
            // Reserve this choice while the saved photo is prepared or the picker imports one, without
            // replacing the current look. Every later page/menu choice supersedes its automatic switch.
            NSUInteger choice = SGRSetPlayerBackground(SGRPlayerBackground());
            SGRPlayerLoadPhoto(^(BOOL available) {
                if (choice != SGRPlayerBackgroundGeneration()) return;
                void (^usePhoto)(BOOL) = ^(BOOL stored) {
                    if (!stored || choice != SGRPlayerBackgroundGeneration()) return;
                    SGRSetPlayerBackground(SGRPlayerBackgroundPhoto);
                    [page backgroundChanged];
                };
                if (available) usePhoto(YES);
                else SGRPlayerPickPhoto(page, usePhoto);
            });
            return;
        }
        SGRSetPlayerBackground(index == 1 ? SGRPlayerBackgroundBlack : SGRPlayerArtworkBackground());
        [page backgroundChanged];
    });
    SGModRow *choosePhoto = SGActionRow(SGL(@"settings.player.photo.choose", @"Choose Photo"), nil, ^{
        SGRPlayerPage *page = weakPlayerPage;
        SGRPlayerPickPhoto(page, ^(BOOL stored) { if (stored) [page backgroundChanged]; });
    });
    choosePhoto.visible = ^BOOL { return SGRPlayerBackground() == SGRPlayerBackgroundPhoto; };

    __block __weak UITableViewController *weakPage;
    SGModRow *reset = SGActionRow(SGL(@"common.reset", @"Reset"), nil, ^{
        SGRResetFluidSettings();
        [weakPage.tableView reloadData];   // the sliders at once, rather than at the page's next tick
    });
    reset.color = SGRed();
    // Light or Smooth, the way Fluid is drawn (SGRFluid.h); the card and the player change at once.
    SGModRow *renderer = SGMenuRow(SGL(@"settings.player.fluid.renderer.title", @"Style"), SGRFluidRendererNames(), ^NSString *{
        return SGRFluidRendererNames()[SGRFluidRendererChosen()];
    }, ^(NSInteger index) {
        SGRSetFluidRenderer(index == SGRFluidRendererSmooth ? SGRFluidRendererSmooth : SGRFluidRendererLight);
        [weakPlayerPage refreshVisibility];   // Grain comes and goes with Smooth
    });
    // Grain is Smooth's alone (SGRFluid.h), so it shows only while Smooth draws.
    SGModRow *grain = fluidSlider(SGL(@"settings.player.fluid.grain", @"Grain"), SGRFluidGrain, @"%");
    NSArray<SGModRow *> *fluid = @[
        renderer, fluidSlider(SGL(@"settings.player.fluid.speed", @"Speed"), SGRFluidSpeed, @"%"), fluidSlider(SGL(@"settings.player.fluid.warp", @"Warp"), SGRFluidWarp, @"%"), fluidSlider(SGL(@"settings.player.fluid.blur", @"Blur"), SGRFluidBlur, @""),
        fluidSlider(SGL(@"settings.player.fluid.saturation", @"Saturation"), SGRFluidSaturation, @"%"), fluidSlider(SGL(@"settings.player.fluid.brightness", @"Brightness"), SGRFluidBrightness, @"%"), grain, reset,
    ];
    for (SGModRow *row in fluid) row.visible = ^BOOL { return SGRPlayerBackground() == SGRPlayerBackgroundFluid; };
    renderer.visible = ^BOOL { return SGRPlayerBackground() == SGRPlayerBackgroundFluid && SGRFluidGPUAvailable(); };
    grain.visible = ^BOOL {
        return SGRPlayerBackground() == SGRPlayerBackgroundFluid && SGRFluidGPUAvailable() && SGRFluidRendererChosen() == SGRFluidRendererSmooth;
    };
    // The header's glass and the footer's glyphs, followed by the open player at once.
    SGModRow *headerGlass = SGWithNew(SGSwitchRow(SGL(@"settings.player.header_glass.title", @"Header glass"),
                                                  SGL(@"settings.player.header_glass.subtitle", @"Glass circles behind the close and ⋯ buttons at the top of the AI DJ's player. The player itself has only a grabber there."),
                                                  SGRKeyPlayerHeaderGlass), @"playerHeaderGlass");
    SGModRow *musicIcons = SGWithNew(SGSwitchRow(SGL(@"settings.player.music_icons.title", @"Music app icons"),
                                                 SGL(@"settings.player.music_icons.subtitle", @"The Music app's lyrics, AirPlay and queue icons under the controls, and the AI DJ's button as a waveform, in place of Spotify's."),
                                                 SGRKeyPlayerMusicIcons), @"playerMusicIcons");
    musicIcons.changed = ^(BOOL on) { SGRPlayerLookChanged(); };
    // Where the footer's queue button shows the queue: Spotify's own screen, or the Music app's page in the player
    // (PlayerQueue.m, PlayerLyrics.x). Both choices keep the two-column player's side list.
    SGModRow *queueStyle = SGWithNew(SGChoiceRow(SGL(@"settings.player.queue_style.title", @"Queue"),
                                                 SGL(@"settings.player.queue_style.subtitle", @"Choose how the queue opens after restart. The two-column iPad player always shows it in the side column."),
                                                 SGRKeyPlayerQueueStyle,
                                                 @[SGL(@"settings.player.queue_style.spotify", @"Spotify"), SGL(@"settings.player.queue_style.music", @"Apple Music")],
                                                 SGRPlayerQueueStyleSpotify), @"playerQueueStyle");
    queueStyle.choiceNotes = @[SGL(@"settings.player.queue_style.spotify_note", @"Spotify's own queue screen opens over the player, where songs can be reordered and removed."),
                               SGL(@"settings.player.queue_style.music_note", @"The queue opens inside the player under a small cover, with shuffle, repeat, sleep timer and AutoMix above it, as in Apple Music. Drag a song's grip to move it. Tap the button again to bring the cover back. AutoMix controls global transitions; per-playlist Mix stays in the playlist's ⋯ menu.")];
    // On until switched off, as the Music app's header has only the grabber over the cover.
    SGModRow *hideContext = SGShownRow(SGL(@"settings.player.hide_context.title", @"Where it plays from"),
                                      SGL(@"settings.player.hide_context.subtitle", @"The artist, album or playlist name at the top of the player."),
                                      SGRKeyPlayerHideContext);
    hideContext.defaultOn = YES; // the stored *hide* switch defaults on
    hideContext.changed = ^(BOOL on) {
        SGRPlayerLookChanged();
        [weakPlayerPage.preview reloadLook];
    };
    // The card draws the header's glass and the add button too.
    headerGlass.changed = ^(BOOL on) {
        SGRPlayerLookChanged();
        [weakPlayerPage.preview reloadLook];
    };
    SGModRow *starAdd = SGWithNew(SGOptionRow(SGL(@"settings.player.star_add.title", @"Star add button"),
                                              SGL(@"settings.player.star_add.subtitle", @"The player's add button as a star beside the song title, next to the ⋯: outlined until the song is saved, filled in the accent once it is. The ⋯ menu then leaves out its add item."),
                                              SGRKeyPlayerStarAdd), @"playerStarAdd");
    starAdd.changed = ^(BOOL on) { [weakPlayerPage.preview reloadLook]; };
    // iPad turns Spotify's own player.
    SGModRow *landscape = SGWithNew(SGOptionRow(SGL(@"settings.player.landscape.title", @"Landscape player"),
                                                SGL(@"settings.player.landscape.subtitle", @"Turn your iPhone while the player is open, even with the lyrics closed."),
                                                SGRKeyPlayerLandscape), @"playerLandscape");
    landscape.visible = ^BOOL { return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone; };
    SGModRow *size = SGMenuRow(SGL(@"settings.player.lyric_line.size", @"Lyrics line size"), lineSizes,
        ^NSString *{ return lineSizes[SGRPlayerLineSmall() ? 1 : 0]; }, ^(NSInteger i) { SGRSetPlayerLineSmall(i == 1); });
    size.waitsOn = SGRKeyPlayerLyricLine;

    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithObjects:
        SGSection(nil, @[behind, choosePhoto]),
        SGNotedSection(nil, @[noClip, holdNoClip],
                       SGL(@"settings.player.no_clip.footer", @"Full-screen cover fills the screen with the album cover. In Low Power Mode or with Reduce Motion, the artwork background stays still.")),
        SGSection(nil, @[visualiserStyle, visualizers]),
        SGNotedSection(nil, fluid, SGL(@"settings.player.fluid.footer", @"Smooth lets the cover flow and carries the next song's cover in through it, "
                                   @"using a little more battery. Brightness above 100% can make white text harder to read. A paused song holds the "
                                   @"background still. Animated and Visualizer use these where they show Fluid.")),
        SGNotedSection(SGL(@"settings.player.controls.header", @"Controls"), @[headerGlass, hideContext, SGSwitchRow(SGL(@"settings.player.volume.title", @"Volume"), nil, SGRKeyPlayerVolume),
                                      SGOptionRow(SGL(@"settings.player.follows_cover.title", @"Follow the cover"), nil, SGRKeyPlayerFollowsCover),
                                      SGWithNew(SGOptionRow(SGL(@"settings.player.lyric_line.title", @"Lyrics Line"),
                                                  SGL(@"settings.player.lyric_line.subtitle", @"The line being sung, under the cover. Tap it to open the lyrics."),
                                                  SGRKeyPlayerLyricLine), @"playerLyricLine"),
                                      size, SGSimplifyTitlesRow(),
                                      SGWithNew(SGSwitchRow(SGL(@"settings.player.rolling_digits.title", @"Rolling time digits"),
                                                  SGL(@"settings.player.rolling_digits.subtitle", @"The digits that change under the progress bar roll into place."),
                                                  SGRKeyPlayerRollingDigits), @"playerRollingDigits"),
                                      starAdd, musicIcons, queueStyle,
                                      SGSwitchRow(SGL(@"settings.player.queue_history.title", @"Show recently played songs in queue"), nil, SGRKeyPlayerQueueHistory),
                                      landscape,
                                      SGOptionRow(SGL(@"settings.player.music_close.title", @"Music-like player close"),
                                                  SGL(@"settings.player.music_close.subtitle", @"Close into the mini player in stages. Applies after restarting Spotify."),
                                                  SGRKeyPlayerMusicClose)],
                       SGL(@"settings.player.controls.footer", @"Volume puts a slider under the controls for this iPhone, or the speaker's while Spotify plays on another device. "
                       @"Follow the cover paints the like, shuffle and repeat in the color of the song playing. Restart Spotify to apply all control changes.")),
        SGNotedSection(SGL(@"settings.player.mini_player.header", @"Mini player"), SGRNowPlayingBarRows(),
                       SGL(@"settings.player.mini_player.footer", @"Apple Music style moves the mini player between two tabs as you scroll down.")), nil];
    [sections addObjectsFromArray:more];
    // Fluid, Animated and Visualizer share the field (PlayerMotion.x reads the choice on every track, PlayerVisualiser.m
    // on the field's layout); Still and Colors are a field of another kind, made once a launch (PlayerField.x). The
    // Buttons chips say their own restart.
    NSString *footer = SGL(@"settings.player.footer.v2", @"Fluid, Animated and Visualizer change with the next song. Still and Colors apply after you restart Spotify.");
    SGRPlayerPage *page = [[SGRPlayerPage alloc] initWithTitle:SGL(@"settings.player.title", @"Player") intro:nil sections:sections footer:footer];
    weakPage = page;
    weakPlayerPage = page;
    page.preview = preview;
    page.backgrounds = backgrounds;
    [backgrounds addTarget:page action:@selector(backgroundPicked) forControlEvents:UIControlEventValueChanged];
    return page;
}
