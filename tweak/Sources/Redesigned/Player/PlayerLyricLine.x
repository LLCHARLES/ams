// Player redesign: the line of the lyrics being sung, one line in the gap under the cover and over the title,
// while the lyrics are not open in the player and the track has synced lines. It is the one line a place with
// room for one shows (SGKaraokeLeadLine, as the lock screen's), at the player's position less the Lyrics page's
// Delay, the way the lyrics view reads it (SGRKaraokeView's positionMs). A tap on it opens the lyrics, as the
// footer's lyrics glyph does (SGRPlayerToggleLyrics).
//
// It is a view of the mod's in SPTNowPlayingView (NowPlayingViewController's view), placed on every layout pass
// of the player, cover and chips. Synced lyrics own a stable text slot one grid gap above the title or pill.
// The ordinary cover fills the remaining room. Its size depends on the reserved rows, never the current words.
// Spotify's preview is masked while we own the slot and restored when the song has no synced lyrics.
//
// A lyric longer than two rows shows in full-size portions (only an overwide word shrinks): the
// line being sung's portion while it is timed by the word, else its share of the line's time (PlayerLyricFit.h).
//
// While the lyrics' menu shows translations (SGRKeyLyricsTranslation, the lyrics page's own switch), the line's
// translation (SGRPlayerLineTranslation: none, or one that only repeats the line, shows nothing) sits under it in a
// smaller type in the artist color with the lyrics page's translation weight and brightness, on one row that shrinks to
// SGRLyricMinScale and then truncates. It goes under the line only when the room holds both with a gap either side
// (SGRPlayerLineFitIn); else the line shows alone in today's place. The translations are the lyrics page's: on the
// same kept lines, which it translates in place, and the saved ones read onto them from disk (SGLyricsLoadTranslation,
// as the Live Activity restores them); the line never asks a translator. One saved, removed or switched on or off is
// picked up at once: the translation fades in or out and the pair settles into place (at once under Reduce Motion).
//
// It reads the line on a one-shot timer armed again after every update, aimed at the next portion or the next line,
// not a display link (a CADisplayLink capped at 60 Hz drags the player's 120 Hz transitions down), and changes only
// when the line does: the new line crosses over the old one. Seeks, rate changes, lyrics changes and coming back to
// the foreground re-aim it.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/PlayerSettings.h"
#import "Redesigned/Lyrics/AutoTranslation.h"
#import "Redesigned/Lyrics/LyricsText.h"
#import <math.h>
#import <stdatomic.h>
#import "Player.h"
#import "PlayerLyricLine.h"
#import "PlayerLyricFit.h"
#import "PlayerQueue.h"

static const CGFloat kPreviewInset = 24, kPreviewPoints = 19.098;
static NSString *const kSmall = @"spotifyglass.redesign.player.lyricLine.small";
static NSNotificationName const sizeChanged = @"SGRPlayerLineSizeChanged";
BOOL SGRPlayerLineSmall(void) { return [NSUserDefaults.standardUserDefaults boolForKey:kSmall]; }
void SGRSetPlayerLineSmall(BOOL small) {
    [NSUserDefaults.standardUserDefaults setBool:small forKey:kSmall];
    [NSNotificationCenter.defaultCenter postNotificationName:sizeChanged object:nil];
}
static void placeLine(void);

static char kLineKey, kStackKey, kTitleKey;
static __weak UIView *sg_host;              // SPTNowPlayingView
static __weak UIViewController *sg_floating; // the chips over the title (FloatingElementsUnit)
#if SG_DRIVER
static void flushChip(BOOL leaving);
#else
#define flushChip(leaving) ((void)0)
#endif
static CGFloat visibleChipTop(UIView *host, CGRect area);
static void watchLineChip(CALayer *root);

BOOL SGRPlayerLyricLineOn(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ on = SGHidden(SGRKeyPlayerLyricLine); });
    return on;
}

@interface SGRLyricLineView : UIView
@property (nonatomic, readonly) BOOL running;
@property (nonatomic) BOOL obscured;
@property (nonatomic) BOOL fits;   // set by the layout: there is room for it
@property (nonatomic) BOOL overClip;
@property (nonatomic) CGRect slot;
@property (nonatomic) CGFloat chipTop;
@property (nonatomic) CGRect chipArea;
@property (nonatomic, weak) UIView *ownedTilt;
@property (nonatomic) CGFloat normalSide;
- (void)setRightToLeft:(BOOL)rtl;
@property (nonatomic) CGRect room; // set by the layout: the gap under the cover, CGRectNull without one
- (void)tick;
- (void)setPlayerCovered:(BOOL)covered;
- (BOOL)place;
- (BOOL)placeWithChipTop:(CGFloat)top;
@end

@interface SGRLyricLineView () <SGPlayerStateObserver>
@end

@implementation SGRLyricLineView {
    UILabel *_label;
    NSTimer *_timer;   // one-shot, armed again after every update
    BOOL _running;     // in a window and Spotify in front: the timer runs
    BOOL _inactive, _covered, _underQueue, _refreshAfterQueue;
    UIView *_covers;
    NSArray<SGKaraokeLine *> *_source, *_ordered;
    BOOL _timed;
    NSInteger _index;
    NSString *_text;   // the line being sung, nil for none: what the label and VoiceOver name
    NSArray<SGRLyricPortion *> *_portions;   // that line's portions for the label's width and font
    CGFloat _portionWidth;                   // the width they were measured for
    BOOL _shown;
    UILabel *_translationLabel;
    NSString *_translation;      // the line being sung's translation, nil for none
    BOOL _translationShown;      // it is under the line: there is one and the room holds both
    // The kept lines the saved translations were last read onto, and in which language.
    NSArray<SGKaraokeLine *> *_restored;
    NSString *_restoredLanguage;
    // Where the timer was armed, to tell a seek, a pause or resume and a speed change from the report that follows.
    BOOL _armed;
    double _armedMs, _armedRate;
    CFAbsoluteTime _armedAt;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _index = NSNotFound;
    _room = CGRectNull;
    _chipTop = CGFLOAT_MAX;
    self.alpha = 0;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton | UIAccessibilityTraitUpdatesFrequently;
    self.accessibilityHint = SGL(@"settings.player.lyric_line.hint", @"Opens the lyrics.");
    _label = [[UILabel alloc] initWithFrame:self.bounds];
    _label.numberOfLines = 2;
    _label.lineBreakMode = NSLineBreakByWordWrapping;
    _label.textColor = UIColor.whiteColor;
    _label.font = [self font];
    [self addSubview:_label];
    _translationLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _translationLabel.numberOfLines = 1;
    _translationLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _translationLabel.adjustsFontSizeToFitWidth = YES;
    _translationLabel.minimumScaleFactor = SGRLyricMinScale;
    _translationLabel.alpha = 0;
    [self styleTranslation];
    [self addSubview:_translationLabel];
    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(queuePlaced:) name:SGRQueueSheetPlacedNotification object:nil];
    [center addObserver:self selector:@selector(activity:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(activity:) name:UIApplicationWillResignActiveNotification object:nil];
    // Lyrics kept for the track, or the Lyrics page's Delay changed: the line and its portions are read again.
    [center addObserver:self selector:@selector(linesChanged) name:SGKaraokeLinesKeptNotification object:nil];
    [center addObserver:self selector:@selector(linesChanged) name:SGLyricsOffsetsDidChangeNotification object:nil];
    // A translation saved, removed or deleted, or a job of the lyrics page's starting or ending (all posted on main):
    // the saved ones are read onto the lines again and the line looks again.
    for (NSNotificationName name in @[SGLyricsTranslationSavedNotification, SGLyricsTranslationsDidChangeNotification,
                                      SGRTranslationNotification]) {
        [center addObserver:self selector:@selector(translationsChanged) name:name object:nil];
    }
    // The menu's translation switch, or the Text sizes page's translation look.
    [center addObserver:self selector:@selector(lyricsTextChanged) name:SGRLyricsTextDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(sizeChanged) name:sizeChanged object:nil];
    SGAddPlayerStateObserver(self);
    return self;
}

- (UIFont *)font {
    return [UIFont systemFontOfSize:SGRPlayerLineSmall() ? 17 : kPreviewPoints weight:UIFontWeightBold];
}

- (void)styleTranslation {
    SGRLyricsTextLook look = SGRLyricsTextLookOf(SGRLyricsTextTranslation);
    _translationLabel.font = [UIFont systemFontOfSize:round([self font].pointSize * 0.8) weight:SGRLyricsTextFontWeight(look.weight)];
    // PlayerTitle.x gives the artist this same color, including under Increase Contrast.
    UIColor *dim = SGRSecondary();
    _translationLabel.textColor = [dim colorWithAlphaComponent:MIN(1, CGColorGetAlpha(dim.CGColor) * look.brightness / 100.0)];
}

- (CGFloat)translationHeight {
    return ceil(_translationLabel.font.lineHeight);
}

// Changing translation settings immediately updates the reserved rows.
- (void)lyricsTextChanged {
    [self styleTranslation];
    placeLine();
    [self setNeedsLayout];
    [self translationsChanged];
}

- (void)translationsChanged {
    _restored = nil;
    if (_running) [self tick];
}

// The saved translations of the playing track's kept lines read onto them, once for the lines and language: what
// the lyrics page shows for them even when it has not been opened this launch. A read from disk only.
- (void)restoreTranslations {
    NSString *track = SGKaraokePlayingTrack(), *language = SGLyricsGeminiLanguage();
    NSArray<SGKaraokeLine *> *lines = _source;
    if (!track.length || !lines.count || !language.length) return;
    if (lines == _restored && [language isEqualToString:_restoredLanguage]) return;
    _restored = lines;
    _restoredLanguage = language;
    __weak SGRLyricLineView *weakSelf = self;
    SGLyricsLoadTranslation(track, language, lines, ^BOOL {
        return [track isEqualToString:SGKaraokePlayingTrack()] && lines == SGKaraokeLinesForTrack(track)
            && [language isEqualToString:SGLyricsGeminiLanguage()] && SGFlag(SGRKeyLyricsTranslation, NO);
    }, ^{
        SGRLyricLineView *view = weakSelf;
        if (view && view->_running) [view tick];
    });
}

- (void)setRightToLeft:(BOOL)rtl {
    _label.textAlignment = _translationLabel.textAlignment = rtl ? NSTextAlignmentRight : NSTextAlignmentLeft;
}

- (BOOL)placeWithChipTop:(CGFloat)top {
    BOOL moving = _chipTop != top && self.userInteractionEnabled;
    _chipTop = top;
    if (!moving) return [self place];
    __block BOOL fits;
    SGRAnimate(SGRMotionLayout, ^{
        fits = [self place];
        [self layoutIfNeeded];
    }, nil);
    return fits;
}

- (BOOL)place {
    if (CGRectIsNull(_room)) return NO;
    // On the fallback path the room already starts below the unreserved artwork;
    // the same row budget applies, with no additional cover floor to subtract.
    CGFloat bottom = MIN(CGRectGetMaxY(_room), _chipTop) - SGRGrid;
    CGFloat row = ceil([self font].lineHeight);
    CGFloat tr = SGFlag(SGRKeyLyricsTranslation, NO) ? [self translationHeight] : 0;
    CGFloat floor = ceil(_normalSide * 2 / 3);
    CGFloat available = bottom - CGRectGetMinY(_room) - (_overClip ? 0 : SGRGrid + floor);
    NSInteger rows = SGRPlayerCompactRows(available, row, &tr);
    if (!rows) { SGRPlayerReserveCover(nil, 0); return NO; }
    CGRect slot = CGRectMake(_room.origin.x, bottom - rows * row - tr, _room.size.width, rows * row + tr);
    if (!CGRectEqualToRect(slot, _slot) || _label.numberOfLines != rows) {
        _slot = slot;
        _label.numberOfLines = rows;
        _portions = nil;
        [self setNeedsLayout];
    }
    CGFloat side = MIN(_normalSide, CGRectGetMinY(slot) - SGRGrid - CGRectGetMinY(_room));
    SGRPlayerReserveCover(_overClip ? nil : _ownedTilt, _overClip ? 0 : side);
    BOOL pair = tr > 0 && _translation.length;
    if (pair != _translationShown) {
        _translationShown = pair;
        _translationLabel.alpha = pair ? 1 : 0;
        [self setNeedsLayout];
    }
    self.accessibilityValue = pair ? _translation : nil;
    if (!CGRectEqualToRect(self.frame, slot)) {
        self.frame = slot;
        if (_overClip && _shown) SGRPlayerMotionLineMoved();
    }
    return YES;
}

// Give UILabel exactly Spotify's text rectangle. The translation never pushes it upwards.
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    _label.frame = CGRectMake(0, 0, bounds.size.width,
        bounds.size.height - (_translationShown ? [self translationHeight] : 0));
    CGFloat width = MIN(bounds.size.width, ceil([_translationLabel sizeThatFits:CGSizeMake(bounds.size.width, CGFLOAT_MAX)].width));
    _translationLabel.frame = CGRectMake(_label.textAlignment == NSTextAlignmentRight ? bounds.size.width - width : 0,
        CGRectGetMidY(_label.frame) + [self lineHeight] / 2, width, [self translationHeight]);
}

- (NSInteger)lyricRows { return _label.numberOfLines; }

- (CGFloat)lineHeight {
    if (!_label.text.length || self.slot.size.width <= 0) return ceil([self font].lineHeight);
    return ceil([_label textRectForBounds:(CGRect){CGPointZero, self.slot.size}
                    limitedToNumberOfLines:_label.numberOfLines].size.height);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    [self restyle];
}

// The text size changed: the line is measured again for the room, and its portions for the new font.
- (void)restyle {
    _label.font = [self font];
    [self styleTranslation];
    _portions = nil;
    // Over a clip the labels are sized to their text here, and the view's frame may not change with the font.
    [self setNeedsLayout];
    [self.superview setNeedsLayout];
}

// A size change shows at once, rather than at the line's next portion.
- (void)sizeChanged {
    [self restyle];
    placeLine();
    if (_running) [self tick];
}

// Touches only over the words, a tap's height tall, so a swipe across the rest of the gap still reaches the covers.
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    CGFloat text = [_label sizeThatFits:self.bounds.size].width;
    if (_translationShown) text = MAX(text, [_translationLabel sizeThatFits:self.bounds.size].width);
    CGFloat width = MIN(self.bounds.size.width, text + 2 * SGRSideMargin);
    CGRect words = CGRectMake(_label.textAlignment == NSTextAlignmentRight ? self.bounds.size.width - width : 0,
                              0, width, self.bounds.size.height);
    return CGRectContainsPoint(words, point);
}

- (void)tapped {
    if (!_shown || SGRPlayerLyricsOpen()) return;
    SGLog(@"redesign player: the line under the cover opens the lyrics");
    SGRPlayerToggleLyrics();
}

- (BOOL)accessibilityActivate {
    if (!_shown || SGRPlayerLyricsOpen()) return NO;
    [self tapped];
    return YES;
}

- (CGRect)accessibilityFrame {
    CGRect rows = [_label textRectForBounds:_label.bounds limitedToNumberOfLines:_label.numberOfLines];
    rows = [self convertRect:rows fromView:_label];
    if (_translationShown) rows = CGRectUnion(rows, _translationLabel.frame);
    return UIAccessibilityConvertFrameToScreenCoordinates(rows, self);
}

#pragma mark - the clock

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window && self.superview == sg_host) flushChip(YES);
    [self clock];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_covers removeObserver:self forKeyPath:@"alpha"];
    [_timer invalidate];
}

- (void)watchCovers:(UIView *)covers {
    if (_covers == covers) return;
    [_covers removeObserver:self forKeyPath:@"alpha"];
    _covers = covers;
    [_covers addObserver:self forKeyPath:@"alpha" options:0 context:NULL];
}

// Full lyrics take the covers away and give them back by setting alpha, even at the same slot width.
- (void)observeValueForKeyPath:(NSString *)key ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (object == _covers) [self tick];
    else [super observeValueForKeyPath:key ofObject:object change:change context:context];
}

- (void)activity:(NSNotification *)note {
    _inactive = [note.name isEqual:UIApplicationWillResignActiveNotification];
    [self clock];
}

- (void)setPlayerCovered:(BOOL)covered {
    _covered = covered;
    [self clock];
}

- (void)queuePlaced:(NSNotification *)note {
    UIView *sheet = note.object;
    BOOL covered = self.window && sheet.window == self.window &&
        CGRectContainsRect(sheet.bounds, [self convertRect:self.bounds toView:sheet]);
    if (_underQueue == covered) return;
    _underQueue = covered;
    if (covered) {
        _refreshAfterQueue = YES;
        [_label.layer removeAllAnimations];
        [_translationLabel.layer removeAllAnimations];
    }
    [self clock];
}

// Runs while the line is in a window and Spotify is in front; stopped otherwise. Coming back starts it over, which
// catches up with where the song went while it was away.
- (void)clock {
    BOOL run = self.window && !_inactive && !_covered && !_underQueue && UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    if (run == _running) return;
    _running = run;
    if (!run) {
        [_timer invalidate];
        _timer = nil;
        _armed = NO;
        [self watchCovers:nil];
        if (self.superview == sg_host) watchLineChip(nil);
        return;
    }
    [self tick];
}

// The next update, one shot, at the next portion or line the line being sung turns over at. Nothing nearer than
// SGRLyricMaxWait is a look every SGRLyricMaxWait, with its tolerance; a wait aimed at a boundary is not late.
- (void)armTimer:(SGRLyricWait)next {
    [_timer invalidate];
    _armedMs = SGKaraokePositionMs();
    _armedRate = [self rate];
    _armedAt = CFAbsoluteTimeGetCurrent();
    _armed = _armedMs >= 0;
    __weak SGRLyricLineView *weakSelf = self;
    _timer = [NSTimer timerWithTimeInterval:next.wait repeats:NO block:^(NSTimer *timer) { [weakSelf tick]; }];
    _timer.tolerance = next.tolerance;
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
}

// The rate the song's time runs at: 0 while the player is paused or has not said, so nothing is aimed at.
- (double)rate {
    SPTPlayerState *state = SGPlayerState();
    if (!state || state.isPaused) return 0;
    double rate = state.playbackSpeed;
    return rate > 0 ? rate : 1;
}

// A report from the player: a seek re-aims the timer, and so does a speed change. A paused report carries the exact
// place the song was put, so any move of it while paused is a seek, however small: it can cross a portion's boundary.
- (void)playerStateDidChange:(SPTPlayerState *)state {
    if (_running) [self tick];  // a new track can start at exactly the last one's reported position
}

- (void)playerStateDidReport:(SPTPlayerState *)state {
    [self rearmForState:state];
}

- (void)rearmForState:(SPTPlayerState *)state {
    if (!_running || !_fits || !_timed || SGRPlayerLyricsOpen() || (_covers && _covers.alpha <= 0.01)) return;
    if (!_armed) {
        [self tick];
        return;
    }
    // Whole milliseconds, as SGKaraokePositionMs counts the position the timer was armed at.
    double position = (state.isPaused ? state.positionAsOfTimestamp : state.position) * 1000;
    if (SGRLyricRearmNeeded((NSInteger)_armedMs, _armedRate, (NSInteger)position, [self rate],
                            CFAbsoluteTimeGetCurrent() - _armedAt)) {
        [self tick];
    }
}

// The lines were kept or the Delay moved: read again from here, and aimed again from what is read. While the line is
// stopped the next clock does it.
- (void)linesChanged {
    if (_running) [self tick];
}

// The playing track's synced lines in time order, and the one being sung; NSNotFound when there is none to show.
- (NSInteger)currentIndex {
    NSArray<SGKaraokeLine *> *lines = SGKaraokeLinesForTrack(SGKaraokePlayingTrack());
    if (lines != _source) {
        _source = lines;
        _ordered = lines ? SGKaraokeInTimeOrder(lines) : nil;
        _timed = lines && SGKaraokeLinesTiming(lines) != SGKaraokeTimingNone;
    }
    if (!_timed) return NSNotFound;
    NSInteger ms = SGKaraokePositionMs();
    if (ms < 0) return NSNotFound;
    NSInteger index = SGKaraokeLeadLine(_ordered, ms - SGKaraokeDelayMs());
    return index < 0 ? NSNotFound : index;
}

- (CGFloat)textWidth {
    return CGRectGetWidth(self.slot);
}

- (void)showLine:(BOOL)shown {
    if (shown == _shown) return;
    _shown = shown;
    self.userInteractionEnabled = shown;
    self.accessibilityElementsHidden = !shown;
    if (_overClip) SGRPlayerMotionLineMoved();
    SGRAnimate(shown ? SGRMotionFade : SGRMotionRespond, ^{ self.alpha = shown ? 1 : 0; }, nil);
}

- (void)tick {
    if (!_running) return;
    [self watchCovers:SGRPlayerCoverList()];
    _obscured = SGRPlayerLyricsOpen() || (_covers && _covers.alpha <= 0.01);
    if (_obscured) {
        [_timer invalidate];
        _timer = nil;
        _armed = NO;
        [self showLine:NO];
        return;
    }
    NSArray<SGKaraokeLine *> *before = _source;
    NSInteger index = [self currentIndex];
    if (index != _index || _source != before) {
        _index = index;
        NSString *text = index == NSNotFound ? nil
            : [SGKaraokeLineText(_ordered[(NSUInteger)index]) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        _text = text.length ? text : nil;
        _portions = nil;
        self.accessibilityLabel = _text;
    }
    // The portion of the line the label has room for, measured once for the line, the width and the font.
    SGKaraokeLine *line = _index == NSNotFound ? nil : _ordered[(NSUInteger)_index];
    if (line && (!_portions || _portionWidth != [self textWidth])) {
        _portionWidth = [self textWidth];
        _portions = SGRLyricPortionsInRows(line, _portionWidth, [self font], _label.numberOfLines);
    }
    SGRLyricPortion *following = nil;
    if (_portions.count) {
        // The portion holding the position, which is the first for a line just begun and after a seek back into it.
        NSUInteger at = (NSUInteger)SGRLyricPortionAt(_portions, SGKaraokePositionMs() - SGKaraokeDelayMs());
        SGRLyricPortion *shown = _portions[at];
        if (at + 1 < _portions.count) following = _portions[at + 1];
        [self showText:shown.text scale:shown.scale];
    } else if (line && _text) [self showText:_text scale:1];
    // Its translation, read again every update, so one that arrives mid-line shows at once. With no line the last one
    // stays, as the line's own text does, for the fade out.
    BOOL translations = SGFlag(SGRKeyLyricsTranslation, NO);
    if (translations && _source) [self restoreTranslations];
    if (line) {
        NSString *translation = SGRPlayerLineTranslation(line, translations);
        if (translation != _translation && ![translation isEqualToString:_translation]) [self showTranslation:translation];
    }
    // Spotify's own preview can come up with no pass of a view this file hooks (its cover cell unhidden as the song
    // changes), so every update looks again: while the line takes its place it is hidden again, else the line stands
    // down by its next portion at the latest. The layout gives the room back once the preview goes.
    if (objc_getAssociatedObject(self.superview, &kLineKey) == self) placeLine();
    [self showLine:_fits && _text];
    _refreshAfterQueue = NO;
    NSInteger position = SGKaraokePositionMs(), delay = SGKaraokeDelayMs();
    double rate = [self rate];
    // A hidden slot has no deadline. A visible slot before the first line does, even though its label is clear.
    BOOL future = _index == NSNotFound || _index + 1 < (NSInteger)_ordered.count || following != nil;
    if (_fits && _timed && position >= 0 && rate > 0 && future) {
        // Placement can straddle the boundary. Catch up to words not yet drawn instead of waiting past them.
        SGRLyricWait next = following && following.start <= position - delay ? (SGRLyricWait){SGRLyricMinWait, 0}
            : SGRLyricLineWaitInRows(_ordered, position, delay, [self textWidth], [self font], rate, _label.numberOfLines);
        [self armTimer:next];
    } else {
        [_timer invalidate];
        _timer = nil;
        _armedMs = position;
        _armedAt = CFAbsoluteTimeGetCurrent();
        _armedRate = rate;
        _armed = position >= 0;
    }
}

// A new line, or a new portion of it, crosses over the one before; one coming while the line is out of sight is set
// at once. With no line the last one stays in the label for the fade out.
- (void)showText:(NSString *)text scale:(CGFloat)scale {
    UIFont *font = SGRLyricFontAtScale([self font], scale);
    if (!text) return;
    NSDictionary *attributes = @{NSFontAttributeName:font};
    if (text.length && [text isEqual:_label.text] && _label.attributedText.length &&
        [[_label.attributedText attribute:NSFontAttributeName atIndex:0 effectiveRange:nil] isEqual:font] &&
        [_label.font isEqual:font]) return;
    _label.font = font;
    UILabel *label = _label;
    [self setNeedsLayout];
    NSAttributedString *styled = [[NSAttributedString alloc] initWithString:text attributes:attributes];
    if (!_shown || _refreshAfterQueue || [label.text isEqual:text]) label.attributedText = styled;
    else [UIView transitionWithView:label duration:SGRCrossfade
                       options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                    animations:^{ label.attributedText = styled; } completion:nil];
    _fits = [self place];
}

// A new translation crosses over the one under the line, or comes in with its place; none fades the last one out.
// The pair settles into its place with a layout spring, at once under Reduce Motion, where only the fade is kept.
- (void)showTranslation:(NSString *)translation {
    BOOL crossing = _shown && !_refreshAfterQueue && _translationShown && translation;
    _translation = translation;
    [self setNeedsLayout];
    UILabel *label = _translationLabel;
    if (crossing) {
        [UIView transitionWithView:label duration:SGRCrossfade
                           options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                        animations:^{ label.text = translation; } completion:nil];
    } else if (translation) {
        label.text = translation;
    }
    if (!_shown) {
        [self place];
        return;
    }
    SGRAnimate(SGRMotionLayout, ^{
        [self place];
        [self layoutIfNeeded];
    }, nil);
}

@end

#pragma mark - the room under the cover

// Whether `view` shows: neither it nor any view above it up to `root` hidden or clear.
static BOOL showsIn(UIView *view, UIView *root) {
    for (UIView *v = view; v && v != root.superview; v = v.superview) {
        if (v.hidden || v.alpha < 0.01) return NO;
    }
    return YES;
}

// The video switch owns its whole pill, not just the inset text or image. For other chips
// use the visible controls, labels and images. Carry clipping and visibility down the tree.
static BOOL layerOwnPaint(CALayer *layer) {
    if (!layer || layer.hidden || layer.opacity < .01 || CGRectIsEmpty(layer.bounds)) return NO;
    if (layer.contents || (layer.backgroundColor && CGColorGetAlpha(layer.backgroundColor) > .01) ||
        (layer.borderWidth > 0 && layer.borderColor && CGColorGetAlpha(layer.borderColor) > .01)) return YES;
    if ([layer isKindOfClass:CAShapeLayer.class]) {
        CAShapeLayer *shape = (CAShapeLayer *)layer;
        if (shape.path && !CGPathIsEmpty(shape.path) && ((shape.fillColor && CGColorGetAlpha(shape.fillColor) > .01) ||
            (shape.lineWidth > 0 && shape.strokeColor && CGColorGetAlpha(shape.strokeColor) > .01))) return YES;
    }
    if ([layer isKindOfClass:CAGradientLayer.class])
        for (id color in ((CAGradientLayer *)layer).colors) if (CGColorGetAlpha((__bridge CGColorRef)color) > .01) return YES;
    UIView *v = [layer.delegate isKindOfClass:UIView.class] ? (UIView *)layer.delegate : nil;
    if (([v isKindOfClass:UILabel.class] && [(UILabel *)v text].length) ||
        ([v isKindOfClass:UIImageView.class] && [(UIImageView *)v image])) return YES;
    return NO;
}
static BOOL layerPaints(CALayer *layer) {
    if (layer.hidden || layer.opacity < .01 || CGRectIsEmpty(layer.bounds) ||
        (layer.mask && !layerPaints(layer.mask))) return NO;
    if (layerOwnPaint(layer)) return YES;
    for (CALayer *child in layer.sublayers) if (layerPaints(child)) return YES;
    return NO;
}
static CGRect maskBox(UIView *v, UIView *host) {
    CALayer *mask = v.layer.mask;
    CGPathRef path = [mask isKindOfClass:CAShapeLayer.class] ? ((CAShapeLayer *)mask).path : NULL;
    if (!path) return [host convertRect:mask.frame fromView:v];
    CGRect box = CGPathGetPathBoundingBox(path);
    if (CGRectIsEmpty(box)) return CGRectNull;
    // A mask has no superlayer. Its anchor/position nevertheless place its local path in the owner's bounds.
    CGRect b = mask.bounds;
    box = CGRectOffset(box, -b.origin.x - b.size.width * mask.anchorPoint.x, -b.origin.y - b.size.height * mask.anchorPoint.y);
    box = CGRectApplyAffineTransform(box, mask.affineTransform);
    return [host convertRect:CGRectOffset(box, mask.position.x, mask.position.y) fromView:v];
}
static BOOL chipVisibleThrough(UIView *v, UIView *host, CGRect *clip) {
    if (v.hidden || v.layer.hidden || v.alpha < .01 || v.layer.opacity < .01 || CGRectIsEmpty(v.bounds)) return NO;
    CGRect bounds = [host convertRect:v.bounds fromView:v];
    if (CGRectIsEmpty(bounds)) return NO;
    if (v.clipsToBounds) *clip = CGRectIntersection(*clip, bounds);
    CALayer *mask = v.layer.mask;
    if (mask) {
        if (!layerPaints(mask)) return NO;
        *clip = CGRectIntersection(*clip, maskBox(v, host));
    }
    return !CGRectIsEmpty(*clip);
}
#if SG_DRIVER
static __weak UIView *sg_chip;
static uint64_t sg_tree;
static void chipMix(uint64_t n) { sg_tree = (sg_tree ^ n) * UINT64_C(1099511628211); }
static void chipNumbers(const CGFloat *numbers, size_t count) {
    for (size_t i = 0; i < count; i++) {
        double value = numbers[i];
        uint64_t bits;
        memcpy(&bits, &value, sizeof(bits));
        chipMix(bits);
    }
}
static void fingerprintLayer(CALayer *l, CGRect frame) {
    chipMix((uintptr_t)(__bridge void *)l.class);
    chipMix(l.hidden | ((l.contents != nil) << 1) | ((l.backgroundColor && CGColorGetAlpha(l.backgroundColor) > 0) << 2));
    chipNumbers((CGFloat[]){frame.origin.x, frame.origin.y, frame.size.width, frame.size.height, l.opacity, l.cornerRadius}, 6);
    if ([l isKindOfClass:CAShapeLayer.class] && ((CAShapeLayer *)l).path) {
        CGRect b = CGPathGetPathBoundingBox(((CAShapeLayer *)l).path);
        chipNumbers((CGFloat[]){b.origin.x,b.origin.y,b.size.width,b.size.height},4);
    }
    if (l.mask) fingerprintLayer(l.mask, l.mask.frame);
}
enum { kChipPartBytes = 840, kChipParts = 4 };
static NSString *chipClass(id object) {
    NSString *name = NSStringFromClass([object class]);
    // Keep the informative type suffix, not a private Swift context hash.
    if ([name hasPrefix:@"_Tt"] && name.length > 48) return [@"…" stringByAppendingString:[name substringFromIndex:name.length-48]];
    return name;
}
static void appendChipTree(NSMutableString *tree, UIView *v, UIView *host, NSUInteger depth) {
    if (tree.length >= kChipPartBytes * kChipParts) return;
    CALayer *l = v.layer;
    NSMutableString *layers = [NSMutableString string];
    for (CALayer *child in l.sublayers) {
        if ([child.delegate isKindOfClass:UIView.class] && ((UIView *)child.delegate).layer == child) continue;
        if (layers.length >= 180) { [layers appendString:@"…"]; break; }
        [layers appendFormat:@"%@%@", layers.length ? @"," : @"", chipClass(child)];
    }
    [tree appendFormat:@"\nd%lu %@%@ %@", (unsigned long)depth, chipClass(v), v == sg_chip ? @"*" : @"",
        v.window == host.window ? NSStringFromCGRect([host convertRect:v.bounds fromView:v]) : @"unattached"];
    if (v.accessibilityIdentifier.length) [tree appendFormat:@" id=%@", [v.accessibilityIdentifier isEqual:SGVideoSwitchIdentifier] ? @"switch" : @"other"];
    if (v.hidden || l.hidden) [tree appendFormat:@" hidden=%d/%d",v.hidden,l.hidden];
    if (v.alpha != 1) [tree appendFormat:@" alpha=%.3g",v.alpha];
    if (v.clipsToBounds) [tree appendString:@" clips=1"];
    if (l.class != CALayer.class) [tree appendFormat:@" layer=%@",chipClass(l)];
    if (l.opacity != 1) [tree appendFormat:@" opacity=%.3g",l.opacity];
    if (l.mask) [tree appendFormat:@" mask=%@ box=%@",chipClass(l.mask),v.window == host.window ? NSStringFromCGRect(maskBox(v,host)) : @"unattached"];
    if (l.backgroundColor && CGColorGetAlpha(l.backgroundColor)>0) [tree appendString:@" bg=1"];
    if (l.contents) [tree appendString:@" contents=1"];
    if (l.cornerRadius) [tree appendFormat:@" radius=%.3g",l.cornerRadius];
    if (layers.length) [tree appendFormat:@" sub=%@",layers];
    for (UIView *child in v.subviews) {
        if (tree.length >= kChipPartBytes * kChipParts) break;
        appendChipTree(tree, child, host, depth + 1);
    }
}
// Structure and decision are independent of host translation. Keep the latest absolute pose
// separately so an animation costs one trailing snapshot, not one snapshot per layout.
static CGRect sg_area, sg_unitFrame;
static CGFloat sg_top;
static uint64_t sg_sentTree, sg_observedTree;
static CFTimeInterval sg_sentAt, sg_poseAt;
static BOOL sg_scheduled;
static NSData *sg_pending;
static void flushChip(BOOL leaving) {
    if (!sg_pending || (!leaving && sg_scheduled)) return;
    CFTimeInterval now = CACurrentMediaTime();
    CFTimeInterval due = sg_sentAt + 1;
    if (sg_observedTree == sg_sentTree) due = MAX(due, sg_poseAt + 1);
    if (!leaving && due > now) {
        sg_scheduled = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((due-now)*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            sg_scheduled = NO; flushChip(NO);
        });
        return;
    }
    sg_sentTree = sg_observedTree; sg_sentAt = now;
    NSData *data = sg_pending;
    sg_pending = nil;
    const uint8_t *bytes = data.bytes;
    NSUInteger offset = 0;
    for (NSUInteger part = 1; part <= kChipParts && offset < data.length; part++) {
        NSUInteger end = MIN(offset + kChipPartBytes, data.length);
        while (end < data.length && (bytes[end] & 0xc0) == 0x80) end--;
        NSString *chunk = [[NSString alloc] initWithBytes:bytes+offset length:end-offset encoding:NSUTF8StringEncoding];
        SGLog(@"lyrics unit: %lu %@%@", (unsigned long)part, chunk, part == kChipParts && end < data.length ? @" [capped]" : @"");
        offset = end;
    }
}
static void reportChip(UIView *host, CGRect area, CGFloat top, CGFloat titleTop, CGRect stack, CGFloat normalSide) {
    if (!host.window) return;
    UIView *unit = sg_floating.viewIfLoaded;
    BOOL attached = unit.window && unit.window == host.window;
    CGRect frame = attached ? [host convertRect:unit.bounds fromView:unit] : CGRectNull;
    chipMix(attached); chipMix((uintptr_t)(__bridge void *)sg_chip);
    if (sg_chip) chipNumbers((CGFloat[]){top - CGRectGetMinY(frame)}, 1);
    chipNumbers(&normalSide,1);
    static CGRect priorStack;
    static CGFloat priorTitle;
    BOOL pose = !CGRectEqualToRect(frame, sg_unitFrame) || !CGRectEqualToRect(area, sg_area) || top != sg_top ||
        !CGRectEqualToRect(stack,priorStack) || titleTop != priorTitle;
    priorStack = stack; priorTitle = titleTop;
    if (!pose && sg_tree == sg_observedTree) return;
    if (pose) sg_poseAt = CACurrentMediaTime();
    sg_unitFrame = frame; sg_area = area; sg_top = top;
    sg_observedTree = sg_tree;
    // The player can disappear before the coalescing deadline. Keep bytes, not its live views.
    NSMutableString *record = [NSMutableString stringWithFormat:@"loaded=%d attached=%d area=%@ top=%@ winner=%@ titleTop=%@ stack=%@ normalSide=%.3f",
        unit != nil, attached, NSStringFromCGRect(area), top == CGFLOAT_MAX ? @"none" : @(top).stringValue,
        sg_chip ? chipClass(sg_chip) : @"none", titleTop == CGFLOAT_MAX ? @"none" : @(titleTop).stringValue,
        NSStringFromCGRect(stack),normalSide];
    if (unit) appendChipTree(record, unit, host, 0);
    sg_pending = [record dataUsingEncoding:NSUTF8StringEncoding];
    flushChip(NO);
}
#endif
static CGFloat chipTopInBranch(UIView *view, UIView *host, CGRect clip, UIView **winner, BOOL placement) {
    // Parent-local geometry preserves hierarchy and ignores a translation of the whole unit.
    BOOL identified = [view.accessibilityIdentifier isEqualToString:SGVideoSwitchIdentifier];
#if SG_DRIVER
    BOOL record = placement;
    if (record) {
        fingerprintLayer(view.layer, view == sg_floating.viewIfLoaded ? view.bounds : view.frame);
        chipMix(view.subviews.count); chipMix(view.layer.sublayers.count);
        chipMix((uintptr_t)(__bridge void *)view.class);
        chipMix(view.clipsToBounds | (view.hidden << 1) | (identified << 2) | ((view.accessibilityIdentifier.length != 0) << 3));
        chipNumbers((CGFloat[]){view.alpha}, 1);
    }
#else
    BOOL record = NO;
#endif
    if (!CGRectIsEmpty(clip) && !chipVisibleThrough(view, host, &clip)) clip = CGRectNull;
    CGRect visible = CGRectIsEmpty(clip) ? CGRectNull : CGRectIntersection(clip, [host convertRect:view.bounds fromView:view]);
    if (!record && CGRectIsEmpty(clip)) return CGFLOAT_MAX;
    BOOL control = !placement && ([view isKindOfClass:UIControl.class] || [view isKindOfClass:UIVisualEffectView.class]);
    BOOL owns = !CGRectIsEmpty(visible) && (identified || control || layerOwnPaint(view.layer));
    CGFloat top = CGFLOAT_MAX;
    for (CALayer *layer in view.layer.sublayers) {
        if ([layer.delegate isKindOfClass:UIView.class] && ((UIView *)layer.delegate).layer == layer) continue;
#if SG_DRIVER
        if (record) fingerprintLayer(layer, layer.frame);
#endif
        if (owns || CGRectIsEmpty(clip) || !layerPaints(layer)) continue;
        CGRect rect = CGRectIntersection(clip, [host convertRect:layer.frame fromView:view]);
        if (!CGRectIsEmpty(rect) && CGRectGetMinY(rect) < top) { *winner = view; top = CGRectGetMinY(rect); }
    }
    for (UIView *child in view.subviews) {
        UIView *candidate = nil;
        CGFloat other = chipTopInBranch(child, host, clip, &candidate, placement);
        if (other < top) { top = other; *winner = candidate; }
    }
    if (owns) { *winner = view; return CGRectGetMinY(visible); }
    return top;
}

static CGFloat visibleChipTop(UIView *host, CGRect area) {
    UIView *floating = sg_floating.viewIfLoaded;
#if SG_DRIVER
    sg_chip = nil;
    sg_tree = UINT64_C(14695981039346656037);
#endif
    if (!floating) return CGFLOAT_MAX;
    CGRect clip = CGRectNull;
    if (!CGRectIsEmpty(area) && floating.window && floating.window == host.window) {
        clip = CGRectIntersection(area, [host convertRect:host.window.bounds fromView:host.window]);
        clip = CGRectIntersection(clip, [host convertRect:floating.bounds fromView:floating]);
        for (UIView *v = floating.superview; v; v = v.superview)
            if (!chipVisibleThrough(v, host, &clip)) { clip = CGRectNull; break; }
    }
    UIView *winner = nil;
    CGFloat top = chipTopInBranch(floating, host, clip, &winner, YES);
#if SG_DRIVER
    sg_chip = winner;
#endif
    return top;
}

static void refreshEmptyStrip(UIView *host);

// With the lyric clock off, follow the inputs to the same chip measurement.
// Watch only the floating unit (including its masks); sublayers changes catch
// insertions/removals even when neither controller is laid out again.
@interface SGRFloatingStripWatch : NSObject
- (void)follow:(CALayer *)root;
@end

@implementation SGRFloatingStripWatch {
    NSSet<CALayer *> *_layers;
    __weak CALayer *_root;
    BOOL _rescan;
    atomic_bool _pending;
}
static void collectStripLayers(CALayer *layer, NSMutableSet *layers) {
    if (!layer || [layers containsObject:layer]) return;
    [layers addObject:layer];
    collectStripLayers(layer.mask, layers);
    for (CALayer *child in layer.sublayers) collectStripLayers(child, layers);
}
static NSArray<NSString *> *stripKeys(CALayer *layer) {
    static NSArray *keys, *shape, *gradient;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @[@"sublayers", @"mask", @"hidden", @"opacity", @"bounds", @"position", @"anchorPoint",
                 @"transform", @"sublayerTransform", @"masksToBounds", @"contents", @"backgroundColor", @"borderColor", @"borderWidth"];
        shape = [keys arrayByAddingObjectsFromArray:@[@"path", @"fillColor", @"strokeColor", @"lineWidth"]];
        gradient = [keys arrayByAddingObject:@"colors"];
    });
    return [layer isKindOfClass:CAShapeLayer.class] ? shape : [layer isKindOfClass:CAGradientLayer.class] ? gradient : keys;
}
- (void)follow:(CALayer *)root {
    if (root == _root && !_rescan) return;
    _root = root;
    _rescan = NO;
    NSMutableSet *next = [NSMutableSet set];
    collectStripLayers(root, next);
    for (CALayer *layer in _layers) if (![next containsObject:layer])
        for (NSString *key in stripKeys(layer)) [layer removeObserver:self forKeyPath:key];
    for (CALayer *layer in next) if (![_layers containsObject:layer])
        for (NSString *key in stripKeys(layer)) [layer addObserver:self forKeyPath:key options:0 context:NULL];
    _layers = next;
}
- (void)observeValueForKeyPath:(NSString *)key ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (atomic_exchange(&_pending, true)) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        atomic_store(&self->_pending, false);
        self->_rescan = YES;
        if (SGRPlayerLyricLineOn()) placeLine();
        else refreshEmptyStrip(sg_host);
    });
}
@end

static void watchLineChip(CALayer *root) {
    static SGRFloatingStripWatch *watch;
    if (root && !watch) watch = [SGRFloatingStripWatch new];
    [watch follow:root];
    if (!root) watch = nil;
}

// The shared switch hook removes the button, not its allocated unit. Do
// not change the stack: give just the artwork its ordinary square back.
static void refreshEmptyStrip(UIView *host) {
    UIView *unit = sg_floating.viewIfLoaded;
    CALayer *root = nil;
    BOOL empty = NO;
    if (host.window && unit.window == host.window && SGVideoSwitchHidden() &&
        host.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPhone && host.bounds.size.height > host.bounds.size.width) {
        UIView *stack = SGRFindByIdentifier(host, @"npv.bottomStackView", &kStackKey);
        if (stack && [unit isDescendantOfView:stack]) {
            root = unit.layer;
            CGRect strip = [host convertRect:unit.bounds fromView:unit];
            UIView *winner = nil;
            empty = !CGRectIsEmpty(strip) && CGRectContainsRect([host convertRect:stack.bounds fromView:stack], strip) &&
                chipTopInBranch(unit, unit, unit.bounds, &winner, NO) == CGFLOAT_MAX;
        }
    }
    // With the line on, placement already watches this same unit for chip movement.
    if (!SGRPlayerLyricLineOn()) watchLineChip(root);
    SGRPlayerEmptyStripIn(empty ? host : nil);
}

// Spotify's own lyric preview under the cover, beside the tilt view, shown when Spotify's lyrics setting has it:
// Lyrics_NPVContainerKit.LyricsContainerView, and in 9.1.90 Lyrics_NPVElementsKitImpl.LyricsElementWrapperView.
static BOOL isPreview(UIView *view) {
    static Class preview, wrapper;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        preview = NSClassFromString(@"_TtC22Lyrics_NPVContainerKit19LyricsContainerView");
        wrapper = NSClassFromString(@"_TtC25Lyrics_NPVElementsKitImpl24LyricsElementWrapperView");
    });
    return (preview && [view isKindOfClass:preview]) || (wrapper && [view isKindOfClass:wrapper]);
}

static BOOL previewOccupies(UIView *preview, UIView *root) {
    return preview.bounds.size.height > 1 && showsIn(preview, root);
}

NSArray<CALayer *> *SGRPlayerPreviewLayers(UIView *column, BOOL *showing) {
    NSMutableArray *layers = [NSMutableArray array];
    *showing = NO;
    for (UIView *sibling in column.subviews) if (isPreview(sibling)) {
        [layers addObject:sibling.layer];
        // Both pictures move/hide with the column; only the preview's own
        // visibility decides their relative sizes when the page returns.
        if (previewOccupies(sibling, sibling)) *showing = YES;
    }
    return layers;
}

static BOOL previewShowing(UIView *tilt, UIView *host) {
    for (UIView *sub in tilt.superview.subviews) {
        if (isPreview(sub) && previewOccupies(sub, host)) return YES;
    }
    return NO;
}

static char kPreviewMaskKey;      // on a preview the line hid: the empty mask that hides it
static char kPreviewOwnMaskKey;   // and the mask of Spotify's that one replaced, if it had one
static BOOL sg_takesPreview;      // the line takes the previews' place
static NSHashTable<UIView *> *sg_hiddenPreviews;   // every preview the line hid, wherever it is now

// Hidden by a mask of the line's own, an empty layer, so Spotify's alpha and touches are never touched, and kept
// from VoiceOver. Set again on every call: a mask Spotify puts on in the meantime is the one given back.
static void hidePreview(UIView *preview) {
    CALayer *mask = objc_getAssociatedObject(preview, &kPreviewMaskKey);
    if (!mask) {
        mask = [CALayer layer];
        objc_setAssociatedObject(preview, &kPreviewMaskKey, mask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CALayer *layer = preview.layer;
    if (layer.mask != mask) {
        objc_setAssociatedObject(preview, &kPreviewOwnMaskKey, layer.mask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        layer.mask = mask;
    }
    preview.accessibilityElementsHidden = YES;
    if (!sg_hiddenPreviews) sg_hiddenPreviews = [NSHashTable weakObjectsHashTable];
    [sg_hiddenPreviews addObject:preview];
}

// Only the line's mask comes off, Spotify's own back in its place; one Spotify put on since is left as it is.
static void showPreview(UIView *preview) {
    CALayer *mask = objc_getAssociatedObject(preview, &kPreviewMaskKey), *layer = preview.layer;
    if (mask && layer.mask == mask) layer.mask = objc_getAssociatedObject(preview, &kPreviewOwnMaskKey);
    objc_setAssociatedObject(preview, &kPreviewMaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(preview, &kPreviewOwnMaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    preview.accessibilityElementsHidden = NO;
}

// The playing track has synced lines the line can show.
static BOOL playingTrackSynced(void) {
    NSArray<SGKaraokeLine *> *lines = SGKaraokeLinesForTrack(SGKaraokePlayingTrack());
    return lines.count && SGKaraokeLinesTiming(lines) != SGKaraokeTimingNone;
}

// Whether the line has the place under the cover to itself: it takes Spotify's preview's place, which hides every
// preview in the covers (the next cover's too, so a skip or a swipe never shows one), or the preview does not show.
// Every preview it hid, under the covers or not, is given back once it no longer takes their place. Asked again on
// every update, so lines kept for the track, or a new track, are looked at.
static void settlePreview(UIView *host, UIView *tilt, BOOL takes) {
    for (UIView *preview in SGRPlayerPreviewsToGiveBack(sg_hiddenPreviews, takes)) showPreview(preview);
    if (takes) {
        UIView *covers = SGRPlayerCoverList();
        SGForEachView(covers && [tilt isDescendantOfView:covers] ? covers : tilt.superview, ^(UIView *view) {
            if (isPreview(view)) hidePreview(view);
        });
    }
    // A hand-over found by an update rather than a pass (the switch set where no notification says so, lines kept)
    // measures the room again on the player's next pass.
    if (takes != sg_takesPreview) {
        SGLog(@"redesign player: the line under the cover %@ Spotify's lyric preview",
              takes ? @"takes the place of" : @"gives the place back to");
        sg_takesPreview = takes;
        [host setNeedsLayout];
    }
}

static void placeLine(void) {
    UIView *host = sg_host;
    static BOOL placing;
    if (!host || !SGRPlayerLyricLineOn() || placing) return;
    placing = YES; // Reserving or releasing a tilt synchronously lays it out again.
    SGRLyricLineView *line = objc_getAssociatedObject(host, &kLineKey);
    if (!line) {
        line = [[SGRLyricLineView alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(host, &kLineKey, line, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGLog(@"redesign player: the line under the cover goes into %@", NSStringFromClass(host.class));
    }
    if (line.superview != host) [host addSubview:line];
    UIView *unitView = sg_floating.viewIfLoaded;
    if (line.running)
        watchLineChip(unitView.window == host.window ? unitView.layer : nil);

    UIView *art = SGRPlayerShowingCover();
    UIView *tilt = art.superview;
    UIView *stack = SGRFindByIdentifier(host, @"npv.bottomStackView", &kStackKey);
    CGRect room = CGRectNull;
    BOOL clear = tilt && [tilt isDescendantOfView:host];
    BOOL clip = SGRPlayerMotionShowing();
    UIView *title = SGRFindByIdentifier(stack, @"now-playing-title-label", &kTitleKey);
    BOOL rtl = (title ?: stack).effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGFloat priorWidth = line.slot.size.width;
    NSInteger priorRows = [line lyricRows];
    BOOL wasCompact = line.normalSide > 0;
    CGFloat chipTop = CGFLOAT_MAX;
    line.chipArea = CGRectNull;
    line.normalSide = 0;
    line.ownedTilt = nil;
    BOOL wants = title && SGRPlayerLineTakesPreview(YES, host.bounds.size.height > host.bounds.size.width, playingTrackSynced());
    CGRect stackFrame = stack ? [host convertRect:stack.bounds fromView:stack] : CGRectNull;
    CGRect anchor = title ? [host convertRect:title.bounds fromView:title] : stackFrame;
    if (clear && stack && host.bounds.size.height > host.bounds.size.width) {
        CGFloat inset = title ? (rtl ? CGRectGetMaxX(host.bounds) - CGRectGetMaxX(anchor)
                                     : CGRectGetMinX(anchor) - CGRectGetMinX(host.bounds)) : kPreviewInset;
        CGRect slot = CGRectInset(host.bounds, inset, 0);
        [line setRightToLeft:rtl];
        CGRect unshrunk = CGRectMake(art.center.x - art.bounds.size.width / 2, art.center.y - art.bounds.size.height / 2,
                                     art.bounds.size.width, art.bounds.size.height);
        CGFloat top = clip ? host.safeAreaInsets.top : CGRectGetMaxY([host convertRect:unshrunk fromView:tilt]);
        CGFloat bottom = CGRectGetMinY(anchor);
        // Artwork and chip detection use the player's content margins, not the title's live inset.
        CGRect content = CGRectInset(host.bounds, 3 * SGRGrid, 0);
        CGRect normal = SGRPlayerNormalCover(host, tilt, content.size.width);
        // The floating unit can be the first row *inside* the stack. Search independently
        // of the reserved cover's bottom, including on the pass that first finds the switch.
        CGFloat searchTop = !clip && wants && !CGRectIsNull(normal) ? normal.origin.y : top;
        line.chipArea = CGRectMake(content.origin.x, searchTop, content.size.width, MAX(0, bottom-searchTop));
        chipTop = visibleChipTop(host, line.chipArea);
        // Removing the button need not collapse Spotify's allocated strip. Only visible
        // paint sets clearance, but the strip itself explains the narrower native square.
        UIView *unit = sg_floating.viewIfLoaded;
        CGRect strip = host.window && unit.window == host.window ? [host convertRect:unit.bounds fromView:unit] : CGRectNull;
        BOOL allocated = !CGRectIsEmpty(strip) && CGRectContainsRect(stackFrame,strip) && CGRectGetMaxY(strip) <= bottom;
        if (wants && !CGRectIsNull(normal) &&
            (fabs(tilt.bounds.size.width - normal.size.width) <= 1 || allocated || previewShowing(tilt, host))) {
            line.ownedTilt = tilt;
            line.normalSide = normal.size.width;
        }
        if (line.normalSide && !clip) top = normal.origin.y;
        if (bottom > top)
            room = CGRectMake(slot.origin.x, top, slot.size.width, bottom - top);
    } else chipTop = visibleChipTop(host, line.chipArea);
    BOOL changed = line.overClip != clip;
    line.overClip = clip;
    if (!line.normalSide) SGRPlayerReserveCover(nil, 0);
    line.room = room;
    BOOL fits = [line placeWithChipTop:chipTop];
    settlePreview(host, tilt, wants && fits);
    if (!fits) SGRPlayerReserveCover(nil, 0);
    if (fits && line.normalSide && !clip) SGRPlayerEmptyStripIn(nil);
    else refreshEmptyStrip(host);
#if SG_DRIVER
    reportChip(host,line.chipArea,chipTop,title ? CGRectGetMinY(anchor) : CGFLOAT_MAX,stackFrame,fits && !clip ? line.normalSide : 0);
#endif
    if (!wants && previewShowing(tilt, host)) fits = NO;
    // Both slots can fit and have the same width. Their ownership still changes
    // which source the clock must show (or clear) on this layout pass.
    UIView *covers = SGRPlayerCoverList();
    if (line.running) [line watchCovers:covers];
    BOOL obscured = SGRPlayerLyricsOpen() || (covers && covers.alpha <= 0.01);
    if (fits != line.fits || changed || obscured != line.obscured || wasCompact != (line.normalSide > 0) ||
        priorWidth != line.slot.size.width || priorRows != [line lyricRows]) {
        line.fits = fits;
        [line tick];
    }
    placing = NO;
}

void SGRPlayerLyricClipChanged(void) { placeLine(); }

CGRect SGRPlayerVisibleClipLineIn(UIView *view) {
    SGRLyricLineView *line = objc_getAssociatedObject(sg_host, &kLineKey);
    return line.overClip && line.userInteractionEnabled && view.window == line.window ? SGRPlayerLyricLineIn(view) : CGRectNull;
}

CGRect SGRPlayerLyricLineIn(UIView *view) {
    UIView *host = sg_host;
    SGRLyricLineView *line = host ? objc_getAssociatedObject(host, &kLineKey) : nil;
    if (!view || !line.fits || !line.window) return CGRectNull;
    return [view convertRect:line.bounds fromView:line];
}

// Spotify's preview is as wide as the cover's column, 24 pt in from the player's sides, and its text starts at its
// edge: 8 pt out from the title under it, which stands SGRPlayerSideMargin in. The preview is inset in its column the
// way the title row is in its unit (SGRPlayerHoldMargin, through Spotify's own side pins: H:|-0-[preview] and its
// trailing to the column's, 9.2.0), the column's own distance from the player's side counted as where its content
// starts. Only where the column runs from side to side: a column of a wide player has no title under it to start with.
static void holdPreviewMargin(UIView *preview, UIView *host) {
    UIView *column = preview.superview;
    if (!column || column.bounds.size.width <= 0 || !host.window) return;
    CGRect inHost = [host convertRect:column.bounds fromView:column];
    CGFloat left = CGRectGetMinX(inHost) - CGRectGetMinX(host.bounds), right = CGRectGetMaxX(host.bounds) - CGRectGetMaxX(inHost);
    BOOL across = left >= 0 && right >= 0 && left < SGRPlayerSideMargin && right < SGRPlayerSideMargin;
    BOOL rtl = column.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    SGRPlayerHoldMargin(preview, across ? (rtl ? right : left) : SGRPlayerSideMargin);
}

// The cover's own layout (PlayerArtwork.x sizes it there): the line follows where the cover now is. Only the
// player's covers, not the now playing bar's.
%group SGRLyricPreviewLayout
%hook _TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView
- (void)layoutSubviews {
    %orig;
    UIView *host = sg_host;
    if (host && [(UIView *)self isDescendantOfView:host]) placeLine();
}
%end

// Spotify's own lyric preview (9.1.90) gets its height when its lyrics arrive, after the cover's last pass: the line
// stands down there and then rather than on the player's next layout. While the line takes its place, its passes
// (and the older LyricsContainerView's) are where Spotify sets its alpha back, and where it is hidden again.
%hook _TtC25Lyrics_NPVElementsKitImpl24LyricsElementWrapperView
- (void)layoutSubviews {
    %orig;
    UIView *host = sg_host;
    if (host && [(UIView *)self isDescendantOfView:host]) placeLine();
}
%end

%hook _TtC22Lyrics_NPVContainerKit19LyricsContainerView
- (void)layoutSubviews {
    %orig;
    UIView *host = sg_host;
    if (host && [(UIView *)self isDescendantOfView:host]) placeLine();
}
%end
%end

// Spotify's own lyric preview takes no touch itself. A tap on it goes up to the covers' list, which selects the
// cell, and for that Spotify opens the cover's viewer: not through the tilt view's handleTap (PlayerGestures.x), so
// whatever the Full screen cover on tap switch says (issue #36; read from the call stack of the viewer going up,
// 9.2.0 in the simulator). A tap on a preview that shows opens the lyrics instead, as the line and the footer's
// glyph do. The recognizer cancels the touch, so the list never selects, and waits for the zones' double tap
// while Gestures is on.
@interface SGRPreviewTap : NSObject <UIGestureRecognizerDelegate>
@end

@implementation SGRPreviewTap
+ (instancetype)shared {
    static SGRPreviewTap *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [SGRPreviewTap new]; });
    return shared;
}

// A preview the line hid is not there to tap.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    UIView *preview = recognizer.view;
    CALayer *mask = objc_getAssociatedObject(preview, &kPreviewMaskKey);
    return !SGRPlayerLyricsOpen() && !(mask && preview.layer.mask == mask);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)other {
    return [other isKindOfClass:UITapGestureRecognizer.class] && ((UITapGestureRecognizer *)other).numberOfTapsRequired > 1;
}

- (void)tapped:(UITapGestureRecognizer *)recognizer {
    if (SGRPlayerLyricsOpen()) return;
    SGLog(@"redesign player: Spotify's lyric preview opens the lyrics");
    SGRPlayerOpenPreviewLyrics(recognizer.view);
}
@end

static void watchPreviewTaps(UIView *preview) {
    static char key;
    if (!preview.window || objc_getAssociatedObject(preview, &key)) return;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:SGRPreviewTap.shared action:@selector(tapped:)];
    tap.delegate = SGRPreviewTap.shared;
    [preview addGestureRecognizer:tap];
    objc_setAssociatedObject(preview, &key, tap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// These two are there whether the line is on or not (SGRLyricPreviewLayout is the line's): the preview shows when it
// is off.
%hook _TtC25Lyrics_NPVElementsKitImpl24LyricsElementWrapperView
- (void)didMoveToWindow {
    %orig;
    watchPreviewTaps((UIView *)self);
}
- (void)layoutSubviews {
    %orig;
    UIView *host = sg_host;
    if (host && [(UIView *)self isDescendantOfView:host]) holdPreviewMargin((UIView *)self, host);
}
%end

%hook _TtC22Lyrics_NPVContainerKit19LyricsContainerView
- (void)didMoveToWindow {
    %orig;
    watchPreviewTaps((UIView *)self);
}
- (void)layoutSubviews {
    %orig;
    UIView *host = sg_host;
    if (host && [(UIView *)self isDescendantOfView:host]) holdPreviewMargin((UIView *)self, host);
}
%end

%hook _TtC19NowPlaying_ViewImpl24NowPlayingViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    [objc_getAssociatedObject(((UIViewController *)self).viewIfLoaded, &kLineKey) setPlayerCovered:NO];
}
- (void)viewDidDisappear:(BOOL)animated {
    if (((UIViewController *)self).viewIfLoaded == sg_host) {
        if (SGRPlayerLyricLineOn()) {
            [objc_getAssociatedObject(sg_host, &kLineKey) setPlayerCovered:YES];
            flushChip(YES);
        }
        else { sg_host = nil; refreshEmptyStrip(nil); }
    }
    %orig;
}
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *host = ((UIViewController *)self).viewIfLoaded;
    if (!host.window) return;
    if (sg_host != host && SGRPlayerLyricLineOn()) flushChip(YES);
    sg_host = host;
    if (SGRPlayerLyricLineOn()) placeLine(); else refreshEmptyStrip(host);
}
%end

%hook _TtC20NowPlaying_ModesImpl20FloatingElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    sg_floating = (UIViewController *)self;
    if (SGRPlayerLyricLineOn()) { placeLine(); return; }
    refreshEmptyStrip(sg_host);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (SGRPlayerLyricLineOn()) {
        %init(SGRLyricPreviewLayout);
#if SG_DRIVER
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:nil
            usingBlock:^(NSNotification *note) { flushChip(YES); }];
#endif
    }
    %init;
    SGRequireClasses(@[
        @"_TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView",
        @"_TtC19NowPlaying_ViewImpl24NowPlayingViewController",
        @"_TtC20NowPlaying_ModesImpl20FloatingElementsUnit",
    ]);
}
