// The redesign's Apple Music style lyrics, always on: the line being sung lights up word by word, the
// rest dim and blur with distance. Lines two voices sing at once are lit together, an instrumental
// break holds three dots, and a line can show its pronunciation and its translation under it. The
// lines and the clock are Shared/Lyrics/Lyrics.h's.
//
// Only words the source timed are swept. A line timed by the line lights up whole as it starts, as
// Apple Music lights such a line, unless the Lyrics page's "Simulate word-by-word timing" asks for
// its estimated words to be swept; lyrics with no timing at all are shown as plain text, every line
// lit, nothing following the clock.
#import "Core/SGCore.h"
#import "SGRKaraokeView.h"
#import "LyricsText.h"
#import "LyricsLook.h"
#import "MeaningSheet.h"
#import "LyricCardPicker.h"
#import "LyricsTools.h"
#import "SongLanguage.h"
#import "SGRSingButton.h"
#import "Shared/Sing/Sing.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Shared/LyricsPiP/LyricsPiP.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"
#import "AutoTranslation.h"
#import "TranslationStatusView.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Player/PlayerEvents.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SpeedPitch.h"
#import "Shared/Haptics/Haptics.h"
#import "Redesigned/Kit/SGRGlass.h"
#import "Redesigned/Kit/SGRTokens.h"

// The size of the words and the room between lines are the Lyrics page's (LyricsLook.h). The lines stand the Music
// app's 32 pt in from the sides, as the player's title and bar do (Redesigned/Player/Player.h, SGRPlayerSideMargin).
static const CGFloat kMargin = 32, kRowTighten = 2;
static const CGFloat kDimAlpha = 0.3, kFillEdge = 22, kLift = 2.5, kDimScale = 0.97;
static const CGFloat kAnchor = 0.28;   // where the sung line rests, as a share of the height
// A tapped line flashes a plate behind it, the Music app's line highlight (white at 0.08, corners of 16, the
// plate 16 pt out from the line): it comes
// up at once and fades as the line glides to the anchor. It is the line's own box grown by the margin, as the
// Music app's is, so in a song for two voices it is as narrow as the line is.
static const CGFloat kTapPlateAlpha = 0.08, kTapPlateRadius = 16, kTapPlateOut = 16, kTapPlateOutY = 8;
static const NSTimeInterval kTapPlateHold = 0.12, kTapPlateFade = 0.45;
// A song for two voices sets each line in this share of the width, against its voice's side, as the Music
// app's are, so the two sides stand apart and a line's plate stops short of the far edge.
static const CGFloat kVocalGroupShare = 0.85;
static const CGFloat kEdgeFade = 0.1;  // the lines fade out over this share at the top and bottom
// The Music app's, scaled by the Lyrics page's blur: no line next to what is sung is sharp. A line coming up is
// blurred by one more than its distance and a line gone by by two more, up to kMaxBlur, the radius its lyrics view
// holds every line under; the steps were measured off its
// player (2026-11-25).
static const CGFloat kBlurAhead = 1, kBlurBehind = 2, kMaxBlur = 4;
// The (oh, aye) hanging under a line: smaller, a little dimmer, and just clear of it.
static const CGFloat kBackingScale = 0.62, kBackingAlpha = 0.8, kBackingGap = 4;
// The translation and the romanized line of a line being sung, brighter than a line waiting but never
// as bright as the words.
static const CGFloat kTranslationLit = 0.6;
// A cultural note waiting its line's turn, dimmer than a translation waiting: it is read once, not sung along to.
static const CGFloat kNoteDim = 0.22;
// The mark of a line Genius explains: a bubble after it for the artist's own word, a dotted underline
// for anyone else's.
static const CGFloat kBubbleSide = 22, kBubbleGap = 8, kBubbleGlyph = 11, kBubbleAlpha = 0.75, kBubbleReach = 14;
static const CGFloat kUnderlineDrop = 1, kUnderlineWidth = 2, kUnderlineAlpha = 0.35;
// The line naming the source, under the lyrics, which fade out above it and the buttons beside it. It
// wraps onto a second line rather than run under the buttons beside it, and a tap this far around it
// opens the pages it links to.
static const CGFloat kCreditSize = 12, kCreditGap = 12, kCreditSlop = 8;
// The button for the pronunciation and the translation, in the bottom leading corner as Apple Music
// has it, and the gap between it and the credit beside it. The translate glyph is half again as wide as the
// mic's across from it, so it is drawn smaller to weigh the same: 14 pt is about the mic's 17 pt in area.
static const CGFloat kExtrasSide = 44, kExtrasBottom = 12, kExtrasGlyph = 14;
// In the player, the Music app's: its translation button and Sing's slider are 38 pt across and stand 32 pt over the
// bottom of its lyrics view, as measured on its player.
static const CGFloat kPlayerExtrasSide = 38, kPlayerExtrasBottom = 32;
static char kExtrasGlassKey;
static const NSTimeInterval kRestyleFade = 0.3;
// Furigana at a third of the words' size, as print sets them over kanji; a cultural note at the size of a third line.
static const CGFloat kFuriganaShare = 0.36, kNoteShare = 0.48;
static const NSTimeInterval kAwakeAfterPause = 5;   // Keep screen on lets the screen lock this long into a pause   // the lines crossfading to a new style
static const NSTimeInterval kBrowseHold = 3;   // after scrolling by hand, how long until it follows the song again
static const double kFloatMinMs = 700, kFloatLeadMs = 80;   // a short word still floats up this slowly
// A word held this long starts to glow, and one held kGlowFullMs glows fully. The glow grows over the
// word and fades over kGlowFadeMs after it.
static const double kGlowFromMs = 900, kGlowFullMs = 2400, kGlowFadeMs = 450;
static const CGFloat kGlowRadius = 9, kGlowOpacity = 0.85;
// The room the sweep's mask leaves around the lit part of a word for its glow: past the widest shadow's
// visible tail, so the glow is cut nowhere but at the sweep's feathered edge (issue #68).
static const CGFloat kGlowReach = kGlowRadius * 4;
// How strongly the glow and the wave below are drawn, the Lyrics page's (LyricsLook.h), 1 being as here.
static CGFloat sgr_glowScale = 1, sgr_waveScale = 1;
// A word held long enough to glow lifts its letters one after another as the sweep reaches each, a wave
// running through it, as high as this share of the font for the word held longest: a letter starts up a
// little before the sweep's edge reaches its middle and is up over this share of the word's time. They come
// down with the glow once the word is sung, and the wave is left out under Reduce Motion.
static const CGFloat kWaveShare = 0.1;
static const double kWaveLead = 0.08, kWaveSpan = 0.3;
// A line lit whole: how long its words take to come up to full white, and to float up together.
static const NSTimeInterval kWholeFade = 0.35;
static const double kWholeRiseMs = 900;
static const double kClockSnapMs = 250, kClockPull = 0.08;
// After a tap seeks to a line, the clock holds at it until the player reports a position this near it,
// or for this long at the most: the player takes a few frames to report a seek.
static const double kSeekNearMs = 500;
static const CFTimeInterval kSeekWait = 1.5;
// Lines get views this far outside the visible part, in screen heights: half a screen above it
// and below, and a quarter more before a view is let go. Every view held is one more for the window
// to take in and let go when the lyrics come up; a line comes into view about once in three seconds,
// and a page flung by hand fills in at a few lines a frame.
static const CGFloat kSightBehind = 0.5, kSightAhead = 0.5, kSightSlack = 0.25;
static const NSTimeInterval kTransitionSlack = 0.05;   // after the player's animation, before the link is back

static NSString *const kBlurPath = @"filters.gaussianBlur.inputRadius";
// Two voices can sing at once, rarely more; past this many, the latest ones wait their turn.
enum { kMostSung = 6 };
// A pause in the singing this long is an instrumental break, and three dots hold its place: from the
// end of the last line sung before it to the start of the next, or from the top of the song to the
// first line. BiniLyrics' web player, which copies Apple Music's, draws them from seven seconds.
static const NSInteger kBreakMinMs = 7000;
// The dots' size and the room between them, as shares of the font, which is Apple Music's proportion.
static const CGFloat kDotShare = 0.5, kDotGapShare = 0.27;
// The break's name beside them, at a little under half the words' size.
static const CGFloat kBreakLabelShare = 0.42;
// Their timeline, Apple Music's as that player reads it off: in over 0.4 s, breathing between 85 % and
// 112 % of their size in eight second cycles, filling one after another, then swelling to 120 % and
// shrinking away in 0.35 s, which ends half a second before the next line starts so it has that long
// to move up into their place. A cycle is timed to end small, so the swell starts from the bottom.
// They wait a quarter of a second before they come, for the line before them to move up out of the way.
static const double kBreakWait = 0.25, kBreakIn = 0.4, kBreakFadeIn = 0.16, kBreathHalf = 4, kBreathLow = 0.85, kBreathHigh = 1.12;
static const double kBreakOut = 0.35, kBreakSwell = 1.2, kBreakSwellShare = 0.35, kBreakCollapse = 0.5;
// The dots' clock is set again only once it is this far from the song's, or the song stops or starts.
static const double kBreakSlack = 0.03;
// A position that has not moved for this long is a paused player, not two frames between readings.
static const CFTimeInterval kStillFor = 0.1;
// How long after the last thing set moving the page's link drops its rate: past the longest placement
// (0.3 s of delay and a 0.7 s spring) and a sung line's 0.9 s sink.
static const CFTimeInterval kCalmAfter = 1.5;

@interface CAFilter : NSObject
+ (instancetype)filterWithType:(NSString *)type;
@end

// Whether a line is written right to left, told by its first letter the way the Unicode bidi algorithm
// tells a paragraph's direction. Each line is asked on its own, since a song can mix scripts, and the
// phone's language has no say in it.
static BOOL readsRightToLeft(NSString *text) {
    static NSCharacterSet *rightToLeft, *leftToRight;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *scripts = [NSMutableCharacterSet new];
        [scripts addCharactersInRange:NSMakeRange(0x0590, 0x370)];    // Hebrew, Arabic, Syriac, Thaana, N'Ko and on
        [scripts addCharactersInRange:NSMakeRange(0xFB1D, 0x2E3)];    // Hebrew and Arabic presentation forms
        [scripts addCharactersInRange:NSMakeRange(0xFE70, 0x90)];     // Arabic presentation forms B
        [scripts addCharactersInRange:NSMakeRange(0x10800, 0x800)];   // the old scripts written right to left
        [scripts addCharactersInRange:NSMakeRange(0x1E800, 0x800)];   // Mende Kikakui and Adlam
        NSMutableCharacterSet *letters = [NSCharacterSet.letterCharacterSet mutableCopy];
        [letters formIntersectionWithCharacterSet:scripts.invertedSet];
        leftToRight = [letters copy];
        [scripts formIntersectionWithCharacterSet:NSCharacterSet.letterCharacterSet];
        rightToLeft = [scripts copy];
    });
    NSUInteger first = [text rangeOfCharacterFromSet:rightToLeft].location;
    return first != NSNotFound && first < [text rangeOfCharacterFromSet:leftToRight].location;
}

// Laid against the right edge: a line written right to left, or a second voice's written left to right.
static BOOL alignsRight(SGKaraokeLine *line) {
    return (line.align == SGKaraokeAlignTrailing) != readsRightToLeft(SGKaraokeLineText(line));
}

// A line's text as holding it offers it, nil for a line there is nothing to offer for: an empty one, or one
// holding only a break's mark, as an instrumental break's does.
static NSString *heldLineText(SGKaraokeLine *line) {
    NSString *text = SGKaraokeLineText(line);
    return [text rangeOfCharacterFromSet:NSCharacterSet.alphanumericCharacterSet].location == NSNotFound ? nil : text;
}

static UILabel *wordLabel(NSString *text, UIFont *font, UIColor *color, CGRect frame, BOOL rightToLeft) {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.text = text;
    label.font = font;
    label.textColor = color;
    if (!rightToLeft) return label;
    // A word of a line written right to left is set in the line's direction, so the punctuation at its
    // ends falls where the whole line would put it, a word of a left to right script among them too.
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.baseWritingDirection = NSWritingDirectionRightToLeft;
    label.attributedText = [[NSAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: font, NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: paragraph}];
    return label;
}

#pragma mark - a word

// The word twice: dim underneath, white on top behind a mask whose feathered edge slides across it,
// from the edge its script starts at.
@interface SGRKaraokeWordView : UIView
@property (nonatomic, readonly) SGKaraokeWord *word;
@property (nonatomic, readonly) UIView *lit;   // a label, or for a word that waves a view of its letters
@property (nonatomic) CGFloat offset;   // where the word starts along its line, rows laid end to end
// Lit with the rest of its line at once rather than swept, and floated up with it over riseStart to
// riseEnd, which are the word's own times until the sweep says otherwise.
@property (nonatomic) BOOL whole;
@property (nonatomic) double riseStart, riseEnd;
- (void)fillTo:(CGFloat)cursor;
// Lit for good, as plain lyrics are: no sweep will move, so the mask goes too.
- (void)showWhole;
- (void)floatAt:(double)ms;
- (double)nextMotionAt:(double)ms;
@property (nonatomic, readonly) UIFont *font;
- (void)settle;   // land and unglow at once
- (void)land;     // back down from its float
- (void)unglow;   // the glow off
- (void)applyDrawingStyle:(SGRLyricsDrawingStyle)style;
@end

@implementation SGRKaraokeWordView {
    CAGradientLayer *_fill;
    CGFloat _filled, _lift, _glow;
    BOOL _rightToLeft;
    // A word that waves: its letters, dim and lit, each letter's middle as a share of the word's width,
    // and how high each is lifted now.
    NSArray<UILabel *> *_dimLetters, *_litLetters;
    CGFloat *_letterAt, *_letterLift;
    CGFloat _waveHeight;
    SGRLyricsDrawingStyle _drawingStyle;
    UIColor *_styleAccent;
    CAGradientLayer *_ink;
    UIView *_inkMask;   // retains the glyph views whose layers mask the color field
}

// The word set letter by letter, each where the whole word would put it, in a view the word's size.
static UIView *lettersOf(NSArray<NSString *> *letters, NSArray<NSNumber *> *xs, UIFont *font, UIColor *color, CGSize size,
                         NSMutableArray<UILabel *> *made) {
    UIView *run = [[UIView alloc] initWithFrame:(CGRect){CGPointZero, size}];
    for (NSUInteger i = 0; i < letters.count; i++) {
        CGFloat x = xs[i].doubleValue, next = i + 1 < xs.count ? xs[i + 1].doubleValue : size.width;
        UILabel *label = wordLabel(letters[i], font, color, CGRectMake(x, 0, ceil(next - x) + 2, size.height), NO);
        [run addSubview:label];
        [made addObject:label];
    }
    return run;
}

// `waiting` and `sung`: how bright the word is before and as it is sung, kDimAlpha and 1 for the lyrics' own.
- (instancetype)initWithWord:(SGKaraokeWord *)word font:(UIFont *)font waiting:(CGFloat)waiting sung:(CGFloat)sung
                 rightToLeft:(BOOL)rightToLeft {
    CGSize size = [word.text sizeWithAttributes:@{NSFontAttributeName: font}];
    self = [super initWithFrame:CGRectMake(0, 0, ceil(size.width), ceil(font.lineHeight))];
    if (!self) return nil;
    _word = word;
    _font = font;
    _riseStart = word.start;
    _riseEnd = word.end;
    _rightToLeft = rightToLeft;
    // Only a word held long enough to glow waves, and only one written left to right: a script that joins
    // its letters, as Arabic does, cannot be set a letter at a time.
    NSMutableArray<NSString *> *letters = [NSMutableArray array];
    NSMutableArray<NSNumber *> *xs = [NSMutableArray array];
    if (word.end - word.start >= kGlowFromMs && !rightToLeft && !SGRReduceMotion()) {
        NSDictionary *attributes = @{NSFontAttributeName: font};
        [word.text enumerateSubstringsInRange:NSMakeRange(0, word.text.length) options:NSStringEnumerationByComposedCharacterSequences
                                   usingBlock:^(NSString *letter, NSRange range, NSRange enclosing, BOOL *stop) {
            [letters addObject:letter];
            [xs addObject:@([[word.text substringToIndex:range.location] sizeWithAttributes:attributes].width)];
        }];
    }
    // The sung word is drawn over the waiting one, which stays under it: over `waiting` it reads as
    // over + waiting × (1 - over), so it is set to whatever makes that `sung`.
    CGFloat over = sung >= 1 || waiting >= 1 ? 1 : MAX(0, (sung - waiting) / (1 - waiting));
    if (letters.count > 1) {
        NSMutableArray<UILabel *> *dim = [NSMutableArray array], *lit = [NSMutableArray array];
        [self addSubview:lettersOf(letters, xs, font, [UIColor colorWithWhite:1 alpha:waiting], self.bounds.size, dim)];
        _lit = lettersOf(letters, xs, font, [UIColor colorWithWhite:1 alpha:over], self.bounds.size, lit);
        _dimLetters = dim;
        _litLetters = lit;
        _letterAt = calloc(letters.count, sizeof(CGFloat));
        _letterLift = calloc(letters.count, sizeof(CGFloat));
        for (NSUInteger i = 0; i < letters.count; i++) {
            CGFloat next = i + 1 < xs.count ? xs[i + 1].doubleValue : size.width;
            _letterAt[i] = (xs[i].doubleValue + next) / 2 / MAX(size.width, 1);
        }
        _waveHeight = font.pointSize * kWaveShare;
    } else {
        [self addSubview:wordLabel(word.text, font, [UIColor colorWithWhite:1 alpha:waiting], self.bounds, rightToLeft)];
        _lit = wordLabel(word.text, font, [UIColor colorWithWhite:1 alpha:over], self.bounds, rightToLeft);
    }
    // Hidden until the line is sung: a masked layer is drawn offscreen every frame even when the
    // mask leaves nothing of it, and a song has hundreds of words waiting their turn.
    _lit.hidden = YES;
    [self addSubview:_lit];

    CGFloat width = self.bounds.size.width + 2 * kGlowReach + kFillEdge;
    _fill = [CAGradientLayer layer];
    _fill.colors = @[(id)UIColor.whiteColor.CGColor, (id)UIColor.whiteColor.CGColor, (id)UIColor.clearColor.CGColor];
    _fill.locations = @[@0, @((width - kFillEdge) / width), @1];
    _fill.startPoint = CGPointMake(rightToLeft ? 1 : 0, 0.5);
    _fill.endPoint = CGPointMake(rightToLeft ? 0 : 1, 0.5);
    _lit.layer.mask = _fill;
    _filled = NAN;
    [self fillTo:-CGFLOAT_MAX];
    return self;
}

- (void)dealloc {
    free(_letterAt);
    free(_letterLift);
}

// Preserve shaped text and writing direction, including the individual glyphs of a held word.
static void colorGlyphs(UIView *view, UIColor *color, BOOL outline) {
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        NSMutableAttributedString *text = label.attributedText
            ? [label.attributedText mutableCopy]
            : [[NSMutableAttributedString alloc] initWithString:label.text ?: @"" attributes:@{NSFontAttributeName: label.font}];
        NSRange range = NSMakeRange(0, text.length);
        if (outline) {
            [text addAttributes:@{NSStrokeWidthAttributeName: @3, NSStrokeColorAttributeName: label.textColor} range:range];
        } else {
            // The accent over each run keeps the run's own alpha, so a word waiting at half brightness
            // stays half lit when the style is applied. The runs are read from a copy: the string is
            // written as they are walked.
            CGFloat accent = CGColorGetAlpha(color.CGColor);
            NSAttributedString *before = [text copy];
            [before enumerateAttribute:NSForegroundColorAttributeName inRange:range options:0
                            usingBlock:^(id value, NSRange run, BOOL *stop) {
                UIColor *existing = [value isKindOfClass:UIColor.class] ? value : label.textColor;
                CGFloat alpha = existing ? CGColorGetAlpha(existing.CGColor) : 1;
                [text addAttribute:NSForegroundColorAttributeName value:[color colorWithAlphaComponent:alpha * accent] range:run];
            }];
        }
        label.attributedText = text;
    }
    for (UIView *child in view.subviews) colorGlyphs(child, color, outline);
}

- (void)applyDrawingStyle:(SGRLyricsDrawingStyle)style {
    if (style == SGRLyricsDrawingAppleMusic) return;   // original layer tree and drawing, untouched
    _drawingStyle = style;
    _styleAccent = SGRAccent();
    if (style == SGRLyricsDrawingOutline) {
        for (UIView *view in self.subviews) if (view != _lit) colorGlyphs(view, nil, YES);
        return;
    }
    if (style == SGRLyricsDrawingNeon) {
        colorGlyphs(_lit, _styleAccent, NO);
        return;
    }
    // Keep the original glyph views (and their letter-wave transforms) as a mask. The existing
    // feathered karaoke sweep still masks the outer view, independently of the ink inside it.
    UIView *glyphs = _lit;
    [glyphs removeFromSuperview];
    glyphs.layer.mask = nil;
    glyphs.hidden = NO;
    _lit = [[UIView alloc] initWithFrame:self.bounds];
    _lit.hidden = YES;
    _lit.layer.mask = _fill;
    [self addSubview:_lit];
    CGFloat pad = _font.pointSize * 0.3;
    _ink = [CAGradientLayer layer];
    _ink.frame = CGRectInset(self.bounds, -pad, -pad);
    _inkMask = [[UIView alloc] initWithFrame:_ink.bounds];
    glyphs.frame = CGRectOffset(self.bounds, pad, pad);
    [_inkMask addSubview:glyphs];
    _ink.mask = _inkMask.layer;
    UIColor *light = [_styleAccent colorWithAlphaComponent:1];
    if (style == SGRLyricsDrawingAurora) {
        CGFloat hue = 0, saturation = 0, brightness = 0, alpha = 0;
        [light getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha];
        UIColor *other = [UIColor colorWithHue:fmod(hue + 0.18, 1) saturation:MAX(0.45, saturation)
                                   brightness:MAX(0.85, brightness) alpha:1];
        _ink.colors = @[(id)light.CGColor, (id)UIColor.whiteColor.CGColor, (id)other.CGColor];
        _ink.startPoint = CGPointMake(0, 0);
        _ink.endPoint = CGPointMake(1, 1);
    } else {
        _ink.colors = @[(id)light.CGColor, (id)UIColor.whiteColor.CGColor, (id)light.CGColor];
        _ink.locations = @[@0, @0.5, @1];
        _ink.startPoint = CGPointMake(0, 0.5);
        _ink.endPoint = CGPointMake(1, 0.5);
    }
    [_lit.layer addSublayer:_ink];
}

// The cursor is in line units and the feathered edge is centered on it, so the edge runs on through
// the space into the next word instead of starting over at each one. Right to left, the mask is the
// same one turned around: white from the word's right edge, the feather `local` in from it. The white
// runs kGlowReach past the word on each side, and the edge follows the cursor that far past it, so a
// word's glow is cut only where the sweep has not reached yet.
- (void)fillTo:(CGFloat)cursor {
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    CGFloat local = MAX(-kFillEdge / 2, MIN(width + kGlowReach + kFillEdge / 2, cursor - _offset));
    if (local == _filled) return;
    _filled = local;
    CGFloat lit = width + 2 * kGlowReach;
    CGFloat left = _rightToLeft ? width - local - kFillEdge / 2 : local - kFillEdge / 2 - lit;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _fill.frame = CGRectMake(left, -kGlowReach, lit + kFillEdge, height + 2 * kGlowReach);
    [CATransaction commit];
}

// Filled to the end, the mask is white over the word and kGlowReach past it on every side, so the word is drawn the
// same without it, and without the offscreen pass a mask costs every frame for every word of a plain page in sight.
- (void)showWhole {
    _lit.hidden = NO;
    _lit.alpha = 1;
    [self fillTo:CGFLOAT_MAX];
    _lit.layer.mask = nil;
}

// Rises like a critically damped spring let go as the word starts: no jolt, a long soft landing.
// x = 5 at the end of the word is 96 % of the way up.
- (void)floatAt:(double)ms {
    // One clock for the whole sung run, including a paused song and a looping preview. No extra
    // display link, animation objects, colors or arrays are made on a frame.
    if (_drawingStyle == SGRLyricsDrawingShimmer && !SGRReduceMotion()) {
        // The band runs on one clock at 0.5 pt/ms, its position the word's place along the run taken off:
        // `across` is already the band's offset within the word, so every word sees it pass and a band
        // crossing into the next word lines up with it.
        CGFloat across = fmod(MAX(0, ms) * 0.5 - _offset, 1200) - 300;
        CGFloat width = MAX(1, _ink.bounds.size.width);
        CGFloat start = (across + _font.pointSize * 0.3) / width;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _ink.startPoint = CGPointMake(_rightToLeft ? 1 - start : start, 0.5);
        _ink.endPoint = CGPointMake(_rightToLeft ? 1 - start - 300 / width : start + 300 / width, 0.5);
        [CATransaction commit];
    }
    double x = MAX(0, ms - _riseStart + kFloatLeadMs) / MAX(_riseEnd - _riseStart, kFloatMinMs) * 5;
    CGFloat lift = kLift * (1 - (1 + x) * exp(-x));
    [self glowAt:ms];
    [self waveAt:ms];
    if (lift == _lift) return;
    _lift = lift;
    self.transform = CGAffineTransformMakeTranslation(0, -lift);
}

- (double)nextMotionAt:(double)ms {
    if (_drawingStyle == SGRLyricsDrawingShimmer && !SGRReduceMotion()) return ms;
    double begin = _riseStart - kFloatLeadMs;
    if (_litLetters && !_whole) begin = MIN(begin, _word.start - kWaveLead * (_word.end - _word.start));
    if (ms < begin) return begin;
    // The float is asymptotic, not finished at riseEnd. Wait for the actual final transform.
    if (_lift != kLift || (!_whole && ms < _word.end + kGlowFadeMs)) return ms;
    return INFINITY;
}

// How strongly a held word glows and waves: from a quarter for the shortest that does, to all of it.
static double heldStrength(double held) {
    return MIN(1, (held - kGlowFromMs) / (kGlowFullMs - kGlowFromMs) + 0.25);
}

// A held word glows, the more the longer it is held: white light around the lit part of it, since the
// sweep's mask cuts the shadow too, kGlowReach out from the lit part. Most words are too short to glow,
// and theirs is never drawn.
- (void)glowAt:(double)ms {
    double held = _word.end - _word.start;
    CGFloat glow = 0;
    if (held >= kGlowFromMs && !_whole && sgr_glowScale > 0) {
        double strength = heldStrength(held);
        double envelope = ms < _word.start ? 0
                        : ms <= _word.end ? (ms - _word.start) / held
                        : MAX(0, 1 - (ms - _word.end) / kGlowFadeMs);
        glow = round(strength * envelope * 50) / 50;   // steps of 2 %, so most frames change nothing
    }
    BOOL neon = _drawingStyle == SGRLyricsDrawingNeon;
    if (neon && ms >= _riseStart) glow = MAX(glow, 0.65);
    if (glow == _glow) return;
    _glow = glow;
    CALayer *layer = _lit.layer;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.shadowColor = (neon ? _styleAccent : UIColor.whiteColor).CGColor;
    layer.shadowOffset = CGSizeZero;
    layer.shadowRadius = kGlowRadius * (0.5 + glow / 2) * (0.75 + sgr_glowScale / 4);
    layer.shadowOpacity = MIN(1, kGlowOpacity * glow * sgr_glowScale);
    [CATransaction commit];
}

// Each letter comes up on a smoothstep as the sweep nears it and stays up while the word is held, so a
// crest runs through the word with the sweep; once it is sung they all come down as the glow fades.
- (void)waveAt:(double)ms {
    if (!_litLetters || _whole) return;
    double held = _word.end - _word.start, along = (ms - _word.start) / held;
    double fade = ms <= _word.end ? 1 : MAX(0, 1 - (ms - _word.end) / kGlowFadeMs);
    CGFloat height = _waveHeight * heldStrength(held) * fade * sgr_waveScale;
    for (NSUInteger i = 0; i < _litLetters.count; i++) {
        double p = MAX(0, MIN(1, (along - _letterAt[i] + kWaveLead) / kWaveSpan));
        CGFloat lift = round(height * p * p * (3 - 2 * p) * 4) / 4;   // quarter points, so most frames change nothing
        if (lift == _letterLift[i]) continue;
        _letterLift[i] = lift;
        CGAffineTransform up = CGAffineTransformMakeTranslation(0, -lift);
        _litLetters[i].transform = up;
        _dimLetters[i].transform = up;
    }
}

- (void)settle {
    [self land];
    [self unglow];
}

- (void)land {
    _lift = 0;
    self.transform = CGAffineTransformIdentity;
    for (NSUInteger i = 0; i < _litLetters.count; i++) {
        _letterLift[i] = 0;
        _litLetters[i].transform = CGAffineTransformIdentity;
        _dimLetters[i].transform = CGAffineTransformIdentity;
    }
}

- (void)unglow {
    _glow = 0;
    _lit.layer.shadowOpacity = 0;
}

@end

#pragma mark - how a line is set

// Which of a line's texts are shown and how big, from the Lyrics page's order of the three and the
// lyrics menu's switches: the first shown is set at the lyrics' own size, and the next two keep the
// sizes of their places whatever is hidden above them, so a translation stays the smallest with the
// pronunciation off. A song is laid out and measured by one of these, so a change of it is a new one.
@interface SGRKaraokeStyle : NSObject
@property (nonatomic) SGRLyricsDrawingStyle drawingStyle;
@property (nonatomic, readonly) NSArray<NSNumber *> *order;   // SGRLyricsText, largest first, shown ones only
@property (nonatomic, readonly) UIFont *lyrics, *pronunciation, *translation;   // nil for a text not shown
@property (nonatomic, readonly) SGRKaraokeStyle *backing;   // the backing row's: smaller, its translation read with the line's
@property (nonatomic, readonly) BOOL generatesReading;
@property (nonatomic) BOOL hangul, hiragana;
// Filled on the layout worker before publication; source words are immutable and shared by snapshots.
@property (nonatomic, copy) NSDictionary<NSArray *, SGLyricsPreparedExtras *> *extras;
// How bright the pronunciation's waiting words and a romanized line are, waiting and sung, and the same for the
// translation and a cultural note: the usual ones times the Text sizes page's brightness, never above white.
@property (nonatomic, readonly) CGFloat spokenDim, spokenLit, translationDim, translationLit, noteDim, noteLit;
@property (nonatomic, readonly) CGFloat spokenSung;   // the pronunciation's words as they are sung, white at 100% and above
@property (nonatomic) BOOL japanese;   // the song has kana, so its kanji are read the Japanese way
// Furigana over the kanji of a Japanese song's words, nil while the Lyrics page has it off or the song has
// no kana. Set at a third of the lyrics' size, in the room that much more leading gives each row.
@property (nonatomic, strong) UIFont *furigana;
// Under each line its cultural note, if it has one, in the translation's place's size, dimmer.
@property (nonatomic, strong) UIFont *note;
- (instancetype)initWithSize:(CGFloat)size order:(NSArray<NSNumber *> *)order pronunciation:(BOOL)pronunciation translation:(BOOL)translation
                   romanised:(BOOL)romanised;
// The furigana's and the cultural note's fonts at their usual sizes, after the lyrics' and the translation's looks.
- (UIFont *)furiganaAt:(CGFloat)points;
- (UIFont *)noteAt:(CGFloat)points;
@end

// The second and third place's sizes, as shares of the first: Apple Music's 20 and 16 under its 30.
static const CGFloat kSecondShare = 0.67, kThirdShare = 0.54;

// A size times the Text sizes page's share of it, the usual size left exactly as it was at 100%.
static CGFloat scaledPoints(CGFloat points, NSInteger scale) {
    return scale == 100 ? points : round(points * scale / 100.0);
}

// A brightness times the Text sizes page's share of it, never above white.
static CGFloat brightened(CGFloat alpha, NSInteger brightness) {
    return brightness == 100 ? alpha : MIN(1, alpha * brightness / 100.0);
}

// What hangs off a text (its romanized line, furigana, a cultural note) is set a step lighter than the text.
static UIFontWeight lighterWeight(NSInteger weight) {
    return weight <= 0 ? UIFontWeightRegular : weight == 1 ? UIFontWeightMedium : UIFontWeightSemibold;
}

@implementation SGRKaraokeStyle {
    UIFontWeight _lyricsWeight, _spokenWeight;
}

- (instancetype)initWithSize:(CGFloat)size order:(NSArray<NSNumber *> *)order pronunciation:(BOOL)pronunciation translation:(BOOL)translation
                   romanised:(BOOL)romanised {
    if (!(self = [super init])) return nil;
    SGRLyricsTextLook looks[3] = {SGRLyricsTextLookOf(SGRLyricsTextLyrics), SGRLyricsTextLookOf(SGRLyricsTextPronunciation),
                                  SGRLyricsTextLookOf(SGRLyricsTextTranslation)};
    _lyricsWeight = SGRLyricsTextFontWeight(looks[SGRLyricsTextLyrics].weight);
    _spokenWeight = SGRLyricsTextFontWeight(looks[SGRLyricsTextPronunciation].weight);
    _spokenDim = brightened(kDimAlpha, looks[SGRLyricsTextPronunciation].brightness);
    _spokenLit = brightened(kTranslationLit, looks[SGRLyricsTextPronunciation].brightness);
    _spokenSung = brightened(1, looks[SGRLyricsTextPronunciation].brightness);
    _translationDim = brightened(kDimAlpha, looks[SGRLyricsTextTranslation].brightness);
    _translationLit = brightened(kTranslationLit, looks[SGRLyricsTextTranslation].brightness);
    _noteDim = brightened(kNoteDim, looks[SGRLyricsTextTranslation].brightness);
    _noteLit = _translationLit;
    CGFloat sizes[3] = {size, round(size * kSecondShare), round(size * kThirdShare)};
    _generatesReading = romanised;
    NSMutableArray<NSNumber *> *shown = [NSMutableArray array];
    for (NSUInteger place = 0; place < order.count && place < 3; place++) {
        SGRLyricsText text = order[place].integerValue;
        if (text < SGRLyricsTextLyrics || text > SGRLyricsTextTranslation) continue;
        if ((text == SGRLyricsTextPronunciation && !pronunciation && !romanised) || (text == SGRLyricsTextTranslation && !translation)) continue;
        CGFloat points = scaledPoints(shown.count ? sizes[place] : size, looks[text].scale);
        UIFont *font = [UIFont systemFontOfSize:points weight:SGRLyricsTextFontWeight(looks[text].weight)];
        if (text == SGRLyricsTextLyrics) _lyrics = font;
        else if (text == SGRLyricsTextPronunciation) _pronunciation = font;
        else _translation = font;
        [shown addObject:@(text)];
    }
    if (!_lyrics) {   // an order without the lyrics in it is not one to trust
        _lyrics = [UIFont systemFontOfSize:scaledPoints(size, looks[SGRLyricsTextLyrics].scale) weight:_lyricsWeight];
        [shown insertObject:@(SGRLyricsTextLyrics) atIndex:0];
    }
    _order = shown;
    return self;
}

// Furigana over the lyrics and a cultural note under the translation, sized and weighted after the text they belong to.
- (UIFont *)furiganaAt:(CGFloat)points {
    SGRLyricsTextLook look = SGRLyricsTextLookOf(SGRLyricsTextLyrics);
    return [UIFont systemFontOfSize:round(scaledPoints(points, look.scale)) weight:lighterWeight(look.weight)];
}

- (UIFont *)noteAt:(CGFloat)points {
    SGRLyricsTextLook look = SGRLyricsTextLookOf(SGRLyricsTextTranslation);
    return [UIFont systemFontOfSize:round(scaledPoints(points, look.scale)) weight:lighterWeight(look.weight)];
}

- (SGRKaraokeStyle *)backing {
    SGRKaraokeStyle *backing = [SGRKaraokeStyle new];
    backing.drawingStyle = _drawingStyle;
    backing->_lyricsWeight = _lyricsWeight;
    backing->_spokenWeight = _spokenWeight;
    backing->_spokenDim = _spokenDim;
    backing->_spokenLit = _spokenLit;
    backing->_spokenSung = _spokenSung;
    backing->_translationDim = _translationDim;
    backing->_translationLit = _translationLit;
    backing->_noteDim = _noteDim;
    backing->_noteLit = _noteLit;
    backing.extras = _extras;
    backing->_lyrics = [UIFont systemFontOfSize:round(_lyrics.pointSize * kBackingScale) weight:_lyricsWeight];
    if (_pronunciation) backing->_pronunciation = [UIFont systemFontOfSize:round(_pronunciation.pointSize * kBackingScale) weight:_spokenWeight];
    NSMutableArray<NSNumber *> *order = [_order mutableCopy];
    [order removeObject:@(SGRLyricsTextTranslation)];
    backing->_order = order;
    return backing;
}

@end

#pragma mark - where a line's words go

// Between a row of words and the row spelling them out under it, between one such pair and the next,
// and between two texts of a line set apart.
static const CGFloat kPairTighten = 2, kPairGap = 4, kPartGap = 6;

// Where everything of a line goes, from its text alone: each word's frame and its place along the
// sweep, the translation's frame and the backing's top. The page lays every line of a song out with
// it off the main thread to stack them, and a line view lays itself out by it when it is made, so the
// two can never disagree about a height.
@interface SGRKaraokeLayout : NSObject
@property (nonatomic) BOOL right;
@property (nonatomic) CGFloat height;
@property (nonatomic, copy) NSArray<NSValue *> *lyricFrames, *spokenFrames;
@property (nonatomic, copy) NSArray<NSNumber *> *lyricOffsets, *spokenOffsets;
@property (nonatomic, copy) NSArray<SGKaraokeWord *> *spokenWords;
@property (nonatomic) CGRect translation;   // CGRectNull without one
@property (nonatomic) CGFloat backingTop;   // 0 without a backing row
@property (nonatomic) CGRect note;           // CGRectNull without one
@end

@implementation SGRKaraokeLayout
@end

// Whether the line has a kanji its furigana would read: only then does its row make room above it.
static BOOL hasKanji(SGKaraokeLine *line) {
    NSString *text = SGKaraokeLineText(line);
    return text.length && [text rangeOfString:@"\\p{Han}" options:NSRegularExpressionSearch].location != NSNotFound;
}

// A run of words set in rows as wide as the page: where each goes along its row, which row, and where
// it sits along the sweep, the rows laid end to end. A joined word follows the one before it flush:
// the scripts that do not space their words would otherwise read with a gap between every syllable.
// A word timed syllable by syllable is a run of one word and the joined ones after it, and a joined
// one that does not fit takes the whole run to the next row with it, so a word is never split; only
// a run that starts its row, or is wider than a row, is broken inside.
typedef struct {
    CGFloat x, width, offset;
    NSUInteger row;
} SGRPlace;

static NSUInteger flow(NSArray<SGKaraokeWord *> *words, UIFont *font, CGFloat width, SGRPlace *places) {
    NSDictionary *attributes = @{NSFontAttributeName: font};
    CGFloat space = ceil([@" " sizeWithAttributes:attributes].width), x = 0, offset = 0;
    NSUInteger row = 0;
    for (NSUInteger i = 0; i < words.count; i++) {
        CGFloat wide = ceil([words[i].text sizeWithAttributes:attributes].width);
        CGFloat lead = x > 0 && !words[i].joined ? space : 0;
        if (x > 0 && x + lead + wide > width) {
            NSUInteger first = i;
            while (first > 0 && words[first].joined) first--;
            CGFloat runWide = 0;
            for (NSUInteger k = first; k < words.count && (k == first || words[k].joined); k++) {
                runWide += ceil([words[k].text sizeWithAttributes:attributes].width);
            }
            if (words[i].joined && places[first].row == row && places[first].x > 0 && runWide <= width) {
                // The run restarts at the row's start, where a word takes no space before it.
                CGFloat from = places[first].x;
                for (NSUInteger k = first; k < i; k++) {
                    places[k].x -= from;
                    places[k].offset -= space;
                    places[k].row = row + 1;
                }
                x -= from;
                offset -= space;
                lead = 0;
            } else {
                x = lead = 0;
            }
            row++;
        }
        x += lead;
        offset += lead;
        places[i] = (SGRPlace){x, wide, offset, row};
        x += wide;
        offset += wide;
    }
    return words.count ? row + 1 : 0;
}

// A contextual reading has no character-by-character dictionary alignment. Divide it by the
// source's grapheme count, using cumulative boundaries so no reading grapheme is lost or repeated.
static NSString *readingFragment(NSString *reading, NSString *source, NSRange part) {
    __block NSUInteger count = 0, before = 0, through = 0;
    [source enumerateSubstringsInRange:NSMakeRange(0, source.length) options:NSStringEnumerationByComposedCharacterSequences
        usingBlock:^(NSString *substring, NSRange range, NSRange enclosing, BOOL *stop) {
            count++;
            if (NSMaxRange(range) <= part.location) before++;
            if (NSMaxRange(range) <= NSMaxRange(part)) through++;
        }];
    NSMutableArray<NSNumber *> *boundaries = [NSMutableArray arrayWithObject:@0];
    [reading enumerateSubstringsInRange:NSMakeRange(0, reading.length) options:NSStringEnumerationByComposedCharacterSequences
        usingBlock:^(NSString *substring, NSRange range, NSRange enclosing, BOOL *stop) {
            [boundaries addObject:@(NSMaxRange(range))];
        }];
    NSUInteger graphemes = boundaries.count - 1;
    NSUInteger from = count ? (NSUInteger)round((double)graphemes * before / count) : 0;
    NSUInteger until = count ? (NSUInteger)round((double)graphemes * through / count) : graphemes;
    return [reading substringWithRange:NSMakeRange(boundaries[from].unsignedIntegerValue,
        boundaries[until].unsignedIntegerValue - boundaries[from].unsignedIntegerValue)];
}

// flow remains the owner of wrapping, including joined groups. Only a generated reading whose
// source crosses those rows is split; provider readings retain their timestamp-based alignment.
static NSArray<SGKaraokeWord *> *readingsForRows(SGKaraokeLine *line, UIFont *font, CGFloat width,
    NSArray<SGKaraokeWord *> *spoken, NSArray<NSValue *> *wordRanges, NSArray<NSValue *> **readingRanges) {
    SGRPlace *places = calloc(line.words.count + 1, sizeof(SGRPlace));
    flow(line.words, font, width, places);
    NSString *text = SGKaraokeLineText(line);
    NSMutableArray<SGKaraokeWord *> *words = [NSMutableArray array];
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    BOOL split = NO;
    for (NSUInteger j = 0; j < spoken.count; j++) {
        NSRange source = (*readingRanges)[j].rangeValue;
        NSMutableArray<NSValue *> *fragments = [NSMutableArray array];
        NSUInteger row = NSNotFound;
        for (NSUInteger i = 0; i < line.words.count; i++) {
            NSRange overlap = NSIntersectionRange(source, wordRanges[i].rangeValue);
            if (!overlap.length) continue;
            if (row == places[i].row) {
                fragments[fragments.count - 1] = [NSValue valueWithRange:NSUnionRange(fragments.lastObject.rangeValue, overlap)];
            } else {
                [fragments addObject:[NSValue valueWithRange:overlap]];
                row = places[i].row;
            }
        }
        if (fragments.count <= 1) {
            [words addObject:spoken[j]];
            [ranges addObject:(*readingRanges)[j]];
            continue;
        }
        split = YES;
        BOOL first = YES;
        for (NSUInteger k = 0; k < fragments.count; k++) {
            // Include separators between source words in exactly one fragment.
            NSUInteger from = k ? fragments[k].rangeValue.location : source.location;
            NSUInteger until = k + 1 < fragments.count ? fragments[k + 1].rangeValue.location : NSMaxRange(source);
            NSString *piece = readingFragment(spoken[j].text, [text substringWithRange:source],
                NSMakeRange(from - source.location, until - from));
            if (!piece.length) continue;
            SGKaraokeWord *word = [SGKaraokeWord new];
            word.text = piece;
            // These are existing source-word clocks, not invented subdivisions of a word.
            word.start = NSIntegerMax;
            word.end = 0;
            for (NSUInteger i = 0; i < line.words.count; i++) {
                if (!NSIntersectionRange(NSMakeRange(from, until - from), wordRanges[i].rangeValue).length) continue;
                word.start = MIN(word.start, line.words[i].start);
                word.end = MAX(word.end, line.words[i].end);
            }
            word.joined = first ? spoken[j].joined : YES;
            first = NO;
            [words addObject:word];
            [ranges addObject:[NSValue valueWithRange:NSMakeRange(from, until - from)]];
        }
    }
    free(places);
    if (!split) return spoken;
    *readingRanges = ranges;
    return words;
}

// Written right to left, rows are laid out left to right and turned around, so the first word is at
// the right edge and each row runs leftwards from it. Then each group of rows goes against the line's
// edge, a second voice's against the far one, as Apple Music sets the two sides of a duet apart; a
// group too wide to fit stays where its first word put it.
static void settle(CGRect *frames, NSUInteger *groups, NSUInteger count, NSUInteger groupCount, CGFloat width, BOOL rightToLeft, BOOL right) {
    if (rightToLeft) {
        for (NSUInteger i = 0; i < count; i++) frames[i].origin.x = width - CGRectGetMaxX(frames[i]);
    }
    for (NSUInteger g = 0; g < groupCount; g++) {
        CGRect extent = CGRectNull;
        for (NSUInteger i = 0; i < count; i++) {
            if (groups[i] == g) extent = CGRectUnion(extent, frames[i]);
        }
        if (CGRectIsNull(extent)) continue;
        CGFloat shift = right ? width - CGRectGetMaxX(extent) : -CGRectGetMinX(extent);
        if (right ? shift <= 0 : shift >= 0) continue;
        for (NSUInteger i = 0; i < count; i++) {
            if (groups[i] == g) frames[i].origin.x += shift;
        }
    }
}

static NSArray<NSValue *> *boxedFrames(CGRect *frames, NSUInteger count) {
    NSMutableArray<NSValue *> *boxed = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) [boxed addObject:[NSValue valueWithCGRect:frames[i]]];
    return boxed;
}

static NSArray<NSNumber *> *offsetsOf(SGRPlace *places, NSUInteger count) {
    NSMutableArray<NSNumber *> *offsets = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) [offsets addObject:@(places[i].offset)];
    return offsets;
}

// A text of words on its own, from `top`; returns where it ends.
static CGFloat layRun(NSArray<SGKaraokeWord *> *words, UIFont *font, CGFloat width, BOOL right, CGFloat top,
                      NSArray<NSValue *> **frames, NSArray<NSNumber *> **offsets, CGFloat ruby) {
    NSUInteger count = words.count;
    SGRPlace *places = calloc(count + 1, sizeof(SGRPlace));
    CGRect *rects = calloc(count + 1, sizeof(CGRect));
    NSUInteger *groups = calloc(count + 1, sizeof(NSUInteger));
    NSUInteger rows = flow(words, font, width, places);
    // Furigana sit in room above each row of words: the row is that much taller, the words that much lower in it.
    CGFloat row = ceil(font.lineHeight) - kRowTighten + ruby, high = ceil(font.lineHeight);
    for (NSUInteger i = 0; i < count; i++) {
        rects[i] = CGRectMake(places[i].x, top + ruby + places[i].row * row, places[i].width, high);
        groups[i] = places[i].row;
    }
    NSMutableString *text = [NSMutableString string];
    for (SGKaraokeWord *word in words) [text appendString:word.text];
    settle(rects, groups, count, rows, width, readsRightToLeft(text), right);
    *frames = boxedFrames(rects, count);
    *offsets = offsetsOf(places, count);
    free(places);
    free(rects);
    free(groups);
    return top + ruby + (rows ? rows - 1 : 0) * row + high;
}

// Two texts of words where the second spells out the first, or the first the second: each row of the
// leading one with the other's words under it, each under the word it starts with, as Apple Music sets
// its pronunciation, so a syllable reads under the syllable it sounds. Returns where the pair ends.
// leadRuby and underRuby: room for furigana above each row of the lead, or above each row set under it.
static CGFloat layPair(NSArray<SGKaraokeWord *> *lead, UIFont *leadFont, NSArray<SGKaraokeWord *> *under, UIFont *underFont,
                       CGFloat width, BOOL right, CGFloat top, NSArray<NSValue *> **leadFrames, NSArray<NSNumber *> **leadOffsets,
                       NSArray<NSValue *> **underFrames, NSArray<NSNumber *> **underOffsets, CGFloat leadRuby, CGFloat underRuby,
                       NSArray<NSValue *> *leadRanges, NSArray<NSValue *> *underRanges, BOOL underFirst) {
    NSUInteger leads = lead.count, unders = under.count, count = leads + unders;
    SGRPlace *places = calloc(count + 1, sizeof(SGRPlace));
    CGRect *rects = calloc(count + 1, sizeof(CGRect));
    NSUInteger *groups = calloc(count + 1, sizeof(NSUInteger));
    NSUInteger rows = flow(lead, leadFont, width, places);
    flow(under, underFont, width, places + leads);   // for their places along their own sweep
    // Generated readings retain source spans even when every clock is zero. Provider readings,
    // which have no source ranges, retain their timestamp-based alignment.
    NSUInteger *matched = calloc(unders + 1, sizeof(NSUInteger));
    for (NSUInteger j = 0, i = 0; j < unders; j++) {
        if (leadRanges && underRanges) {
            while (i + 1 < leads && NSMaxRange(leadRanges[i].rangeValue) <= underRanges[j].rangeValue.location) i++;
        } else {
            while (i + 1 < leads && lead[i + 1].start <= under[j].start) i++;
        }
        matched[j] = i;
    }
    CGFloat leadRow = ceil(leadFont.lineHeight) - kRowTighten, leadHigh = ceil(leadFont.lineHeight);
    CGFloat underRow = ceil(underFont.lineHeight) - kRowTighten + underRuby, underHigh = ceil(underFont.lineHeight);
    CGFloat space = ceil([@" " sizeWithAttributes:@{NSFontAttributeName: underFont}].width);
    CGFloat y = top, bottom = top;
    NSUInteger j = 0;
    for (NSUInteger r = 0; r < rows; r++) {
        CGFloat rowTop = y;
        y += leadRuby;
        for (NSUInteger i = 0; i < leads; i++) {
            if (places[i].row != r) continue;
            rects[i] = CGRectMake(places[i].x, y, places[i].width, leadHigh);
            groups[i] = r;
        }
        bottom = y + leadHigh;
        // Under the row, each word at the start of its own, pushed along past the one before it, and the
        // pieces of one word flush together, the way the row above has them. A row spelled out wider than
        // it is written, as Korean is, cannot keep to its words and still fit: it is set as plain words
        // from the edge instead, in as many rows as it takes.
        NSUInteger from = j, until = j;
        while (until < unders && places[matched[until]].row == r) until++;
        CGFloat underTop = y + leadHigh - kPairTighten + underRuby, reached = 0;
        BOOL fits = YES;
        for (NSUInteger k = from; k < until && fits; k++) {
            BOOL flush = k > from && under[k].joined;
            CGFloat x = flush ? reached : MAX(places[matched[k]].x, reached + (reached > 0 ? space : 0));
            rects[leads + k] = CGRectMake(x, underTop, places[leads + k].width, underHigh);
            reached = x + places[leads + k].width;
            fits = reached <= width;
        }
        NSUInteger subRow = 0;
        if (!fits) {
            reached = 0;
            for (NSUInteger k = from; k < until; k++) {
                CGFloat wide = places[leads + k].width, lead = reached > 0 && !under[k].joined ? space : 0;
                if (reached > 0 && reached + lead + wide > width) {
                    subRow++;
                    reached = lead = 0;
                }
                rects[leads + k] = CGRectMake(reached + lead, underTop + subRow * underRow, wide, underHigh);
                reached += lead + wide;
            }
        }
        for (NSUInteger k = from; k < until; k++) groups[leads + k] = r;
        j = until;
        BOOL any = until > from;
        if (any) bottom = underTop + subRow * underRow + underHigh;
        // A fragmented generated reading can be the first visible role, but its source rows
        // still own the fragments. Exchange the two blocks inside each row, not their wrapping.
        if (underFirst && any) {
            CGFloat underHeight = bottom - underTop;
            for (NSUInteger k = from; k < until; k++) rects[leads + k].origin.y -= underTop - rowTop;
            for (NSUInteger i = 0; i < leads; i++) {
                if (places[i].row == r) rects[i].origin.y = rowTop + underHeight - kPairTighten + leadRuby;
            }
            bottom = rowTop + underHeight - kPairTighten + leadRuby + leadHigh;
        }
        y = any ? bottom + kPairGap : y + leadRow;
    }
    NSMutableString *text = [NSMutableString string];
    for (SGKaraokeWord *word in lead) [text appendString:word.text];
    settle(rects, groups, count, rows, width, readsRightToLeft(text), right);
    *leadFrames = boxedFrames(rects, leads);
    *underFrames = boxedFrames(rects + leads, unders);
    *leadOffsets = offsetsOf(places, leads);
    *underOffsets = offsetsOf(places + leads, unders);
    free(places);
    free(rects);
    free(groups);
    free(matched);
    return bottom;
}

// A text set as a block, wrapping as a label does, from `top`.
static CGRect blockFrame(NSString *text, UIFont *font, CGFloat width, CGFloat top) {
    CGRect bounds = [text boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin
                                    attributes:@{NSFontAttributeName: font} context:nil];
    return CGRectMake(0, top, width, ceil(bounds.size.height));
}

// The texts a line has, in the style's order, the lyrics and their pronunciation set as a pair where
// the order has them side by side, and the backing row after that. `right` is the side a backing
// row keeps to, its line's; -1 for a line of its own, which takes its side from its voice and script.
static SGRKaraokeLayout *layOut(SGKaraokeLine *line, CGFloat width, SGRKaraokeStyle *style, NSInteger right) {
    SGRKaraokeLayout *layout = [SGRKaraokeLayout new];
    layout.right = right >= 0 ? right : alignsRight(line);
    layout.translation = layout.note = CGRectNull;
    SGLyricsPreparedExtras *extras = line.words.count ? style.extras[line.words] : nil;
    SGKaraokeLine *pronunciation = line.pronunciation ?: extras.pronunciation;
    NSArray *wordRanges = line.pronunciation ? nil : extras.wordRanges;
    NSArray *readingRanges = line.pronunciation ? nil : extras.sourceRanges;
    NSArray<SGKaraokeWord *> *spoken = style.pronunciation ? pronunciation.words : nil;
    NSString *translation = style.translation ? line.translation : nil;
    // A translator hands back a line already in the language as it was; the line says it once. It stays
    // translated, so it is not asked again.
    NSString *lineText = translation.length ? SGKaraokeLineText(line) : nil;
    if (translation.length && [SGLyricsBareText(translation) isEqualToString:SGLyricsBareText(lineText)]) translation = nil;
    NSMutableArray<NSNumber *> *parts = [NSMutableArray array];
    for (NSNumber *text in style.order) {
        if (text.integerValue == SGRLyricsTextPronunciation && !spoken.count) continue;
        if (text.integerValue == SGRLyricsTextTranslation && !translation.length) continue;
        [parts addObject:text];
    }
    NSArray<NSValue *> *frames;
    NSArray<NSNumber *> *offsets;
    CGFloat y = 0;
    for (NSUInteger p = 0; p < parts.count; p++) {
        SGRLyricsText text = parts[p].integerValue;
        if (p > 0) y += kPartGap;
        if (text == SGRLyricsTextTranslation) {
            layout.translation = blockFrame(translation, style.translation, width, y);
            y = CGRectGetMaxY(layout.translation);
            continue;
        }
        BOOL lyrics = text == SGRLyricsTextLyrics;
        BOOL paired = p + 1 < parts.count && parts[p + 1].integerValue != SGRLyricsTextTranslation;
        if (paired) {
            NSArray<NSValue *> *pairedFrames;
            NSArray<NSNumber *> *pairedOffsets;
            NSArray<SGKaraokeWord *> *unfragmented = spoken;
            if (wordRanges && readingRanges)
                spoken = readingsForRows(line, style.lyrics, width, spoken, wordRanges, &readingRanges);
            BOOL lyricFlow = lyrics || spoken != unfragmented;
            // The lyrics' rows make room for furigana above them, whichever of the two leads.
            CGFloat ruby = style.furigana && hasKanji(line) ? ceil(style.furigana.lineHeight) : 0;
            y = layPair(lyricFlow ? line.words : spoken, lyricFlow ? style.lyrics : style.pronunciation,
                        lyricFlow ? spoken : line.words, lyricFlow ? style.pronunciation : style.lyrics,
                        width, layout.right, y, &frames, &offsets, &pairedFrames, &pairedOffsets, lyricFlow ? ruby : 0, lyricFlow ? 0 : ruby,
                        lyricFlow ? wordRanges : readingRanges, lyricFlow ? readingRanges : wordRanges, !lyrics && lyricFlow);
            layout.lyricFrames = lyricFlow ? frames : pairedFrames;
            layout.lyricOffsets = lyricFlow ? offsets : pairedOffsets;
            layout.spokenFrames = lyricFlow ? pairedFrames : frames;
            layout.spokenOffsets = lyricFlow ? pairedOffsets : offsets;
            p++;
            lyrics = YES;
        } else {
            y = layRun(lyrics ? line.words : spoken, lyrics ? style.lyrics : style.pronunciation, width, layout.right, y, &frames, &offsets,
                       lyrics && style.furigana && hasKanji(line) ? ceil(style.furigana.lineHeight) : 0);
            if (lyrics) {
                layout.lyricFrames = frames;
                layout.lyricOffsets = offsets;
            } else {
                layout.spokenFrames = frames;
                layout.spokenOffsets = offsets;
            }
        }
        if (lyrics && right < 0 && line.backing.words.count) {
            layout.backingTop = y + kBackingGap;
            y = layout.backingTop + layOut(line.backing, width, style.backing, layout.right).height;
        }
    }
    layout.spokenWords = spoken;
    // A cultural note goes last, under everything the line shows, and only for a line of its own.
    if (right < 0 && style.note && line.note.length) {
        layout.note = blockFrame(line.note, style.note, width, y + kPartGap);
        y = CGRectGetMaxY(layout.note);
    }
    layout.height = y;
    return layout;
}

// Where each line starts in the stack, from the heights alone. Measuring text is safe off the main
// thread, and a song's worth of it is kept off it: the first card of a track lays out while the
// player is opening, and a frame that measured every line then was a frame the animation lost.
// Where each line starts in the stack, and one more: where the stack ends, which the credit follows.
// Taken on main before dispatch: translators and AI results can replace these fields while text is
// measured. Words are immutable once built; the line objects, including their attached runs, are not.
static SGKaraokeLine *layoutSnapshot(SGKaraokeLine *line) {
    if (!line) return nil;
    SGKaraokeLine *copy = [line copy];
    copy.backing = layoutSnapshot(line.backing);
    copy.pronunciation = layoutSnapshot(line.pronunciation);
    return copy;
}

static NSArray<SGKaraokeLine *> *layoutSnapshots(NSArray<SGKaraokeLine *> *lines) {
    NSMutableArray<SGKaraokeLine *> *copies = [NSMutableArray arrayWithCapacity:lines.count];
    for (SGKaraokeLine *line in lines) [copies addObject:layoutSnapshot(line)];
    return copies;
}

// Keeper revisions can remove or replace provider text as well as add it. Compare the
// displayed translation strings, not array identity or whether either song has a translation.
static BOOL translationsDiffer(NSArray<SGKaraokeLine *> *before, NSArray<SGKaraokeLine *> *after) {
    for (NSUInteger i = 0; i < before.count; i++) {
        if (![(before[i].translation ?: @"") isEqualToString:(after[i].translation ?: @"")]) return YES;
    }
    return NO;
}

static BOOL samePresentedLine(SGKaraokeLine *a, SGKaraokeLine *b) {
    if (a == b) return YES;
    if (!a || !b || a.start != b.start || a.end != b.end || a.timing != b.timing ||
        a.align != b.align || a.translationMade != b.translationMade || a.pronunciationMade != b.pronunciationMade ||
        ![(a.translation ?: @"") isEqualToString:b.translation ?: @""] ||
        ![(a.translationLanguage ?: @"") isEqualToString:b.translationLanguage ?: @""] ||
        ![(a.note ?: @"") isEqualToString:b.note ?: @""] || a.words.count != b.words.count) return NO;
    for (NSUInteger i = 0; i < a.words.count; i++) {
        SGKaraokeWord *left = a.words[i], *right = b.words[i];
        if (left.start != right.start || left.end != right.end || left.joined != right.joined ||
            ![(left.text ?: @"") isEqualToString:right.text ?: @""]) return NO;
    }
    return samePresentedLine(a.backing, b.backing) && samePresentedLine(a.pronunciation, b.pronunciation);
}

static BOOL samePresentedLines(NSArray<SGKaraokeLine *> *a, NSArray<SGKaraokeLine *> *b) {
    if (a.count != b.count) return NO;
    for (NSUInteger i = 0; i < a.count; i++) if (!samePresentedLine(a[i], b[i])) return NO;
    return YES;
}

static NSArray<NSNumber *> *topsOf(NSArray<SGKaraokeLine *> *lines, CGFloat width, SGRKaraokeStyle *style, CGFloat gap) {
    NSMutableDictionary *extras = [NSMutableDictionary dictionary];
    for (SGKaraokeLine *line in lines) {
        for (SGKaraokeLine *run in line.backing ? @[line, line.backing] : @[line]) {
            if (!run.words.count) continue;
            extras[run.words] = SGLyricsPrepareExtras(run, style.japanese, style.hangul, style.hiragana,
                style.generatesReading && !run.pronunciation, style.furigana != nil);
        }
    }
    style.extras = extras;
    NSMutableArray<NSNumber *> *tops = [NSMutableArray arrayWithCapacity:lines.count + 1];
    CGFloat top = 0;
    for (SGKaraokeLine *line in lines) {
        [tops addObject:@(top)];
        top += layOut(line, width, style, -1).height + gap;
    }
    [tops addObject:@(top)];
    return tops;
}

#pragma mark - a sweep

typedef struct {
    double ms, x, slope;
} SGSweepKnot;

// One run of words lit by one sweep: a line's own, or its pronunciation's, each timed by its own words.
// A whole one lights every word of the run at once from `start`, for a run whose words are not timed.
@interface SGRKaraokeSweep : NSObject
@property (nonatomic, readonly) NSArray<SGRKaraokeWordView *> *words;
- (instancetype)initWithWords:(NSArray<SGRKaraokeWordView *> *)words wholeFrom:(double)start;
- (void)showTime:(double)ms;
@end

@implementation SGRKaraokeSweep {
    SGSweepKnot *_knots;
    NSUInteger _knotCount;
    BOOL _whole;
}

// start: NAN to sweep the words by their own times.
- (instancetype)initWithWords:(NSArray<SGRKaraokeWordView *> *)words wholeFrom:(double)start {
    if (!(self = [super init])) return nil;
    _words = words;
    _whole = !isnan(start);
    if (_whole) {
        for (SGRKaraokeWordView *word in words) {
            word.whole = YES;
            word.riseStart = start;
            word.riseEnd = start + kWholeRiseMs;
        }
        return self;
    }
    [self buildSweep];
    return self;
}

- (void)dealloc {
    free(_knots);
}

static double secant(SGSweepKnot *knots, NSUInteger i) {
    return (knots[i + 1].x - knots[i].x) / (knots[i + 1].ms - knots[i].ms);
}

// The fill cursor reaches each word's left edge as the word starts and clears the last word as it
// ends, on a monotone cubic through those points, so the pace changes between words without a kink.
- (void)buildSweep {
    _knots = calloc(_words.count + 1, sizeof(SGSweepKnot));
    if (!_words.count) return;
    for (NSUInteger i = 0; i <= _words.count; i++) {
        SGRKaraokeWordView *word = _words[MIN(i, _words.count - 1)];
        double ms = i < _words.count ? word.word.start : word.word.end;
        double x = i == 0 ? -kFillEdge / 2 : i < _words.count ? word.offset : word.offset + word.bounds.size.width + kFillEdge / 2;
        if (_knotCount && ms <= _knots[_knotCount - 1].ms) {
            _knots[_knotCount - 1].x = x;
            continue;
        }
        _knots[_knotCount++] = (SGSweepKnot){ms, x, 0};
    }
    // Fritsch-Carlson slopes: capped so the cursor never runs backwards or overshoots a word.
    for (NSUInteger k = 0; k < _knotCount; k++) {
        BOOL first = k == 0, last = k + 1 == _knotCount;
        if (first && last) break;
        if (first || last) {
            _knots[k].slope = secant(_knots, first ? 0 : k - 1);
            continue;
        }
        double before = secant(_knots, k - 1), after = secant(_knots, k);
        double h0 = _knots[k].ms - _knots[k - 1].ms, h1 = _knots[k + 1].ms - _knots[k].ms;
        _knots[k].slope = MIN(MIN(2 * before, 2 * after), (before * h1 + after * h0) / (h0 + h1));
    }
}

- (CGFloat)cursorAt:(double)ms {
    if (!_knotCount) return -CGFLOAT_MAX;
    if (ms <= _knots[0].ms) return _knots[0].x;
    if (_knotCount == 1 || ms >= _knots[_knotCount - 1].ms) return _knots[_knotCount - 1].x;
    NSUInteger k = 0;
    while (ms >= _knots[k + 1].ms) k++;
    SGSweepKnot a = _knots[k], b = _knots[k + 1];
    double h = b.ms - a.ms, u = (ms - a.ms) / h, u2 = u * u, u3 = u2 * u;
    return (2 * u3 - 3 * u2 + 1) * a.x + (u3 - 2 * u2 + u) * h * a.slope
         + (3 * u2 - 2 * u3) * b.x + (u3 - u2) * h * b.slope;
}

- (void)showTime:(double)ms {
    // A whole run is only ever shown while its line is sung, so it is lit throughout.
    CGFloat cursor = _whole ? CGFLOAT_MAX : [self cursorAt:ms];
    for (SGRKaraokeWordView *word in _words) {
        [word fillTo:cursor];
        [word floatAt:ms];
    }
}

- (double)nextMotionAt:(double)ms {
    double next = INFINITY;
    if (_knotCount > 1 && ms < _knots[_knotCount - 1].ms) {
        next = MAX(ms, _knots[0].ms);   // the cubic also moves *between* word clocks
    }
    for (SGRKaraokeWordView *word in _words) {
        if (next == ms) break;
        next = MIN(next, [word nextMotionAt:ms]);
        if (_whole) break;   // same float, drawing style and start for the whole run
    }
    return next;
}

@end

#pragma mark - a line

@interface SGRKaraokeLineView : UIView
@property (nonatomic, readonly) SGKaraokeLine *line;
// Laid against the right edge: a line written right to left, or a second voice's written left to
// right. A backing row keeps to the edge of the line it hangs under, whatever script each is in.
@property (nonatomic, readonly) BOOL right;
@property (nonatomic) BOOL active;
@property (nonatomic, copy) BOOL (^activate)(void);
// What holding the line offers, as VoiceOver's own actions: Copy line, Share line and Share as card, and Meaning
// where the page found one. Nil until the page hands them over; a backing row, and a preview, get none.
@property (nonatomic, copy) BOOL (^copyText)(void);
@property (nonatomic, copy) BOOL (^shareText)(void);
@property (nonatomic, copy) BOOL (^shareCard)(void);
@property (nonatomic) CGFloat blur;
// under: the line a backing row hangs under, nil for a line of its own. sweepsEstimates: the words of a
// line timed only by the line are swept on their estimated times, rather than lit whole.
- (instancetype)initWithLine:(SGKaraokeLine *)line width:(CGFloat)width style:(SGRKaraokeStyle *)style under:(SGRKaraokeLineView *)under
                     blurred:(BOOL)blurred sweepsEstimates:(BOOL)sweepsEstimates;
- (void)showTime:(double)ms;
// Every word lit and left so, for lyrics with no timing: nothing is sung, so nothing is dim.
- (void)showPlain;
- (void)markMeaning:(NSArray<SGLyricsMeaning *> *)meanings;
// Where the bubble can be tapped, in the line's own space; CGRectNull without one.
@property (nonatomic, readonly) CGRect bubbleTarget;
@end


@implementation SGRKaraokeLineView {
    NSArray<SGRKaraokeSweep *> *_sweeps;   // the line's words, then their pronunciation's where shown
    NSArray<SGRKaraokeWordView *> *_words;   // every word of both
    NSArray<SGRKaraokeWordView *> *_lyricWords;
    UIImageView *_bubble;
    CAShapeLayer *_underline;
    UILabel *_translation, *_note;
    NSArray<UILabel *> *_furigana;   // the readings over the line's kanji, lit with the line
    NSUInteger _generation;
    SGRKaraokeLineView *_backing;
    NSArray<UIAccessibilityCustomAction *> *_meaningActions;   // VoiceOver's Meaning, while the line has one
    // How bright the texts set apart are, waiting and sung, from the style.
    CGFloat _translationDim, _translationLit, _spokenDim, _spokenLit, _noteDim, _noteLit;
    BOOL _blurs;              // made to blur with its distance from what is sung
    NSUInteger _blurTurn;     // counts the blur's changes, so a sharpening cut short leaves the filter on
}

// VoiceOver's actions on the line: Meaning first where it has one, then Copy line, Share line and Share as card,
// each the menu's own item. A line with nothing to copy, and a backing row, offer none.
- (void)buildActions {
    NSString *text = heldLineText(self.line);
    if (!text.length || !self.copyText || !self.isAccessibilityElement) {
        self.accessibilityCustomActions = nil;
        return;
    }
    NSMutableArray<UIAccessibilityCustomAction *> *actions = [NSMutableArray array];
    [actions addObjectsFromArray:_meaningActions];
    __weak SGRKaraokeLineView *weakSelf = self;
    [actions addObject:[[UIAccessibilityCustomAction alloc]
        initWithName:SGL(@"settings.lyrics.hold.copy.line", @"Copy line") actionHandler:^BOOL(UIAccessibilityCustomAction *action) {
            SGRKaraokeLineView *line = weakSelf;
            return line.copyText ? line.copyText() : NO;
        }]];
    [actions addObject:[[UIAccessibilityCustomAction alloc]
        initWithName:SGL(@"settings.lyrics.hold.share.line", @"Share line") actionHandler:^BOOL(UIAccessibilityCustomAction *action) {
            SGRKaraokeLineView *line = weakSelf;
            return line.shareText ? line.shareText() : NO;
        }]];
    [actions addObject:[[UIAccessibilityCustomAction alloc]
        initWithName:SGL(@"settings.lyrics.hold.card.line", @"Share as card") actionHandler:^BOOL(UIAccessibilityCustomAction *action) {
            SGRKaraokeLineView *line = weakSelf;
            return line.shareCard ? line.shareCard() : NO;
        }]];
    self.accessibilityCustomActions = actions;
}

// A sweep's word views, each put where the layout has it and told where it sits along the sweep.
// start: NAN for words timed one by one, else when the run lights up whole. waiting: the words' brightness until sung.
- (SGRKaraokeSweep *)sweepOf:(NSArray<SGKaraokeWord *> *)words font:(UIFont *)font waiting:(CGFloat)waiting sung:(CGFloat)sung
                      frames:(NSArray<NSValue *> *)frames offsets:(NSArray<NSNumber *> *)offsets wholeFrom:(double)start
                drawingStyle:(SGRLyricsDrawingStyle)drawingStyle {
    if (!words.count || frames.count != words.count) return nil;
    BOOL rightToLeft = readsRightToLeft([[words valueForKey:@"text"] componentsJoinedByString:@""]);
    NSMutableArray<SGRKaraokeWordView *> *views = [NSMutableArray arrayWithCapacity:words.count];
    for (NSUInteger i = 0; i < words.count; i++) {
        SGRKaraokeWordView *view = [[SGRKaraokeWordView alloc] initWithWord:words[i] font:font waiting:waiting sung:sung rightToLeft:rightToLeft];
        [view applyDrawingStyle:drawingStyle];
        CGRect frame = frames[i].CGRectValue;
        view.center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
        view.offset = offsets[i].doubleValue;
        [self addSubview:view];
        [views addObject:view];
    }
    return [[SGRKaraokeSweep alloc] initWithWords:views wholeFrom:start];
}

// When a run of the line lights up whole, or NAN to sweep it: only words the source timed are swept,
// unless the estimate is asked for.
static double wholeFrom(SGKaraokeLine *run, BOOL sweepsEstimates) {
    if (run.timing == SGKaraokeTimingWords || (run.timing == SGKaraokeTimingLine && sweepsEstimates)) return NAN;
    return run.start;
}

- (instancetype)initWithLine:(SGKaraokeLine *)line width:(CGFloat)width style:(SGRKaraokeStyle *)style under:(SGRKaraokeLineView *)under
                     blurred:(BOOL)blurred sweepsEstimates:(BOOL)sweepsEstimates {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _line = line;
    self.isAccessibilityElement = under == nil;
    self.accessibilityLabel = SGKaraokeLineText(line);
    self.accessibilityTraits = UIAccessibilityTraitButton;
    BOOL backing = under != nil;
    SGRKaraokeLayout *layout = layOut(line, width, style, backing ? under.right : -1);
    _right = layout.right;
    _translationDim = style.translationDim;
    _translationLit = style.translationLit;
    _spokenDim = style.spokenDim;
    _spokenLit = style.spokenLit;
    _noteDim = style.noteDim;
    _noteLit = style.noteLit;
    NSMutableArray<SGRKaraokeSweep *> *sweeps = [NSMutableArray array];
    SGRKaraokeSweep *sung = [self sweepOf:line.words font:style.lyrics waiting:kDimAlpha sung:1 frames:layout.lyricFrames
                                  offsets:layout.lyricOffsets wholeFrom:wholeFrom(line, sweepsEstimates) drawingStyle:style.drawingStyle];
    SGLyricsPreparedExtras *extras = line.words.count ? style.extras[line.words] : nil;
    SGKaraokeLine *pronunciation = line.pronunciation ?: extras.pronunciation;
    SGRKaraokeSweep *spoken = [self sweepOf:layout.spokenWords font:style.pronunciation waiting:_spokenDim sung:style.spokenSung
                                     frames:layout.spokenFrames offsets:layout.spokenOffsets
                                  wholeFrom:wholeFrom(pronunciation, sweepsEstimates) drawingStyle:style.drawingStyle];
    if (sung) [sweeps addObject:sung];
    if (spoken) [sweeps addObject:spoken];
    _sweeps = sweeps;
    _words = [sung.words ?: @[] arrayByAddingObjectsFromArray:spoken.words ?: @[]];
    _lyricWords = sung.words;

    if (!CGRectIsNull(layout.translation)) _translation = [self asideAt:layout.translation font:style.translation text:line.translation alpha:_translationDim];
    if (!CGRectIsNull(layout.note)) _note = [self asideAt:layout.note font:style.note text:line.note alpha:_noteDim];
    if (style.furigana && !backing) _furigana = [self furiganaOver:sung.words font:style.furigana readings:extras.ruby width:width];
    if (layout.backingTop > 0) {
        _backing = [[SGRKaraokeLineView alloc] initWithLine:line.backing width:width style:style.backing under:self blurred:NO
                                            sweepsEstimates:sweepsEstimates];
        _backing.alpha = kBackingAlpha;
        _backing.frame = CGRectMake(0, layout.backingTop, width, _backing.bounds.size.height);
        [self addSubview:_backing];
    }
    NSMutableArray<NSString *> *asides = [NSMutableArray array];
    if (_translation.text.length) [asides addObject:_translation.text];
    if (_note.text.length) [asides addObject:_note.text];
    if (layout.spokenFrames.count && pronunciation) [asides addObject:SGKaraokeLineText(pronunciation) ?: @""];
    if (line.backing) [asides addObject:SGKaraokeLineText(line.backing) ?: @""];
    self.accessibilityValue = [asides componentsJoinedByString:@". "];
    for (UIView *child in self.subviews) child.accessibilityElementsHidden = YES;
    self.frame = CGRectMake(0, 0, width, layout.height);

    // Scales toward the edge its text is aligned to, and a backing row rides its line's blur.
    if (backing) return self;
    self.layer.anchorPoint = CGPointMake(_right ? 1 : 0, 0.5);
    _blurs = blurred;
    return self;
}

- (BOOL)accessibilityActivate {
    return self.activate ? self.activate() : NO;
}

// The line's kanji with their readings set over them, each centered on the kanji it reads and no narrower than
// they are: furigana wider than their kanji spill to either side within the line's bounds. The readings are
// taken from the whole line, since a source timed by the line hands its words over a character or two at a time
// and a kanji read alone is read wrongly (夜 alone is よる, in 夜明け it is よ). A reading rides on the first
// word view of each row fragment, so it rises and waves with it, and dims and lights with the line.
- (NSArray<UILabel *> *)furiganaOver:(NSArray<SGRKaraokeWordView *> *)words font:(UIFont *)font readings:(NSArray<SGLyricsRuby *> *)readings width:(CGFloat)lineWidth {
    if (!words.count) return nil;
    // Where each word's text starts in the line's, as SGKaraokeLineText joins them.
    NSMutableString *text = [NSMutableString string];
    NSUInteger *starts = calloc(words.count, sizeof(NSUInteger));
    for (NSUInteger i = 0; i < words.count; i++) {
        SGKaraokeWord *word = words[i].word;
        if (text.length && !word.joined) [text appendString:@" "];
        starts[i] = text.length;
        [text appendString:word.text ?: @""];
    }
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    for (SGLyricsRuby *ruby in readings) {
        if (NSMaxRange(ruby.range) > text.length || !ruby.reading.length) continue;
        // Finish each row independently instead of discarding everything after the first row.
        __block CGRect under = CGRectNull;
        __block SGRKaraokeWordView *first = nil;
        __block NSRange fragment = NSMakeRange(0, 0);
        void (^finish)(void) = ^{
            if (!first) return;
            NSString *reading = readingFragment(ruby.reading, [text substringWithRange:ruby.range],
                NSMakeRange(fragment.location - ruby.range.location, fragment.length));
            if (!reading.length) return;
            CGFloat width = MIN(lineWidth, MAX(ceil([reading sizeWithAttributes:@{NSFontAttributeName: font}].width), ceil(under.size.width)));
            CGFloat x = MAX(0, MIN(CGRectGetMidX(under) - width / 2, lineWidth - width));
            CGRect frame = CGRectMake(x, CGRectGetMinY(under) - ceil(font.lineHeight), width, ceil(font.lineHeight));
            UILabel *label = [[UILabel alloc] initWithFrame:[self convertRect:frame toView:first]];
            label.text = reading;
            label.font = font;
            label.adjustsFontSizeToFitWidth = YES;
            label.textColor = UIColor.whiteColor;
            label.textAlignment = NSTextAlignmentCenter;
            label.alpha = kDimAlpha;
            [first addSubview:label];
            [labels addObject:label];
        };
        for (NSUInteger i = 0; i < words.count; i++) {
            SGRKaraokeWordView *view = words[i];
            NSString *piece = view.word.text ?: @"";
            NSRange inWord = NSIntersectionRange(ruby.range, NSMakeRange(starts[i], piece.length));
            if (!inWord.length) continue;
            if (first && fabs(CGRectGetMinY(view.frame) - CGRectGetMinY(first.frame)) > 1) {
                finish();
                first = nil;
                under = CGRectNull;
            }
            fragment = first ? NSUnionRange(fragment, inWord) : inWord;
            if (!first) first = view;
            NSDictionary *attributes = @{NSFontAttributeName: view.font};
            CGFloat from = [[piece substringToIndex:inWord.location - starts[i]] sizeWithAttributes:attributes].width;
            CGFloat wide = [[piece substringWithRange:NSMakeRange(inWord.location - starts[i], inWord.length)] sizeWithAttributes:attributes].width;
            under = CGRectUnion(under, CGRectMake(CGRectGetMinX(view.frame) + from, CGRectGetMinY(view.frame), wide, 1));
        }
        finish();
    }
    free(starts);
    return labels;
}

// A text of the line set apart from its words, dim until the line is sung.
- (UILabel *)asideAt:(CGRect)frame font:(UIFont *)font text:(NSString *)text alpha:(CGFloat)alpha {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.numberOfLines = 0;
    label.font = font;
    label.textColor = UIColor.whiteColor;
    label.alpha = alpha;
    label.textAlignment = _right ? NSTextAlignmentRight : NSTextAlignmentLeft;
    label.text = text;
    [self addSubview:label];
    return label;
}

// How many line views are made in one frame: the rest follow on the next, nearest the sung line first.
static const NSUInteger kLinesPerFrame = 4;

// Eases from wherever the blur is on screen, so a line coming into focus sharpens instead of snapping. The filter is on
// the line only while it blurs: at a radius of 0 it drew the line offscreen for nothing on every frame, as it did for
// the lines around what is sung and for every line while the page is browsed. It comes off once a sharpening ends.
- (void)setBlur:(CGFloat)blur {
    if (blur == _blur) return;
    id shown = [self.layer.presentationLayer valueForKeyPath:kBlurPath];
    CGFloat from = [shown isKindOfClass:NSNumber.class] ? [shown doubleValue] : _blur;
    _blur = blur;
    if (!_blurs) return;
    if (!self.layer.filters) {
        CAFilter *filter = [NSClassFromString(@"CAFilter") filterWithType:@"gaussianBlur"];
        if (!filter) return;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [filter setValue:@(from) forKey:@"inputRadius"];
        self.layer.filters = @[filter];
        [CATransaction commit];
    }
    NSUInteger turn = ++_blurTurn;
    [CATransaction begin];
    if (blur == 0) {
        __weak SGRKaraokeLineView *weakSelf = self;
        [CATransaction setCompletionBlock:^{
            SGRKaraokeLineView *line = weakSelf;
            if (!line || line->_blurTurn != turn) return;
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            line.layer.filters = nil;
            [CATransaction commit];
        }];
    }
    [self.layer setValue:@(blur) forKeyPath:kBlurPath];
    CABasicAnimation *ease = [CABasicAnimation animationWithKeyPath:kBlurPath];
    ease.fromValue = @(from);
    ease.toValue = @(blur);
    ease.duration = 0.6;
    ease.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.layer addAnimation:ease forKey:@"blur"];
    [CATransaction commit];
}

- (void)setActive:(BOOL)active {
    if (active == _active) return;
    _active = active;
    self.accessibilityTraits = (self.accessibilityTraits & ~UIAccessibilityTraitSelected) | (active ? UIAccessibilityTraitSelected : 0);
    _backing.active = active;
    NSUInteger generation = ++_generation;
    if (_translation || _note || _furigana.count) {
        [UIView animateWithDuration:active ? 0.3 : 0.5 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            self->_translation.alpha = active ? self->_translationLit : self->_translationDim;
            self->_note.alpha = active ? self->_noteLit : self->_noteDim;
            for (UILabel *reading in self->_furigana) reading.alpha = active ? kTranslationLit : kDimAlpha;
        } completion:nil];
    }
    if (active) {
        NSMutableArray<SGRKaraokeWordView *> *whole = [NSMutableArray array];
        for (SGRKaraokeWordView *word in _words) {
            [word.layer removeAllAnimations];
            [word.lit.layer removeAllAnimations];
            word.lit.alpha = 1;
            word.lit.hidden = NO;
            [word fillTo:word.whole ? CGFLOAT_MAX : -CGFLOAT_MAX];
            [word settle];
            if (word.whole) [whole addObject:word];
        }
        // A line lit whole comes up to white together rather than popping on, as Apple Music's do.
        if (!whole.count) return;
        for (SGRKaraokeWordView *word in whole) word.lit.alpha = 0;
        [UIView animateWithDuration:kWholeFade delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                         animations:^{ for (SGRKaraokeWordView *word in whole) word.lit.alpha = 1; } completion:nil];
        return;
    }
    // A sung line fades back to dim rather than dropping its fill at once, and its words sink back
    // on a spring slow enough to still be seen doing it. A held word's glow is left on: the spring would
    // drop it in the first frame, and the lit word fading out takes it out with it.
    [UIView animateWithDuration:0.9 delay:0 usingSpringWithDamping:1 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        for (SGRKaraokeWordView *word in self->_words) [word land];
    } completion:nil];
    [UIView animateWithDuration:0.5 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        for (SGRKaraokeWordView *word in self->_words) word.lit.alpha = 0;
    } completion:^(BOOL finished) {
        if (generation != self->_generation) return;
        for (SGRKaraokeWordView *word in self->_words) {
            [word fillTo:-CGFLOAT_MAX];
            [word unglow];
            word.lit.hidden = YES;
            word.lit.alpha = 1;
        }
    }];
}

- (void)showTime:(double)ms {
    for (SGRKaraokeSweep *sweep in _sweeps) [sweep showTime:ms];
    [_backing showTime:ms];   // timed on its own, so it lags the line as it is sung
}

- (double)nextMotionAt:(double)ms {
    double next = INFINITY;
    for (SGRKaraokeSweep *sweep in _sweeps) {
        next = MIN(next, [sweep nextMotionAt:ms]);
        if (next == ms) return next;
    }
    return _backing ? MIN(next, [_backing nextMotionAt:ms]) : next;
}

- (void)showPlain {
    self.accessibilityTraits = UIAccessibilityTraitStaticText;
    for (SGRKaraokeWordView *word in _words) [word showWhole];
    _translation.alpha = _translationLit;
    _note.alpha = _noteLit;
    for (UILabel *reading in _furigana) reading.alpha = kTranslationLit;
    [_backing showPlain];
}

- (CGRect)bubbleTarget {
    return _bubble ? CGRectInset(_bubble.frame, -kBubbleReach, -kBubbleReach) : CGRectNull;
}

- (void)markMeaning:(NSArray<SGLyricsMeaning *> *)meanings {
    // VoiceOver's Meaning comes before Copy and Share, as it does in the menu; without one the line offers the two.
    NSString *text = heldLineText(self.line);
    _meaningActions = meanings.count && text.length ? @[[[UIAccessibilityCustomAction alloc]
        initWithName:SGL(@"settings.lyrics.hold.meaning", @"Meaning") actionHandler:^BOOL(UIAccessibilityCustomAction *action) {
            SGRShowMeanings(text, meanings);
            return YES;
        }]] : nil;
    [self buildActions];
    [_bubble removeFromSuperview];
    _bubble = nil;
    [_underline removeFromSuperlayer];
    _underline = nil;
    if (!meanings.count || !_lyricWords.count) return;
    if (meanings.firstObject.author == SGLyricsMeaningByArtist) {
        // Beside the line's last row, on the side that faces into the page: after it for a line against the left
        // edge, before it, the quote mirrored, for one against the right (a second voice, or right to left), whose
        // far end is the screen's edge.
        SGRKaraokeWordView *last = _lyricWords.lastObject;
        CGFloat rowLeft = CGFLOAT_MAX, rowRight = -CGFLOAT_MAX;
        for (SGRKaraokeWordView *word in _lyricWords) {
            if (fabs(word.center.y - last.center.y) > 1) continue;
            rowLeft = MIN(rowLeft, word.center.x - word.bounds.size.width / 2);
            rowRight = MAX(rowRight, word.center.x + word.bounds.size.width / 2);
        }
        BOOL before = alignsRight(_line);
        CGFloat x = before ? rowLeft - kBubbleGap - kBubbleSide : rowRight + kBubbleGap;
        UIImage *glyph = [UIImage systemImageNamed:@"quote.opening" withConfiguration:
                          [UIImageSymbolConfiguration configurationWithPointSize:kBubbleGlyph weight:UIImageSymbolWeightBold]];
        if (before) glyph = glyph.imageWithHorizontallyFlippedOrientation;
        _bubble = [[UIImageView alloc] initWithImage:glyph];
        _bubble.contentMode = UIViewContentModeCenter;
        _bubble.tintColor = UIColor.blackColor;
        _bubble.backgroundColor = UIColor.whiteColor;
        _bubble.layer.cornerRadius = kBubbleSide / 2;
        _bubble.alpha = kBubbleAlpha;
        _bubble.frame = CGRectMake(x, last.center.y - kBubbleSide / 2, kBubbleSide, kBubbleSide);
        _bubble.isAccessibilityElement = YES;
        _bubble.accessibilityLabel = SGL(@"settings.lyricstools.meaning.artist", @"Meaning from the artist");
        [self addSubview:_bubble];
        return;
    }
    // One dotted stroke under each row the line's words wrap onto.
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGFloat rowY = NAN, from = 0, to = 0;
    for (SGRKaraokeWordView *word in _lyricWords) {
        CGFloat bottom = word.center.y + word.bounds.size.height / 2 + kUnderlineDrop;
        CGFloat left = word.center.x - word.bounds.size.width / 2, right = left + word.bounds.size.width;
        if (bottom != rowY) {
            if (!isnan(rowY)) {
                [path moveToPoint:CGPointMake(from, rowY)];
                [path addLineToPoint:CGPointMake(to, rowY)];
            }
            rowY = bottom;
            from = left;
            to = right;
            continue;
        }
        from = MIN(from, left);
        to = MAX(to, right);
    }
    [path moveToPoint:CGPointMake(from, rowY)];
    [path addLineToPoint:CGPointMake(to, rowY)];
    _underline = [CAShapeLayer layer];
    _underline.path = path.CGPath;
    _underline.strokeColor = [UIColor colorWithWhite:1 alpha:kUnderlineAlpha].CGColor;
    _underline.lineWidth = kUnderlineWidth;
    _underline.lineCap = kCALineCapRound;
    _underline.lineDashPattern = @[@0, @5];
    [self.layer insertSublayer:_underline atIndex:0];
}

@end

#pragma mark - a break

// Three dots in place of the lines through an instrumental break, the way Apple Music keeps a long
// pause from reading as lyrics gone missing: they come in as the break begins, breathe while it
// lasts, fill one after another over its length and swell and go as the next line comes up.
//
// All of it is one Core Animation timeline the length of the break, on a layer whose clock is laid
// against the song's: set once as the break opens and again only when the song jumps, stops or
// starts, so the frames in between cost the page nothing. The view itself is moved by the page like
// a line, so the clock is a layer inside it, where a stopped clock cannot stop that move too.
@interface SGRKaraokeBreakView : UIView
@property (nonatomic) BOOL right;         // against the right edge, where the line after it is
@property (nonatomic) BOOL rightToLeft;   // filling from the right, the way the line after it reads
// A word beside the dots naming the break (Intro, Interlude, Outro), nil for none. It comes and goes with them.
@property (nonatomic, copy) NSString *label;
- (instancetype)initWithFont:(UIFont *)font;
- (void)playFrom:(NSInteger)start to:(NSInteger)end;
- (void)showTime:(double)ms running:(BOOL)running at:(CFTimeInterval)shown;
@end

// Local time on the dots' clock is this far into the break plus this, so no animation begins at 0,
// which Core Animation reads as "now".
static const CFTimeInterval kBreakEpoch = 1;

// The rate the page's display link asks for, asked for here too: an animation that settles for less
// could hold the player's own 120 Hz animations down, as a link asking for 60 once did.
static CAFrameRateRange lyricsFrameRate(void) {
    return SGEnabled(SGRKeyLyricsFullRate) ? CAFrameRateRangeMake(80, 120, 120) : CAFrameRateRangeMake(30, 60, 60);
}

static double easeOutExpo(double p) {
    return p <= 0 ? 0 : p >= 1 ? 1 : 1 - pow(2, -10 * p);
}

static double smoothstep(double p) {
    p = MAX(0, MIN(1, p));
    return p * p * (3 - 2 * p);
}

@implementation SGRKaraokeBreakView {
    CALayer *_clock, *_group;
    CATextLayer *_word;
    NSArray<CALayer *> *_dots;
    NSInteger _start;
    CGFloat _side, _gap;
}

- (instancetype)initWithFont:(UIFont *)font {
    self = [super initWithFrame:CGRectMake(0, 0, 0, ceil(font.lineHeight))];
    if (!self) return nil;
    self.userInteractionEnabled = NO;
    _side = round(font.pointSize * kDotShare);
    _gap = round(font.pointSize * kDotGapShare);
    _clock = [CALayer layer];
    _group = [CALayer layer];
    _group.bounds = CGRectMake(0, 0, 3 * _side + 2 * _gap, _side);
    NSMutableArray<CALayer *> *dots = [NSMutableArray array];
    for (NSUInteger i = 0; i < 3; i++) {
        CALayer *dot = [CALayer layer];
        dot.frame = CGRectMake(i * (_side + _gap), 0, _side, _side);
        dot.cornerRadius = _side / 2;
        dot.backgroundColor = UIColor.whiteColor.CGColor;
        dot.opacity = kDimAlpha;
        [_group addSublayer:dot];
        [dots addObject:dot];
    }
    _dots = dots;
    // The name rides in the dots' group, so it breathes, swells and fades with them on their timeline.
    _word = [CATextLayer layer];
    // The system font by the font object itself: a CATextLayer handed the name of the system font finds no font
    // by that name and draws in Times.
    UIFont *labelFont = [UIFont systemFontOfSize:round(font.pointSize * kBreakLabelShare) weight:UIFontWeightSemibold];
    _word.font = (__bridge CFTypeRef)labelFont;
    _word.fontSize = labelFont.pointSize;
    _word.foregroundColor = UIColor.whiteColor.CGColor;
    _word.opacity = kDimAlpha;
    _word.contentsScale = UIScreen.mainScreen.scale;
    _word.hidden = YES;
    [_group addSublayer:_word];
    _group.opacity = 0;
    [_clock addSublayer:_group];
    [self.layer addSublayer:_clock];
    return self;
}

- (void)setLabel:(NSString *)label {
    _label = [label copy];
    _word.hidden = !label.length;
    _word.string = label;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    // The name follows the dots, on the side the line after them reads toward, its baseline on their middle.
    CGFloat dots = 3 * _side + 2 * _gap, wide = 0;
    if (_label.length) {
        UIFont *font = [UIFont systemFontOfSize:_word.fontSize weight:UIFontWeightSemibold];
        CGSize text = [_label sizeWithAttributes:@{NSFontAttributeName: font}];
        wide = ceil(text.width) + _gap * 2;
        _word.alignmentMode = _rightToLeft ? kCAAlignmentRight : kCAAlignmentLeft;
        _word.frame = CGRectMake(_rightToLeft ? 0 : dots + _gap * 2, (_side - ceil(font.lineHeight)) / 2, ceil(text.width), ceil(font.lineHeight));
        for (NSUInteger i = 0; i < _dots.count; i++)
            _dots[i].frame = CGRectMake((_rightToLeft ? wide : 0) + i * (_side + _gap), 0, _side, _side);
    }
    _group.bounds = CGRectMake(0, 0, dots + wide, _side);
    CGSize size = self.bounds.size, group = _group.bounds.size;
    _clock.frame = self.bounds;
    _group.position = CGPointMake(_right ? size.width - group.width / 2 : group.width / 2, size.height / 2);
    [CATransaction commit];
}

- (void)setRight:(BOOL)right {
    if (right == _right) return;
    _right = right;
    [self setNeedsLayout];
}

// The break's whole run, sampled the way the numbers above describe it: densely where the dots come
// and go, every fifth of a second through the slow breath between.
- (void)playFrom:(NSInteger)start to:(NSInteger)end {
    _start = start;
    [_group removeAllAnimations];
    for (CALayer *dot in _dots) [dot removeAllAnimations];
    double length = (end - start) / 1000.0;
    double exitAt = MAX(kBreakWait + kBreakIn, length - kBreakCollapse - kBreakOut), over = exitAt + kBreakOut;
    BOOL still = SGRReduceMotion();   // no breath and no swell, only the fades and the fill
    NSMutableArray<NSNumber *> *times = [NSMutableArray array], *scales = [NSMutableArray array], *alphas = [NSMutableArray array];
    void (^sample)(double) = ^(double t) {
        double cycle = 2 * kBreathHalf, phase = fmod(t + kBreathHalf - fmod(exitAt, cycle) + cycle, cycle);
        double low = (1 - cos(M_PI * phase / kBreathHalf)) / 2;
        double scale = (kBreathHigh + (kBreathLow - kBreathHigh) * low) * easeOutExpo((t - kBreakWait) / kBreakIn);
        double alpha = MAX(0, MIN(1, (t - kBreakWait) / kBreakFadeIn));
        if (t >= exitAt) {
            double p = (t - exitAt) / kBreakOut;
            BOOL swelling = p <= kBreakSwellShare;
            double eased = smoothstep(swelling ? p / kBreakSwellShare : (p - kBreakSwellShare) / (1 - kBreakSwellShare));
            scale = swelling ? kBreathLow + (kBreakSwell - kBreathLow) * eased : kBreakSwell * (1 - eased);
            alpha = swelling ? 1 : 1 - eased;
        }
        [times addObject:@(t / over)];
        [scales addObject:@(still ? 1 : MAX(scale, 0.001))];
        [alphas addObject:@(alpha)];
    };
    for (double t = 0; t < kBreakWait + kBreakIn; t += 0.025) sample(t);
    for (double t = kBreakWait + kBreakIn; t < exitAt; t += 0.2) sample(t);
    for (double t = exitAt; t < over; t += 0.02) sample(t);
    sample(over);

    CAKeyframeAnimation *scale = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    CAKeyframeAnimation *alpha = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    scale.values = scales;
    alpha.values = alphas;
    for (CAKeyframeAnimation *run in @[scale, alpha]) {
        run.keyTimes = times;
        run.duration = over;
        run.beginTime = kBreakEpoch;
        run.fillMode = kCAFillModeBoth;
        run.removedOnCompletion = NO;
        run.preferredFrameRateRange = lyricsFrameRate();
        [_group addAnimation:run forKey:run.keyPath];
    }
    // Each dot fills over its third of the time before they go, in the order the next line reads.
    for (NSUInteger i = 0; i < _dots.count; i++) {
        CABasicAnimation *fill = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fill.fromValue = @(kDimAlpha);
        fill.toValue = @1;
        fill.beginTime = kBreakEpoch + (_rightToLeft ? _dots.count - 1 - i : i) * exitAt / 3;
        fill.duration = exitAt / 3;
        fill.fillMode = kCAFillModeBoth;
        fill.removedOnCompletion = NO;
        fill.preferredFrameRateRange = lyricsFrameRate();
        [_dots[i] addAnimation:fill forKey:@"fill"];
    }
}

- (void)showTime:(double)ms running:(BOOL)running at:(CFTimeInterval)shown {
    double local = kBreakEpoch + (ms - _start) / 1000.0;
    CFTimeInterval parent = [self.layer convertTime:shown fromLayer:nil];
    BOOL stopped = _clock.speed == 0;
    double now = stopped ? _clock.timeOffset : (parent - _clock.beginTime) * _clock.speed + _clock.timeOffset;
    if (stopped != running && fabs(now - local) < kBreakSlack) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (running) {
        _clock.speed = 1;
        _clock.timeOffset = 0;
        _clock.beginTime = parent - local;
    } else {
        _clock.speed = 0;
        _clock.beginTime = 0;
        _clock.timeOffset = local;
    }
    [CATransaction commit];
}

@end

#pragma mark - the page

// When each line is sung, kept apart from the lines so the page can ask on every frame.
typedef struct {
    NSInteger start, end;   // its start, and when it is sung out (SGKaraokeSungEnd)
} SGRKaraokeSpan;

// A pause long enough for the dots, and the line after it.
typedef struct {
    NSInteger start, end, line;
} SGRKaraokeBreak;

@interface SGRCreditLabel : UILabel
@property (nonatomic, copy) BOOL (^activate)(void);
@end
@implementation SGRCreditLabel
- (BOOL)accessibilityActivate { return self.activate ? self.activate() : NO; }
@end

@interface SGRKaraokeView () <UIScrollViewDelegate, SGPlayerStateObserver, UIEditMenuInteractionDelegate>
@end

@implementation SGRKaraokeView {
    UIScrollView *_scroll;
    BOOL _browsing;
    BOOL _inactive;
    // The anchor and the open break as they were when the page was taken by hand, which the stack keeps to
    // until it follows the song again (topOfLine:).
    CGFloat _browseAnchor;
    NSInteger _browseBreak;
    CADisplayLink *_link;
    NSTimer *_poll;              // looking a few times a second while the link is paused, nothing on the page moving
    NSTimer *_boundaryWake;      // instead of polling when an advancing clock has a known static interval
    NSTimer *_plainRelease;      // the one screen-awake deadline of a paused plain sheet
    BOOL _holdingAwake;
    CFTimeInterval _stirredAt;   // when something last set the page moving
    NSString *_track;
    NSArray<SGKaraokeLine *> *_lines;
    // The keeper's last snapshot found equivalent to _lines, so tick compares a snapshot once, not every frame.
    NSArray<SGKaraokeLine *> *_reconciled;
    // The song is placed from its lines' heights alone; views exist for the lines in and near sight.
    NSArray<NSNumber *> *_tops;   // where each line starts in the stack
    CGFloat _stackEnd;            // where the last line's gap ends: the credit's place
    NSMutableDictionary<NSNumber *, SGRKaraokeLineView *> *_shown;   // the views there are, by line
    CGFloat _focusTop;            // the top of the line the stack is arranged around
    CGFloat _sightOffset, _sightFocus;   // what the views in sight were last chosen for
    NSUInteger _sightArrangement;
    NSUInteger _build;   // counts the songs and widths measured, so a measurement that is late is dropped
    UIFont *_font;
    // What is sung now. Most of the time one line, the one at the anchor; where voices overlap, every
    // line being sung, the stack arranged around the one that began first; through a break, none,
    // and the dots at the anchor with the line after them just below.
    SGRKaraokeSpan *_spans;
    SGRKaraokeBreak *_breaks;
    NSUInteger _breakCount;
    NSInteger _sung[kMostSung];
    NSUInteger _sungCount;
    NSInteger _focus;       // the line the stack is arranged around, -1 before the first
    NSInteger _openBreak;   // the line the open break comes before, -1 while no break is open
    NSUInteger _arrangement;   // counts the changes to the three above, for the views in sight
    SGRKaraokeBreakView *_dots;
    NSInteger _dotsLine;   // the line the break the dots are timed for comes before
    CFTimeInterval _stillSince;   // when the position stopped moving, 0 while it moves
    SGRKaraokeStyle *_style;   // how the lines were laid out
    BOOL _hasSpoken, _hasTranslation;   // whether the song has any line with either
    BOOL _hasNotes;   // whether any line has a cultural note
    BOOL _untranslated;   // whether a line with words has no translation, which a translator can fill in
    BOOL _autoQueued;
    BOOL _madeTranslation;   // whether a line shows a translation made here, which the menu can make again or remove
    BOOL _foreign;        // whether the song is in a language other than the one translations are asked in
    BOOL _languageReady;
    NSUInteger _languageRequest;
    NSString *_detectedLanguage;
    UIView *_extrasBox;   // the Kit's glass and _extras over it, which holds none, so its alpha can fade
    UIButton *_extras;
    NSString *_extrasGlyph;   // the glyph _extras shows: translate while it has languages to offer, else ellipsis
    NSArray<SGKaraokeLine *> *_asking;        // the lines an AI service is writing pronunciations or notes for
    SGRSingButton *_sing;   // across from _extras
    UIView *_statusBox;     // between the two: automatic translation's note, faded with the extras
    SGRTranslationStatusView *_status;
    UIButton *_loadFailure;
    CGFloat _builtWidth, _placedHeight;
    NSArray<SGKaraokeLine *> *_voicesOf;   // the lines _twoVoices was settled for
    BOOL _twoVoices;
    BOOL _showing;
    BOOL _detached, _restoringRows;
    SGKaraokeLine *_detachedAnchor;
    CGFloat _detachedAnchorY;
    CAGradientLayer *_fade;
    SGRCreditLabel *_credit;
    NSString *_creditSource;   // the source the credit was settled on, nil until the lyrics name one
    NSArray<SGLyricsLink *> *_creditLinks;
    CGFloat _fontSize, _margin, _lineGap, _blurScale, _maxBlur;
    BOOL _crediting;   // Show source, read once: the page asks for the source on every frame until it has one
    double _clock;
    NSInteger _reported;
    CFTimeInterval _clockTime;
    NSInteger _seekTo;      // the line a tap seeked to, held by the clock until the player reports it
    CFTimeInterval _seekAt;   // when, 0 while no seek is waiting
    BOOL _sweepsEstimates;   // the Lyrics page's "Simulate word-by-word timing", read again as it changes
    BOOL _plain;             // the song has no timing at all: every line lit, nothing follows the clock
    NSArray<SGKaraokeLine *> *_sample;   // the preview's lines, nil for the player's
    NSInteger _sampleLength;
    CFTimeInterval _sampleEpoch;
    NSDictionary<NSNumber *, NSArray<SGLyricsMeaning *> *> *_meanings;   // Genius's, by line
    NSUInteger _meaningsAsked;
    UIEditMenuInteraction *_editMenu;   // a held line's Copy, Share and Meaning
    NSUInteger _translationPage;
    UIAlertController *_translationAlert;
    __weak UIView *_alertCover;
    NSString *_coverKey;
    SGRKaraokeLineView *_heldLine;   // the line the menu that is up was opened on
    id<NSCopying> _heldKey;   // that menu's configuration's identifier: its dismissal is the one that lets the line go
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.hidden = YES;
    _focus = _openBreak = -1;
    _margin = kMargin;
    [self takeLook];
    _shown = [NSMutableDictionary dictionary];
    _sightArrangement = NSUIntegerMax;
    SGAddPlayerStateObserver(self);
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sheetChanged:) name:SGKaraokeLinesKeptNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(awakeSettingChanged) name:SGRKeyLyricsKeepAwake object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(frameRateChanged) name:SGRKeyLyricsFullRate object:nil];
    _fade = [CAGradientLayer layer];
    _fade.colors = @[(id)UIColor.clearColor.CGColor, (id)UIColor.whiteColor.CGColor,
                     (id)UIColor.whiteColor.CGColor, (id)UIColor.clearColor.CGColor, (id)UIColor.clearColor.CGColor];
    _fade.locations = @[@0, @(kEdgeFade), @(1 - kEdgeFade), @1, @1];
    _scroll = [[UIScrollView alloc] initWithFrame:self.bounds];
    _scroll.layer.mask = _fade;
    _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _scroll.showsVerticalScrollIndicator = NO;
    _scroll.alwaysBounceVertical = YES;
    _scroll.scrollsToTop = NO;
    _scroll.delegate = self;
    [self addSubview:_scroll];
    _credit = [[SGRCreditLabel alloc] initWithFrame:CGRectZero];
    [self refreshCreditStyle];
    _credit.adjustsFontForContentSizeCategory = YES;
    _credit.hidden = YES;
    _credit.numberOfLines = 2;
    _crediting = SGFlag(SGKeyLyricsCredit, NO);
    _sweepsEstimates = SGFlag(SGKeyLyricsSimulateWords, NO);
    [_scroll addSubview:_credit];
    __weak SGRKaraokeView *weakSelf = self;
    _credit.activate = ^BOOL {
        SGRKaraokeView *page = weakSelf;
        if (!page || !page->_creditLinks.count) return NO;
        SGLyricsOpenCreditLinks(page->_creditLinks, page->_credit);
        return YES;
    };
    for (NSNotificationName name in @[UIContentSizeCategoryDidChangeNotification, UIAccessibilityDarkerSystemColorsStatusDidChangeNotification])
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(creditStyleChanged) name:name object:nil];
    _sing = [SGRSingButton new];
    _sing.hidden = !SGSingButtonShown();
    [self addSubview:_sing];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(singButtonChanged) name:SGSingButtonDidChangeNotification object:nil];
    _statusBox = [[UIView alloc] initWithFrame:CGRectZero];
    _status = [[SGRTranslationStatusView alloc] initWithFrame:CGRectZero];
    _status.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    __weak SGRKaraokeView *weakStatusOwner = self;
    _status.retry = ^(NSString *track, NSString *language) { [weakStatusOwner retryTranslationOf:track language:language]; };
    [_statusBox addSubview:_status];
    [self addSubview:_statusBox];
    _loadFailure = [UIButton buttonWithType:UIButtonTypeSystem];
    [_loadFailure setTitle:SGL(@"settings.lyrics.load_failed", @"Couldn't load lyrics · Retry") forState:UIControlStateNormal];
    _loadFailure.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _loadFailure.titleLabel.adjustsFontForContentSizeCategory = YES;
    _loadFailure.titleLabel.numberOfLines = 0;
    _loadFailure.titleLabel.textAlignment = NSTextAlignmentCenter;
    _loadFailure.tintColor = UIColor.whiteColor;
    _loadFailure.hidden = YES;
    [_loadFailure addTarget:self action:@selector(retryLyrics) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_loadFailure];
    // A snapshot changed: the note is drawn again, and nothing is asked of any translator from here.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(translationProgressChanged:) name:SGRAutoTranslationProgressDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(wordTimingChanged) name:SGLyricsWordTimingDidChangeNotification object:nil];
    if (SGRedesignedUI() && SGLyricsPiPEnabled())
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(offerExtras) name:SGLyricsPiPDidChangeNotification object:nil];
    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)]];
    [self addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(held:)]];
    _editMenu = [[UIEditMenuInteraction alloc] initWithDelegate:self];
    [self addInteraction:_editMenu];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerTransitionChanged:) name:SGPlayerTransitionNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerTransitionChanged:) name:SGPlayerTransitionEndedNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(restyle) name:SGRLyricsTextDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(restyle) name:SGLyricsRomanisedDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(translationsChanged) name:SGLyricsTranslationsDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(autoTranslationSettingsChanged) name:SGRAutoTranslationDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(aiResultsChanged:) name:SGLyricsAIResultDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(translationDidChange:) name:SGRTranslationNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sourceChosen:) name:SGLyricsSourceChosenNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(lookChanged) name:SGRLyricsLookDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(restyle) name:SGRLyricsStyleDidChangeNotification object:nil];
    // The menu says the song's offsets and whether its lyrics were picked by hand.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(offerExtras) name:SGLyricsOffsetsDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stir) name:SGLyricsOffsetsDidChangeNotification object:nil];
    for (NSNotificationName name in @[SGPlayerSpeedDidChangeNotification, SGSingChangedNotification])
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playbackClockChanged:) name:name object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stir) name:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil];
    // A translator switched on or off on the Lyrics page leaves or joins the menu.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(offerExtras) name:SGLyricsTranslationServiceSettingsDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(pinChanged:) name:SGLyricsPinDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(pinChanged:) name:SGLyricsDidReloadNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(translationsChanged) name:SGLyricsLanguageDidChangeNotification object:nil];
    // A locked phone leaves the card in its window, so the link has to be put down by the app going
    // away rather than by the view going: see scheduleLink.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(becomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resignActive) name:UIApplicationWillResignActiveNotification object:nil];
    return self;
}

// Lyrics picked by hand for the song shown, the pick taken off, or the song's lyrics asked for again: its lines
// go, and the ones kept for it next are built the way a new song's are.
- (void)pinChanged:(NSNotification *)note {
    if (_sample || ![note.object isEqual:_track]) return;
    [self dropLines];
}

// Karaoke's settings switched the mic off or on: hidden at once, Karaoke itself as it was.
- (void)singButtonChanged {
    _sing.hidden = !SGSingButtonShown();
    [self setNeedsLayout];   // the translation note takes the mic's room while it is gone
}

- (void)refreshCreditStyle {
    _credit.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption1]
        scaledFontForFont:[UIFont systemFontOfSize:kCreditSize weight:UIFontWeightSemibold] maximumPointSize:17];
    _credit.textColor = SGRSecondary();
}

- (void)creditStyleChanged {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self refreshCreditStyle];
        [self setNeedsLayout];
    });
}

- (instancetype)initWithSampleLines:(NSArray<SGKaraokeLine *> *)lines length:(NSInteger)length {
    if (!(self = [self initWithFrame:CGRectZero])) return nil;
    _sample = lines;
    _sampleLength = MAX(length, 1);
    _sampleEpoch = CACurrentMediaTime();
    _crediting = NO;
    [_sing removeFromSuperview];
    _sing = nil;
    [_statusBox removeFromSuperview];
    _statusBox = nil;
    _status = nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;   // a picture of the setting, with nothing to read or do
    return self;
}

- (void)setSampleStyleIdentifier:(NSString *)identifier {
    if (!_sample || [_sampleStyleIdentifier isEqualToString:identifier]) return;
    _sampleStyleIdentifier = [identifier copy];
    [self restyle];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self stopWatchingTranslationCover];
    if (_holdingAwake) SGRLyricsHoldAwake(self, NO);
    free(_spans);
    free(_breaks);
}

// The Lyrics page's look: the size and the room are the lines' layout, the blur their placing, the glow
// and the wave every held word's, so a change is the song measured again in it and crossfaded over.
- (void)takeLook {
    SGRLyricsLook look = SGRLyricsLookNow();
    // The size chosen for the place the view shows in, the look's own until one is.
    CGFloat share = SGRLyricsSizeShare(_sizePlace);
    _fontSize = share == 1 ? look.size : round(look.size * share);
    _lineGap = look.spacing;
    _blurScale = look.blur;
    _maxBlur = kMaxBlur * look.blur;
    sgr_glowScale = look.glow;
    sgr_waveScale = look.wave;
}

// A view without lines yet takes the place's size into the font its first build makes.
- (void)setSizePlace:(SGRLyricsPlace)sizePlace {
    if (_sizePlace == sizePlace) return;
    _sizePlace = sizePlace;
    if (_lines) [self lookChanged];
    else [self takeLook];
}

- (void)lookChanged {
    [self takeLook];
    _font = [UIFont systemFontOfSize:_fontSize weight:UIFontWeightBold];
    [_dots removeFromSuperview];   // made again in the new font, at the next frame with a break open
    _dots = nil;
    [self restyle];
}

// The preview's lines on its own clock, round and round; everything else the player's, less the
// Lyrics page's Delay (below 0 for the first moments of a song with one).
- (NSInteger)positionMs {
    if (!_sample) {
        NSInteger ms = SGKaraokePositionMs();
        return ms < 0 ? ms : ms - SGKaraokeDelayMs();
    }
    return (NSInteger)fmod((CACurrentMediaTime() - _sampleEpoch) * 1000, _sampleLength);
}

- (NSArray<SGKaraokeLine *> *)linesFor:(NSString *)track {
    return _sample ?: SGKaraokeLinesForTrack(track);
}

static BOOL cornerControlShown(UIView *view) {
    return view.superview && !view.hidden && view.userInteractionEnabled;
}

- (void)tapped:(UITapGestureRecognizer *)tap {
    [self stir];
    if (cornerControlShown(_extrasBox) && CGRectContainsPoint(_extrasBox.frame, [tap locationInView:self])) return;
    if (_status.showsNote && _statusBox.userInteractionEnabled && CGRectContainsPoint(_statusBox.frame, [tap locationInView:self])) return;
    if (cornerControlShown(_sing) && [_sing pointInside:[tap locationInView:_sing] withEvent:nil]) return;
    if (_creditLinks.count && !_credit.hidden
        && CGRectContainsPoint(CGRectInset(_credit.frame, -kCreditSlop, -MAX(kCreditSlop, (44 - _credit.frame.size.height) / 2)),
                               [tap locationInView:_scroll])) {
        SGLyricsOpenCreditLinks(_creditLinks, _credit);
        return;
    }
    CGPoint point = [self displayedScrollPoint:tap];
    for (SGRKaraokeLineView *view in _shown.allValues) {
        CGRect target = view.bubbleTarget;
        if (CGRectIsNull(target)) continue;
        CALayer *layer = view.layer.presentationLayer ?: view.layer;
        if (!CGRectContainsPoint(target, [layer convertPoint:point fromLayer:layer.superlayer])) continue;
        [self explainLine:view];
        return;
    }
    if (_plain) return;   // a line with no time has nowhere to seek to
    SGRKaraokeLineView *view = [self lineUnder:point];
    if (!view) return;
    [self flashPlateBehind:view];
    [self seekToLine:view.line];
}

// The plate is the line's own sublayer, under its words, so it rides the glide to the anchor with it.
- (void)flashPlateBehind:(SGRKaraokeLineView *)view {
    CALayer *plate = [CALayer layer];
    plate.frame = CGRectInset(view.bounds, -kTapPlateOut, -kTapPlateOutY);
    plate.cornerRadius = kTapPlateRadius;
    plate.cornerCurve = kCACornerCurveContinuous;
    plate.backgroundColor = [UIColor colorWithWhite:1 alpha:kTapPlateAlpha].CGColor;
    plate.opacity = 0;
    [view.layer insertSublayer:plate atIndex:0];
    CAKeyframeAnimation *flash = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    NSTimeInterval total = kTapPlateHold + kTapPlateFade;
    flash.values = @[@1, @1, @0];
    flash.keyTimes = @[@0, @(kTapPlateHold / total), @1];
    flash.duration = total;
    flash.timingFunctions = @[[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear],
                              [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{ [plate removeFromSuperlayer]; }];
    [plate addAnimation:flash forKey:@"flash"];
    [CATransaction commit];
}

- (BOOL)untimed { return _plain; }

- (BOOL)touchIsOnLine:(UITouch *)touch {
    if (_plain || _browsing || !_scroll) return NO;
    CGPoint inSelf = [touch locationInView:self];
    if (cornerControlShown(_extrasBox) && CGRectContainsPoint(_extrasBox.frame, inSelf)) return NO;
    if (cornerControlShown(_sing) && [_sing pointInside:[touch locationInView:_sing] withEvent:nil]) return NO;
    CGPoint point = [touch locationInView:_scroll];
    CALayer *shown = _scroll.layer.presentationLayer;
    if (shown) point.y += shown.bounds.origin.y - _scroll.bounds.origin.y;
    return [self lineUnder:point] != nil;
}

// A tap on a line, or VoiceOver activating it.
- (void)seekToLine:(SGKaraokeLine *)line {
    // The line shows Delay later than the song, so its sound is that much past its start.
    NSInteger delay = SGKaraokeDelayMs();
    SGLog(@"lyrics: tapped the line at %ld-%ld ms, the clock at %.0f ms, %ld ms of delay", (long)line.start, (long)line.end, _clock, (long)delay);
    SGKaraokeSeek(line.start + delay);
    SGPlayFeedback(SGFeedbackSkip);
    [self glideTo:line.start];
}

- (void)held:(UILongPressGestureRecognizer *)hold {
    [self stir];
    // Changed and Ended carry on with the line the press opened the menu on: the menu keeps its anchor until it is
    // dismissed, not until the finger moves.
    if (hold.state != UIGestureRecognizerStateBegan || _sample) return;   // a preview is a picture of the page
    // The page's own controls take their own touches; a press behind them gets no menu of a line's.
    CGPoint point = [hold locationInView:self];
    SGRKaraokeLineView *view = nil;
    if (!(cornerControlShown(_extrasBox) && CGRectContainsPoint(_extrasBox.frame, point))
        && !(_status.showsNote && _statusBox.userInteractionEnabled && CGRectContainsPoint(_statusBox.frame, point))
        && !(cornerControlShown(_sing) && [_sing pointInside:[hold locationInView:_sing] withEvent:nil]))
        view = [self lineUnder:[self displayedScrollPoint:hold]];
    if (!view || !heldLineText(view.line).length) {
        // A press that offers nothing of its own takes the last menu away rather than leaving it on that line.
        [self letGoOfHeldLine];
        return;
    }
    // The line is held under this menu's own identifier: a press while this menu is up presents another one, which
    // UIKit does after telling the delegate this one is gone, and that dismissal is not the new line's to answer.
    NSString *key = [[NSUUID UUID] UUIDString];
    _heldLine = view;
    _heldKey = key;
    SGPlayFeedback(SGFeedbackGrab);
    UIEditMenuConfiguration *configuration = [UIEditMenuConfiguration configurationWithIdentifier:key
        sourcePoint:[self convertPoint:[hold locationInView:_scroll] fromView:_scroll]];
    configuration.preferredArrowDirection = UIEditMenuArrowDirectionAutomatic;
    [_editMenu presentEditMenuWithConfiguration:configuration];
}

- (CGPoint)displayedScrollPoint:(UIGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:_scroll];
    // UIKit converts to the model bounds even while the scroll is springing home.
    CALayer *shown = _scroll.layer.presentationLayer;
    if (shown) point.y += shown.bounds.origin.y - _scroll.bounds.origin.y;
    return point;
}

// The line whose room a touch in the scroll is in: of the lines whose room holds it, the one it is nearest, so a
// line with nothing to say (an empty one) is the one held and not the line beside it.
- (SGRKaraokeLineView *)lineUnder:(CGPoint)point {
    SGRKaraokeLineView *nearest = nil;
    CGFloat distance = CGFLOAT_MAX;
    for (SGRKaraokeLineView *view in _shown.allValues) {
        CALayer *layer = view.layer.presentationLayer ?: view.layer;
        CGRect frame = layer.frame;
        if (!CGRectContainsPoint(CGRectInset(frame, -_margin, -_lineGap / 2), point)) continue;
        CGFloat away = fabs(CGRectGetMidY(frame) - point.y);
        if (away >= distance) continue;
        nearest = view;
        distance = away;
    }
    return nearest;
}

// The meanings of a line, nil for one Genius has not explained.
- (NSArray<SGLyricsMeaning *> *)meaningsOf:(SGRKaraokeLineView *)view {
    NSNumber *index = [_shown allKeysForObject:view].firstObject;
    return index ? _meanings[index] : nil;
}

- (void)explainLine:(SGRKaraokeLineView *)view {
    NSArray<SGLyricsMeaning *> *meanings = [self meaningsOf:view];
    if (!meanings.count) return;
    SGPlayFeedback(SGFeedbackSkip);
    SGRShowMeanings(SGKaraokeLineText(view.line), meanings);
}

#pragma mark - the held line's menu

NSString *SGRLyricsShareText(NSString *line, NSString *title, NSString *artist, NSString *trackID, BOOL playing) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    if (line.length) [lines addObject:line];
    if (title.length) [lines addObject:artist.length ? [NSString stringWithFormat:@"\u2014 %@ \u00B7 %@", title, artist]
                                                     : [NSString stringWithFormat:@"\u2014 %@", title]];
    // The link goes with the song it names: an episode's, a podcast's or a local file's has none of its own here.
    if (playing && [trackID hasPrefix:@"spotify:track:"]) {
        [lines addObject:[@"https://open.spotify.com/track/" stringByAppendingString:[trackID substringFromIndex:@"spotify:track:".length]]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

// Copy, Share, Share as Card and, where the line has one already, Meaning: the system's edit menu on the held line,
// and the same as VoiceOver's actions on the line (markMeaning:). Nothing here asks any source for anything.
- (UIMenu *)editMenuInteraction:(UIEditMenuInteraction *)interaction menuForConfiguration:(UIEditMenuConfiguration *)configuration
                suggestedActions:(NSArray<UIMenuElement *> *)suggestedActions {
    SGRKaraokeLineView *view = [self lineOfConfiguration:configuration];
    NSString *text = view ? heldLineText(view.line) : nil;
    if (!text.length) return [UIMenu menuWithChildren:@[]];
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
    NSArray<SGLyricsMeaning *> *meanings = [self meaningsOf:view];
    if (meanings.count) {
        [items addObject:[UIAction actionWithTitle:SGL(@"settings.lyrics.hold.meaning", @"Meaning") image:nil identifier:nil
                                           handler:^(UIAction *action) { SGRShowMeanings(text, meanings); }]];
    }
    [items addObject:[UIAction actionWithTitle:SGL(@"settings.lyrics.hold.copy", @"Copy") image:nil identifier:nil
                                       handler:^(UIAction *action) { [self copyLine:text]; }]];
    __weak SGRKaraokeView *weakSelf = self;
    [items addObject:[UIAction actionWithTitle:SGL(@"settings.lyrics.hold.share", @"Share") image:nil identifier:nil
                                       handler:^(UIAction *action) { [weakSelf shareLine:text from:view]; }]];
    SGKaraokeLine *line = view.line;
    [items addObject:[UIAction actionWithTitle:SGL(@"settings.lyrics.hold.card", @"Share as Card") image:nil identifier:nil
                                       handler:^(UIAction *action) { [weakSelf shareCardFrom:line]; }]];
    return [UIMenu menuWithChildren:items];
}

- (CGRect)editMenuInteraction:(UIEditMenuInteraction *)interaction targetRectForConfiguration:(UIEditMenuConfiguration *)configuration {
    SGRKaraokeLineView *view = [self lineOfConfiguration:configuration];
    if (!view || view.superview != _scroll) return CGRectNull;
    return [view convertRect:view.bounds toView:self];
}

// The line a configuration is for: the held line, while the configuration is the held line's own menu's. Anything
// else has no line here, so a menu left over from before cannot answer for the one that replaced it.
- (SGRKaraokeLineView *)lineOfConfiguration:(UIEditMenuConfiguration *)configuration {
    return [self configurationIsHeld:configuration] ? _heldLine : nil;
}

// Whether a configuration is the held line's own menu's: its dismissal is the one that lets the line go, and it is
// the only one that offers the line's items and anchor.
- (BOOL)configurationIsHeld:(UIEditMenuConfiguration *)configuration {
    id key = configuration.identifier;
    return _heldKey != nil && (key == _heldKey || [(NSObject *)key isEqual:_heldKey]);
}

// The line is held for as long as its menu is up, its Changed and Ended included; it is let go with that menu, and
// with its own view when that goes (letGoOfLineView:). A menu replaced by another one goes too, and says so here
// before the new one is presented: only the menu that is the held line's own can let it go.
- (void)editMenuInteraction:(UIEditMenuInteraction *)interaction willDismissMenuForConfiguration:(UIEditMenuConfiguration *)configuration
                   animator:(id<UIEditMenuInteractionAnimating>)animator {
    if ([self configurationIsHeld:configuration]) {
        _heldLine = nil;
        _heldKey = nil;
    }
}

// The line's own words, and nothing else: no translation, pronunciation, title or artist.
- (void)copyLine:(NSString *)text {
    if (!text.length) return;
    UIPasteboard.generalPasteboard.string = text;
    SGLog(@"lyrics: copied the held line");
}

// What a shared line says: the line, then the song on the line after it, and the song's public link under that
// while the lines shown are the playing track's own and it is not a local file's.
- (void)shareLine:(NSString *)text from:(UIView *)view {
    if (!text.length) return;
    SPTPlayerTrack *song = SGKaraokeTrackFor(_track);
    NSString *body = SGRLyricsShareText(text, song.trackTitle, song.artistName, _track,
                                       [SGKaraokePlayingTrack() isEqualToString:_track]);
    UIViewController *top = SGTopController();
    if (!top) return;
    UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[body] applicationActivities:nil];
    sheet.popoverPresentationController.sourceView = self;
    sheet.popoverPresentationController.sourceRect = view && view.superview ? [view convertRect:view.bounds toView:self]
                                                                          : CGRectMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds), 1, 1);
    SGPresentDark(sheet);
    [top presentViewController:sheet animated:YES completion:nil];
    SGLog(@"lyrics: shared the held line");
}

// A lyric card, the held line picked already: every line with something to say goes to the picker
// (LyricCardPicker.h) with the side it reads from and its pronunciation, the source's or else the reading in the
// alphabet the Lyrics page chose, whether or not the page shows it now. Readings are made off the main thread, as
// the layout's are; the card starts with them shown while the page shows them.
- (void)shareCardFrom:(SGKaraokeLine *)held {
    if (!_lines.count || !heldLineText(held).length) return;
    NSUInteger heldIndex = [_lines indexOfObjectIdenticalTo:held];
    NSArray<SGKaraokeLine *> *lines = layoutSnapshots(_lines);
    NSString *track = _track;
    BOOL japanese = [[self songLanguage] isEqual:@"ja"];
    BOOL hangul = SGFlag(SGKeyLyricsPronunciationHangul, NO), hiragana = SGFlag(SGKeyLyricsJapaneseKana, NO);
    BOOL shown = _style.pronunciation != nil;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<SGRLyricCardLine *> *cards = [NSMutableArray array];
        NSUInteger picked = NSNotFound;
        for (NSUInteger i = 0; i < lines.count; i++) {
            SGKaraokeLine *line = lines[i];
            NSString *text = heldLineText(line);
            if (!text.length) continue;
            if (i == heldIndex) picked = cards.count;
            SGKaraokeLine *spoken = line.pronunciation ?: SGLyricsPrepareExtras(line, japanese, hangul, hiragana, YES, NO).pronunciation;
            NSString *reading = spoken ? SGKaraokeLineText(spoken) : nil;
            SGRLyricCardLine *card = [SGRLyricCardLine new];
            card.text = text;
            card.pronunciation = reading.length && ![SGLyricsBareText(reading) isEqualToString:SGLyricsBareText(text)] ? reading : nil;
            card.rightToLeft = readsRightToLeft(text);
            [cards addObject:card];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            SGLog(@"lyrics: a lyric card of %lu lines to pick from", (unsigned long)cards.count);
            SGRPresentLyricCardPicker(cards, picked, shown, track);
        });
    });
}

// Genius is asked once the song's lines are in; lines that change under it are matched again.
- (void)askMeanings {
    _meanings = nil;
    if (_sample) return;
    NSUInteger asked = ++_meaningsAsked;
    NSArray<SGKaraokeLine *> *lines = _lines;
    NSString *track = _track, *language = [self songLanguage] ?: @"";
    __weak SGRKaraokeView *weakSelf = self;
    SGLyricsMeaningsFor(_track, lines, ^(NSDictionary<NSNumber *, NSArray<SGLyricsMeaning *> *> *byLine) {
        SGRKaraokeView *page = weakSelf;
        if (!page || asked != page->_meaningsAsked || lines != page->_lines || ![track isEqual:page->_track] ||
            ![language isEqual:([page songLanguage] ?: @"")]) return;
        page->_meanings = byLine;
        for (NSNumber *key in page->_shown) [page->_shown[key] markMeaning:byLine[key]];
    });
}

#pragma mark - scrolling by hand

// Lines are placed for a content offset of 0, so following the song means scrolling back to 0.
// While the user browses, placement stands still and every line is sharp.
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [self stir];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(followSong) object:nil];
    if (!_browsing) {
        _browseAnchor = [self restingAnchor];
        _browseBreak = _openBreak;
    }
    _browsing = YES;
    if (self.browsingBegan) self.browsingBegan();
    for (SGRKaraokeLineView *view in _shown.allValues) view.blur = 0;
}

- (void)updateExtrasGlass {
    UIView *shape = SGRGlassInside(_extrasBox, &kExtrasGlassKey, _sizePlace == SGRLyricsPlacePlayer ? kPlayerExtrasSide : kExtrasSide);
    SGRGlassBacks(shape, _extras);
    SGRShowGlass(shape, !_extrasHidden);
}

- (void)refreshGlass {
    if (_extrasBox && !_extrasHidden) SGRRefreshGlass(objc_getAssociatedObject(_extrasBox, &kExtrasGlassKey));
    [_sing refreshGlass];
}

// In the caller's animation: the glass dematerializes by its effect and the glyph fades by its alpha, the
// one view of the two with no glass in it.
- (void)setExtrasHidden:(BOOL)hidden {
    [self stir];
    _extrasHidden = hidden;
    if (_extrasBox) {
        [self updateExtrasGlass];
        _extras.alpha = hidden ? 0 : 1;
        _extrasBox.userInteractionEnabled = !hidden;
    }
    _statusBox.alpha = hidden ? 0 : 1;
    _statusBox.userInteractionEnabled = !hidden;
    _sing.tucked = hidden && !_keepsSing;
    [self clearBottomRow];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self stir];    // follow the presentation-layer offset and finish any budgeted rows
    [self showLinesInSight];
}

// The Music app decides on its controls here, by the flick the finger leaves: toward the lines to come hides them, back toward the ones sung brings them back.
- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)target {
    if (self.browsingFlicked) self.browsingFlicked(velocity.y);
}

// Plain text has no song to follow back to: it stays where it was scrolled to, as a page of text does.
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate && !_plain) [self performSelector:@selector(followSong) withObject:nil afterDelay:kBrowseHold];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (!_plain) [self performSelector:@selector(followSong) withObject:nil afterDelay:kBrowseHold];
}

- (void)followSong {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(followSong) object:nil];
    if (!_browsing || _renderingSuspended) return;
    _browsing = NO;
    [UIView animateWithDuration:0.7 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{ self->_scroll.contentOffset = CGPointZero; } completion:nil];
    [self placeLinesAnimated:YES];
    if (self.browsingEnded) self.browsingEnded();
}

// A tapped line glides to the anchor at once, and the stack with it: the clock is held at the line until
// the player reports the seek, which takes a few frames. Read before then, the position still on the line
// being sung put the stack back on it, and the seek's arrival then jumped it over to the tapped one.
- (void)glideTo:(NSInteger)ms {
    [self stir];
    _seekTo = ms;
    _seekAt = CACurrentMediaTime();
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(followSong) object:nil];
    if (_browsing) {
        _browsing = NO;
        [UIView animateWithDuration:0.7 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0
                            options:UIViewAnimationOptionAllowUserInteraction
                         animations:^{ self->_scroll.contentOffset = CGPointZero; } completion:nil];
        if (self.browsingEnded) self.browsingEnded();
    }
    if (!_tops) return;
    NSUInteger arrangement = _arrangement;
    [self arrangeAt:[self clockMs] glide:YES];
    // The line sung tapped again, off a page scrolled by hand: nothing moved on, so the stack is put back.
    if (_arrangement == arrangement) [self placeLinesAnimated:YES];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) {
        NSNumber *anchor = [self browseAnchorAt:&_detachedAnchorY];
        _detachedAnchor = anchor ? _shown[anchor].line : nil;
        _detached = YES;
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(followSong) object:nil];
        [self leaveTranslationPage];
        [self dropLineViews];
    } else if (_detached) {
        _detached = NO;
        // Place the viewport before UIKit presents it. Keep the measured stack,
        // including a hand-scrolled anchor; offscreen padding can wait for ticks.
        _restoringRows = YES;
        if (_browsing && _detachedAnchor && _tops) {
            NSUInteger index = [_lines indexOfObjectIdenticalTo:_detachedAnchor];
            if (index == NSNotFound) {
                // A provider translation can replace the line objects without replacing the lyrics.
                NSString *text = SGKaraokeLineText(_detachedAnchor);
                index = [_lines indexOfObjectPassingTest:^BOOL(SGKaraokeLine *line, NSUInteger i, BOOL *stop) {
                    return line.start == self->_detachedAnchor.start && [SGKaraokeLineText(line) isEqual:text];
                }];
            }
            if (index != NSNotFound) [self restoreAnchor:index viewportY:_detachedAnchorY];
        }
        _detachedAnchor = nil;
        if (!_renderingSuspended) [self tick];
        [self showLinesInSight];
        for (SGRKaraokeLineView *row in _shown.allValues) [row.layer removeAnimationForKey:@"blur"];
        _restoringRows = NO;
        _sightOffset = -CGFLOAT_MAX;
        if (_browsing && !_plain) [self performSelector:@selector(followSong) withObject:nil afterDelay:kBrowseHold];
    }
    [self scheduleLink];
    [self refreshTranslationStatus];
}

- (void)resumeBrowseReturn {
    if (!_browsing || _plain || _renderingSuspended || !self.window || _scroll.isTracking || _scroll.isDecelerating) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(followSong) object:nil];
    [self performSelector:@selector(followSong) withObject:nil afterDelay:kBrowseHold];
}

- (void)setRenderingSuspended:(BOOL)suspended {
    if (_renderingSuspended == suspended) return;
    _renderingSuspended = suspended;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(followSong) object:nil];
    if (!suspended && self.window && !_inactive && UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
        // The next link may be delayed by the transition. Paint the current song position
        // before the reveal, without discarding measured rows or a hand-scrolled anchor.
        _clockTime = CACurrentMediaTime();
        _clock = [self positionMs];
        [self tick];
        [self resumeBrowseReturn];
    }
    [self scheduleLink];
}

// The player opens and closes in animations that run at 120 Hz, and while a display link asked
// for 30 to 60, the range Apple's ProMotion guide says Core Animation gives priority to, those
// animations ran rough; the player and the lyrics themselves were smooth throughout. The card's
// link now asks for 60 but takes 120, and is put down for as long as the player animates, which
// NowPlayingBar.x announces as each animation starts and again as it ends. The timer is for an end
// that is never announced.
//
// The link is also put down whenever the app is not in front. Spotify keeps playing there, and a
// phone locked on the player kept the card ticking at 120 Hz against a screen that was off: 117 of
// the 137 wake ups a second the mod cost over stock Spotify were this one link, measured with
// scripts/battery-probe.sh. Nothing of the card is seen from the background, so nothing is drawn.
- (void)scheduleLink {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(startLink) object:nil];
    [_boundaryWake invalidate];
    _boundaryWake = nil;
    [_plainRelease invalidate];
    _plainRelease = nil;
    [_poll invalidate];
    _poll = nil;
    [_link invalidate];
    _link = nil;
    [self holdAwake:NO];   // held again by the next frame, while the song plays
    if (_renderingSuspended || !self.window) return;
    NSTimeInterval wait = SGPlayerTransitionEnds() - CACurrentMediaTime();
    if (wait <= 0) [self startLink];
    else [self performSelector:@selector(startLink) withObject:nil afterDelay:wait + kTransitionSlack inModes:@[NSRunLoopCommonModes]];
}

- (void)resignActive {
    // WillResignActive can arrive before UIApplication's state changes.
    _inactive = YES;
    [self scheduleLink];
}

- (void)becomeActive {
    _inactive = NO;
    [self resumeBrowseReturn];
    [self scheduleLink];
    [self presentPendingTranslationAlert];
}

- (void)frameRateChanged {
    // Reinstall an open break's animations on the same timeline with the new range.
    _dotsLine = -1;
    if (_dots.superview) [self placeBreak];
    [self scheduleLink];
}

// Smooth lyrics asks for 80–120 Hz by default; switching it off asks for 30–60 Hz, preferring 60.
- (void)startLink {
    if (_renderingSuspended || !self.window || _link) return;
    if (_inactive || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    _link.preferredFrameRateRange = lyricsFrameRate();
    _stirredAt = CACurrentMediaTime();
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    [self queueAutomaticTranslation];
}

// The frame being drawn, or now while the link is paused.
- (CFTimeInterval)frameTime {
    return _link && !_link.paused ? _link.targetTimestamp : CACurrentMediaTime();
}

// Nothing on the page moves: the link is paused rather than slowed, because a link asking for a low rate,
// even uncapped, holds the player's 120 Hz animations back (see scheduleLink). A timer, which asks the display
// for nothing, still watches the track, its lines and the clock a few times a second.
- (void)calmDown {
    _link.paused = YES;
    __weak typeof(self) weakSelf = self;
    _poll = [NSTimer timerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer) { [weakSelf tick]; }];
    [NSRunLoop.mainRunLoop addTimer:_poll forMode:NSRunLoopCommonModes];
}

// Something is about to move: the link back at the display's rate before its next frame.
- (void)stir {
    _stirredAt = CACurrentMediaTime();
    [self resumeFrames];
}

- (void)resumeFrames {
    if (!_link.paused) return;
    [_boundaryWake invalidate];
    _boundaryWake = nil;
    [_poll invalidate];
    _poll = nil;
    _link.paused = NO;
}

// Play, pause, a new track: the clock is about to move, or the page to change.
- (void)playerStateDidChange:(SPTPlayerState *)state {
    [self stir];
}

- (void)sheetChanged:(NSNotification *)note {
    if ([_track isEqual:note.object]) [self stir];
}

- (void)playbackClockChanged:(NSNotification *)note {
    if (!_sample && !_plain) [self resumeFrames];
}

- (void)awakeSettingChanged {
    // The row has applied its setting. Each view releases or reacquires its own
    // hold synchronously, including a plain page whose display link is paused.
    if (!_link || _sample) return;
    if (_plain) [self plainAwake];
    else if (!SGRLyricsKeepAwakeOn()) [self holdAwake:NO];
    else [self tick];
}

// A rate-only report can stop the clock without pausing Spotify (SpeedProbe.x).
static NSInteger plainRestPosition(SPTPlayerState *state) {
    if (state.isPaused) return (NSInteger)(state.positionAsOfTimestamp * 1000);
    if (!state.isPlaying || state.playbackSpeed == 0) return (NSInteger)(state.position * 1000);
    return NSNotFound;
}

// A seek while paused, from Spotify's own scrubber: a report that moves the position. A report that
// leaves it where it was lets the link stay calm.
- (void)playerStateDidReport:(SPTPlayerState *)state {
    if (_plain) {
        if (_sample || !_link) return;
        NSInteger rest = plainRestPosition(state);
        if (rest == NSNotFound ? _stillSince != 0 : !_stillSince || rest != _reported) [self plainAwake];
        return;
    }
    // The player's position less the Delay, as positionMs reads it, from the state reported.
    NSInteger ms = _sample ? [self positionMs]
                           : (NSInteger)((state.isPaused ? state.positionAsOfTimestamp : state.position) * 1000) - SGKaraokeDelayMs();
    if (!_link.paused) return;
    if (_poll) {
        if (ms != _reported) [self stir];
    } else {
        // A normal advancing report confirms the deadline rather than buying a display callback.
        // Both samples were truncated to milliseconds. A correction, stall or seek rechecks it.
        double expected = _clock + (CACurrentMediaTime() - _clockTime) * 1000;
        if (state.isPaused || !state.isPlaying || state.playbackSpeed != 1 || fabs(ms - expected) > 2)
            [self resumeFrames];
    }
}

- (void)playerTransitionChanged:(NSNotification *)note {
    [self scheduleLink];
}

// The mask sits in the scroll view's own coordinates, which move with the content as it scrolls, so
// it is put back over the visible part on every frame, where the presentation layer says the
// content is: that holds through a drag and through the animated scroll home alike. Left where
// layout put it, it covered the first screenful of lines only, and a scroll past them showed nothing.
- (void)alignFade {
    CALayer *shown = (CALayer *)_scroll.layer.presentationLayer ?: _scroll.layer;
    CGRect frame = CGRectMake(0, shown.bounds.origin.y, self.bounds.size.width, self.bounds.size.height);
    if (CGRectEqualToRect(frame, _fade.frame)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _fade.frame = frame;
    [CATransaction commit];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self alignFade];
    CGFloat failureWidth = MAX(0, self.bounds.size.width - 2 * _margin);
    CGFloat failureHeight = MAX(44, [_loadFailure sizeThatFits:CGSizeMake(failureWidth, CGFLOAT_MAX)].height + 24);
    _loadFailure.frame = CGRectMake(_margin, (self.bounds.size.height - failureHeight) / 2, failureWidth, failureHeight);
    _scroll.contentSize = self.bounds.size;
    BOOL player = _sizePlace == SGRLyricsPlacePlayer;
    CGFloat side = player ? kPlayerExtrasSide : kExtrasSide, bottom = player ? kPlayerExtrasBottom : kExtrasBottom;
    _sing.frame = CGRectMake(self.bounds.size.width - _margin - side, self.bounds.size.height - side - bottom, side, side);
    if (_extrasBox && !_extrasBox.hidden) {
        _extrasBox.frame = CGRectMake(_margin, self.bounds.size.height - side - bottom, side, side);
        [self updateExtrasGlass];
    }
    if (_statusBox) {
        CGFloat left = _margin + side + 8;
        CGFloat right = _sing && !_sing.hidden ? CGRectGetMinX(_sing.frame) - 8 : self.bounds.size.width - _margin;
        _statusBox.frame = CGRectMake(left, self.bounds.size.height - side - bottom, MAX(0, right - left), side);
    }
    [self clearBottomRow];
    if (_lines && self.bounds.size.width != _builtWidth) {
        [self rebuild];
    } else if (_tops && self.bounds.size.height != _placedHeight) {
        // A new height moves the anchor (the player's lines going alone and back): the stack is placed for it
        // here, inside whatever animation resized the page, so the sung line rides along with it rather than
        // springing to the new anchor at the next line, and the band the height opens is filled in.
        _sightOffset = -CGFLOAT_MAX;
        [self placeLinesAnimated:NO];
    }
    _placedHeight = self.bounds.size.height;
}

// The lines fade out above the bottom row (the mic and the extras button) and stay clear under
// it, so none is read through the credit; with nothing there they fade out at the bottom edge.
- (void)clearBottomRow {
    CGFloat height = self.bounds.size.height;
    if (height <= 0) return;
    CGFloat floor = height;
    // In the player the Music app's lines run on behind its translate and Sing buttons, fading only at the bottom edge.
    BOOL behind = _sizePlace == SGRLyricsPlacePlayer;
    if (!behind && cornerControlShown(_sing)) floor = MIN(floor, CGRectGetMinY(_sing.frame) - 8);
    if (!behind && cornerControlShown(_extrasBox)) floor = MIN(floor, CGRectGetMinY(_extrasBox.frame) - 8);
    CGFloat clear = MAX(0, MIN(1, (height - floor) / height));
    NSArray *locations = @[@0, @(kEdgeFade), @(MAX(kEdgeFade, 1 - clear - kEdgeFade)), @(1 - clear), @1];
    if ([_fade.locations isEqualToArray:locations]) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _fade.locations = locations;
    [CATransaction commit];
    [self updateScrollExtent];
}

// A line's view going away takes the menu with it: the menu's arrow points at a view that is gone otherwise, and
// its Copy and Share would offer a line the page no longer shows. Every removal path goes through here or through
// dropLineViews, which goes through it.
- (void)letGoOfLineView:(SGRKaraokeLineView *)view {
    if (view == _heldLine) [self letGoOfHeldLine];
    [view removeFromSuperview];
}

- (void)letGoOfHeldLine {
    _heldLine = nil;
    _heldKey = nil;
    [_editMenu dismissMenu];
}

- (void)dropLineViews {
    for (UIView *view in _shown.allValues) [self letGoOfLineView:(SGRKaraokeLineView *)view];
    [self letGoOfHeldLine];
    [_shown removeAllObjects];
    _sightArrangement = NSUIntegerMax;
}

- (void)dropMeasuredLines {
    [self dropLineViews];
    _detachedAnchor = nil;
    _tops = nil;
    _build++;
    [self forgetSung];
}

// Nothing sung, no break open: the state a song starts from, before the clock places it. The dots
// are made again for the next, in case it is laid out in another font.
- (void)forgetSung {
    _sungCount = 0;
    _focus = _openBreak = -1;
    _arrangement++;
    [_dots removeFromSuperview];
    _dots = nil;
}

// A way to translate a song: the lines, the track and the language in, one translation per line out, or a
// message to show. Main queue.
typedef SGRAutoTranslated SGRTranslated;

// The lines' text for a translator, "" for a line with no words or a translation already.
static NSArray<NSString *> *textsOf(NSArray<SGKaraokeLine *> *lines) {
    NSMutableArray<NSString *> *texts = [NSMutableArray arrayWithCapacity:lines.count];
    for (SGKaraokeLine *line in lines) [texts addObject:SGRLyricsHasWords(line) && !line.translation.length ? SGKaraokeLineText(line) ?: @"" : @""];
    return texts;
}

// The lines with what was made here taken off, as copies: a translator skips a line with a translation, and the
// page's lines keep theirs until the new one is in.
static NSArray<SGKaraokeLine *> *withoutMade(NSArray<SGKaraokeLine *> *lines) {
    NSMutableArray<SGKaraokeLine *> *sent = [NSMutableArray arrayWithCapacity:lines.count];
    for (SGKaraokeLine *line in lines) {
        if (!line.translationMade) {
            [sent addObject:line];
            continue;
        }
        SGKaraokeLine *copy = [line copy];
        copy.translation = nil;
        copy.translationMade = NO;
        [sent addObject:copy];
    }
    return sent;
}

- (void)loadSavedTranslationThen:(void (^)(void))done {
    NSString *track = _track, *language = SGLyricsGeminiLanguage();
    NSArray *lines = _lines;
    __weak SGRKaraokeView *weakSelf = self;
    SGLyricsLoadTranslation(track, language, lines, ^BOOL {
        SGRKaraokeView *view = weakSelf;
        return view && view->_lines == lines && [view->_track isEqual:track] &&
            [SGLyricsGeminiLanguage() isEqual:language];
    }, done);
}

// When each line is sung and where the breaks are, worked out once per song for the frames to read.
- (void)timeLines {
    free(_spans);
    free(_breaks);
    NSUInteger count = _lines.count;
    _spans = calloc(count + 1, sizeof(SGRKaraokeSpan));
    _breaks = calloc(count + 1, sizeof(SGRKaraokeBreak));
    _breakCount = 0;
    _hasSpoken = _hasTranslation = _untranslated = _hasNotes = NO;
    BOOL plain = _lines.count && SGKaraokeLinesTiming(_lines) == SGKaraokeTimingNone;
    if (_plain && !plain) {
        [_plainRelease invalidate];
        _plainRelease = nil;
        [self stir];
    }
    _plain = plain;
    if (!_sample) [self loadSavedTranslationThen:^{
        [self countTranslations];
        [self restyle];
    }];
    [self analyzeLanguage];
    if (!_sample) [self takeSavedAI];
    NSInteger sungTo = 0;   // the top of the song counts as where the singing before the first line ends
    for (NSUInteger i = 0; i < count; i++) {
        SGKaraokeLine *line = _lines[i];
        _spans[i] = (SGRKaraokeSpan){line.start, SGKaraokeSungEnd(line)};
        if (!_plain && line.start - sungTo >= kBreakMinMs) _breaks[_breakCount++] = (SGRKaraokeBreak){sungTo, line.start, (NSInteger)i};
        sungTo = MAX(sungTo, _spans[i].end);
        _hasSpoken = _hasSpoken || line.pronunciation || line.backing.pronunciation;
        _hasNotes = _hasNotes || line.note.length;
    }
    [self countTranslations];
    [self offerExtras];
    if (_languageReady) [self askMeanings];
    [self queueAutomaticTranslation];
}

- (void)countTranslations {
    _hasTranslation = _untranslated = _madeTranslation = NO;
    for (SGKaraokeLine *line in _lines) {
        _hasTranslation = _hasTranslation || line.translation.length;
        _untranslated = _untranslated || (!line.translation.length && SGRLyricsHasWords(line));
        _madeTranslation = _madeTranslation || (line.translationMade && line.translation.length);
    }
}

// Measures the song for the width and, once that is in, places it; Spotify's own lines stay in view
// until then, since the page shows nothing of its own before it has lines to show.
- (void)rebuild {
    if (!_languageReady) return;
    [self dropMeasuredLines];
    _browsing = NO;
    _scroll.contentOffset = CGPointZero;
    _builtWidth = self.bounds.size.width;
    CGFloat width = [self lineWidth];
    if (width <= 0) return;
    _font = [UIFont systemFontOfSize:_fontSize weight:UIFontWeightBold];
    SGRKaraokeStyle *style = _style = [self styleNow];
    NSArray<SGKaraokeLine *> *lines = layoutSnapshots(_lines);
    CGFloat gap = _lineGap;
    NSUInteger build = _build;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
        NSArray<NSNumber *> *tops = topsOf(lines, width, style, gap);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (build != self->_build) return;   // the song or the width moved on meanwhile
            [self takeTops:tops];
            [self placeLinesAnimated:NO];
        });
    });
}

#pragma mark - the pronunciation and the translation

// What a line shows besides its words: what the song has, of what the lyrics menu has switched on.
- (SGRKaraokeStyle *)styleNow {
    BOOL romanised = SGFlag(SGKeyLyricsRomanised, NO);
    // A preview shows whatever its sample lines have, the menu's switches being for songs.
    SGRKaraokeStyle *style = [[SGRKaraokeStyle alloc] initWithSize:_fontSize order:SGRLyricsTextOrder()
                                                     pronunciation:_hasSpoken && (_sample || SGFlag(SGRKeyLyricsPronunciation, NO))
                                                       translation:_hasTranslation && (_sample || SGFlag(SGRKeyLyricsTranslation, NO))
                                                         romanised:romanised];
    style.drawingStyle = SGRLyricsDrawingStyleForID(_sampleStyleIdentifier ?: SGRLyricsStyleNow());
    BOOL japanese = [[self songLanguage] isEqual:@"ja"];
    style.japanese = japanese;
    style.hangul = SGFlag(SGKeyLyricsPronunciationHangul, NO);
    style.hiragana = SGFlag(SGKeyLyricsJapaneseKana, NO);
    if (japanese && SGFlag(SGKeyLyricsFurigana, NO)) style.furigana = [style furiganaAt:round(_fontSize * kFuriganaShare)];
    if (_hasNotes && SGFlag(SGKeyLyricsCulturalNotes, NO)) style.note = [style noteAt:round(_fontSize * kNoteShare)];
    return style;
}

// A switch of the menu or the Lyrics page's order: the song is measured again in the new style off
// the main thread, as for a new width, but the lines on the page stay until it is in, and then the
// new ones crossfade over them where they were, so nothing blinks and nothing is lost of the place.
- (void)restyle {
    [self queueAutomaticTranslation];
    [self offerExtras];
    if (!_languageReady || !_lines || _builtWidth <= 0) return;
    if (!_tops) {
        [self rebuild];   // invalidate the pending measurement, which captured the previous style
        return;
    }
    SGRKaraokeStyle *style = [self styleNow];
    NSArray<SGKaraokeLine *> *lines = layoutSnapshots(_lines);
    CGFloat width = [self lineWidth], gap = _lineGap;
    NSUInteger build = ++_build;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
        NSArray<NSNumber *> *tops = topsOf(lines, width, style, gap);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (build != self->_build) return;
            [self showStyle:style tops:tops];
        });
    });
}

// topsOf's answer: the lines' tops, and the stack's end apart from them.
- (void)takeTops:(NSArray<NSNumber *> *)tops {
    _stackEnd = tops.lastObject.doubleValue;
    _tops = tops.count ? [tops subarrayWithRange:NSMakeRange(0, tops.count - 1)] : tops;
    if (!_sample && !_plain) {
        NSInteger now = [self positionMs];
        if (now >= 0) {
            _sungCount = [self sungAt:now into:_sung focus:&_focus openBreak:&_openBreak];
            _arrangement++;
            if (_openBreak < 0) [_dots removeFromSuperview];
        }
    }
}

- (NSNumber *)browseAnchorAt:(CGFloat *)viewportY {
    NSNumber *anchor = nil;
    *viewportY = CGFLOAT_MAX;
    if (_browsing) {
        CGRect viewport = _scroll.bounds;
        for (NSNumber *key in _shown) {
            CGRect frame = _shown[key].frame;
            CGFloat y = CGRectGetMinY(frame) - CGRectGetMinY(viewport);
            if (y >= 0 && y < *viewportY && CGRectGetMaxY(frame) <= CGRectGetMaxY(viewport)) {
                anchor = key;
                *viewportY = y;
            }
        }
    }
    return anchor;
}

- (void)restoreAnchor:(NSUInteger)index viewportY:(CGFloat)y {
    UIView *line = [self viewForLine:index];
    _scroll.contentOffset = CGPointMake(_scroll.contentOffset.x, CGRectGetMinY(line.frame) - y);
}

- (void)showStyle:(SGRKaraokeStyle *)style tops:(NSArray<NSNumber *> *)tops {
    CGFloat viewportY;
    NSNumber *anchor = [self browseAnchorAt:&viewportY];
    if (!_detached) {
        CATransition *fade = [CATransition animation];
        fade.type = kCATransitionFade;
        fade.duration = kRestyleFade;
        [_scroll.layer addAnimation:fade forKey:@"restyle"];
    }
    for (UIView *view in _shown.allValues) [self letGoOfLineView:(SGRKaraokeLineView *)view];
    [_shown removeAllObjects];
    _style = style;
    [self takeTops:tops];
    _sightArrangement = NSUIntegerMax;
    [self placeLinesAnimated:NO];
    if (anchor) [self restoreAnchor:anchor.unsignedIntegerValue viewportY:viewportY];
    [self showLinesInSight];   // placing stands still while the page is scrolled by hand; the views do not
    // A restyle's blur starts in place rather than easing in from sharp.
    for (SGRKaraokeLineView *view in _shown.allValues) [view.layer removeAnimationForKey:@"blur"];
}

// The button shows only for a song with a pronunciation or a translation to show, and its menu only
// what the song has: a switch for each, reading what tapping it will do.
- (void)offerExtras {
    NSString *language = SGLyricsGeminiLanguage();
    BOOL gemini = SGGeminiKeySet(), onDevice = SGFlag(SGKeyLyricsTranslateOnDevice, YES) && SGOnDeviceTranslation.translationAvailable;
    BOOL intelligence = SGFlag(SGKeyLyricsAppleIntelligence, YES) && [SGOnDeviceTranslation appleIntelligenceAvailable:language];
    // A translator is offered only for a song in another language than the one it would translate into.
    BOOL deepl = SGDeepLKeySet(), google = SGFlag(SGKeyLyricsGoogleTranslate, NO), openai = SGOpenAIKeySet();
    BOOL bing = SGFlag(SGKeyLyricsBingTranslate, NO), claude = SGClaudeKeySet();
    BOOL anyTranslator = gemini || onDevice || intelligence || deepl || google || bing || openai || claude;
    BOOL translatable = SGRLyricsShouldTranslate(_foreign) && _untranslated && anyTranslator;
    // Sync and Search LRCLIB are there for every song with lines, so the button is too; its glyph says
    // translate only while it has a pronunciation or a translation to offer.
    BOOL pipOffered = SGRedesignedUI() && SGLyricsPiPEnabled() && !_sample;
    BOOL offered = (_lines || pipOffered) && !_sample && _track.length;
    BOOL languages = _hasSpoken || _hasTranslation || translatable;
    if (!offered) {
        _extrasBox.hidden = YES;
        [self refreshTranslationStatus];
        [self setNeedsLayout];
        return;
    }
    if (!_extras) {
        // The Kit's glass, as the mic across from it has (setExtrasHidden:), which turns solid under Reduce
        // Transparency, with a plain button over it.
        _extrasBox = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kExtrasSide, kExtrasSide)];
        _extrasBox.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
        config.image = [UIImage systemImageNamed:@"translate"];
        config.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:kExtrasGlyph weight:UIImageSymbolWeightSemibold];
        config.baseForegroundColor = UIColor.whiteColor;
        _extras = [UIButton buttonWithConfiguration:config primaryAction:nil];
        _extras.frame = _extrasBox.bounds;
        _extras.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _extras.showsMenuAsPrimaryAction = YES;
        _extras.preferredMenuElementOrder = UIContextMenuConfigurationElementOrderFixed;
        _extras.accessibilityLabel = SGL(@"settings.lyricstools.menu.label", @"Lyrics options");
        [_extrasBox addSubview:_extras];
        [self addSubview:_extrasBox];
        self.extrasHidden = _extrasHidden;
    }
    // While a translation is worked out the glyph turns into a spinner, and the menu has nothing to ask a second time.
    BOOL translating = SGRTranslationJobRunning(_track, language) || (_asking && _asking == _lines);
    UIButtonConfiguration *config = _extras.configuration;
    NSString *glyph = languages ? @"translate" : @"ellipsis";
    if (config.showsActivityIndicator != translating || ![_extrasGlyph isEqualToString:glyph]) {
        config.showsActivityIndicator = translating;
        config.image = [UIImage systemImageNamed:glyph];
        _extrasGlyph = glyph;
        _extras.configuration = config;
        _extras.accessibilityValue = translating ? SGL(@"settings.lyricstools.menu.translating", @"Translating") : nil;
    }
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
    if (pipOffered) {
        BOOL close = SGLyricsPiPActive() || SGLyricsPiPStarting();
        __weak SGRKaraokeView *weakSelf = self;
        [items addObject:[UIAction actionWithTitle:close ? SGL(@"settings.lyrics.pip.close", @"Close Picture in Picture")
                                                        : SGL(@"settings.lyrics.pip.show", @"Show in Picture in Picture")
            image:[UIImage systemImageNamed:close ? @"pip.exit" : @"pip.enter"] identifier:nil
            handler:^(UIAction *action) { SGLyricsPiPToggle(weakSelf); }]];
    }
    // With readings enabled the style already shows the provider's pronunciation in that slot.
    if (_hasSpoken && !SGFlag(SGKeyLyricsRomanised, NO)) {
        BOOL on = SGFlag(SGRKeyLyricsPronunciation, NO);
        [items addObject:[UIAction actionWithTitle:on ? SGL(@"settings.lyricstools.menu.pronunciation.hide", @"Hide Pronunciation")
                                                      : SGL(@"settings.lyricstools.menu.pronunciation.show", @"Show Pronunciation")
                                             image:[UIImage systemImageNamed:@"character.phonetic"] identifier:nil
                                           handler:^(UIAction *action) { SGRSetLyricsTextShown(SGRLyricsTextPronunciation, !on); }]];
    }
    // A switch of what shows, for every song; Remove Translation below is what takes this song's away.
    if (_hasTranslation || (SGRAutoTranslationEnabled() && SGRLyricsShouldTranslate(_foreign))) {
        BOOL on = SGFlag(SGRKeyLyricsTranslation, NO);
        UIAction *shown = [UIAction actionWithTitle:on ? SGL(@"settings.lyricstools.menu.translation.hide", @"Hide Translation")
                                                       : SGL(@"settings.lyricstools.menu.translation.show", @"Show Translation")
                                              image:[UIImage systemImageNamed:@"character.bubble"] identifier:nil
                                            handler:^(UIAction *action) { SGRSetLyricsTextShown(SGRLyricsTextTranslation, !on); }];
        shown.subtitle = SGL(@"settings.lyricstools.menu.translation.scope", @"For all songs");
        [items addObject:shown];
    }
    // Also for a song a source translated in part, as Musixmatch's community often has: the rest is filled in.
    // Said in each item: whether the song's words stay on the phone. Once a translation was made here, the same
    // items go under Translate Again, which replaces it with another service's.
    // Each item keeps the song and language it was offered for: a menu left open while the song changes acts on
    // that song or not at all.
    BOOL again = _madeTranslation;
    NSString *menuTrack = _track;
    if (!translating && (again ? anyTranslator : translatable)) {
        __weak SGRKaraokeView *weakSelf = self;
        NSMutableArray<UIMenuElement *> *translators = [NSMutableArray array];
        void (^offer)(NSString *, NSString *, NSString *, SGRTranslator) = ^(NSString *title, NSString *glyph, NSString *subtitle, SGRTranslator translator) {
            UIAction *action = [UIAction actionWithTitle:title image:[UIImage systemImageNamed:glyph] identifier:nil
                                                 handler:^(UIAction *action) { [weakSelf translateWith:translator again:again track:menuTrack language:language]; }];
            action.subtitle = subtitle;
            [translators addObject:action];
        };
        if (onDevice) {
            offer(SGL(@"settings.translation.ondevice.title", @"Translate on iPhone"), @"translate", SGL(@"settings.lyricstools.menu.ondevice.subtitle", @"Apple's Translate, on this iPhone"),
                  ^(NSArray<SGKaraokeLine *> *lines, NSString *track, NSString *to, SGRTranslated progress, SGRTranslated done) {
                [SGOnDeviceTranslation translate:textsOf(lines) to:to from:weakSelf done:done];
            });
        }
        if (intelligence) {
            offer(SGL(@"settings.lyricstools.menu.intelligence", @"Translate with Apple Intelligence"), @"apple.intelligence", SGL(@"settings.lyrics.auto_translation.intelligence.note", @"On this iPhone"),
                  ^(NSArray<SGKaraokeLine *> *lines, NSString *track, NSString *to, SGRTranslated progress, SGRTranslated done) {
                [SGOnDeviceTranslation translateWithAppleIntelligence:textsOf(lines) to:to song:SGLyricsSongName(track) progress:^(NSArray<NSString *> *soFar) { progress(soFar, nil); } done:done];
            });
        }
        if (gemini) offer(SGL(@"settings.lyricstools.menu.gemini", @"Translate with Gemini"), @"sparkles", SGL(@"settings.lyricstools.menu.gemini.subtitle", @"Sends the lyrics to Google"), ^(NSArray<SGKaraokeLine *> *lines, NSString *track, NSString *to, SGRTranslated progress, SGRTranslated done) {
            SGLyricsTranslateWithGemini(track, lines, to, done);
        });
        if (deepl) offer(SGL(@"settings.lyricstools.menu.deepl", @"Translate with DeepL"), @"character.book.closed",
                         SGL(@"settings.lyricstools.menu.deepl.subtitle", @"Sends the lyrics to DeepL"),
                         ^(NSArray<SGKaraokeLine *> *lines, NSString *track, NSString *to, SGRTranslated progress, SGRTranslated done) {
            SGLyricsTranslateWithDeepL(track, lines, to, done);
        });
        if (google) offer(SGL(@"settings.lyricstools.menu.google", @"Translate with Google"), @"globe",
                          SGL(@"settings.lyricstools.menu.google.subtitle", @"Sends the lyrics to Google Translate"),
                          ^(NSArray<SGKaraokeLine *> *lines, NSString *track, NSString *to, SGRTranslated progress, SGRTranslated done) {
            SGLyricsTranslateWithGoogle(track, lines, to, done);
        });
        if (bing) offer(SGL(@"settings.lyricstools.menu.bing", @"Translate with Bing"), @"globe.americas",
                        SGL(@"settings.lyricstools.menu.bing.subtitle", @"Sends the lyrics to Bing Translator"),
                        ^(NSArray<SGKaraokeLine *> *lines, NSString *track, NSString *to, SGRTranslated progress, SGRTranslated done) {
            SGLyricsTranslateWithBing(track, lines, to, done);
        });
        if (claude) offer(SGL(@"settings.lyricstools.menu.claude", @"Translate with Claude"), @"sparkle",
                          SGL(@"settings.lyricstools.menu.claude.subtitle", @"Sends the lyrics to Anthropic"),
                          ^(NSArray<SGKaraokeLine *> *lines, NSString *track, NSString *to, SGRTranslated progress, SGRTranslated done) {
            SGLyricsTranslateWithClaude(track, lines, to, done);
        });
        if (openai) offer(SGL(@"settings.lyricstools.menu.openai", @"Translate with your AI service"), @"cpu",
                          SGL(@"settings.lyricstools.menu.openai.subtitle", @"Sends the lyrics to the service you set"),
                          ^(NSArray<SGKaraokeLine *> *lines, NSString *track, NSString *to, SGRTranslated progress, SGRTranslated done) {
            SGLyricsTranslateWithOpenAI(track, lines, to, done);
        });
        if (again) {
            UIMenu *menu = [UIMenu menuWithTitle:SGL(@"settings.lyricstools.menu.retranslate", @"Translate Again")
                                           image:[UIImage systemImageNamed:@"arrow.triangle.2.circlepath"] identifier:nil options:0 children:translators];
            menu.subtitle = SGL(@"settings.lyricstools.menu.retranslate.subtitle", @"Replaces the translation made here");
            [items addObject:menu];
        } else [items addObjectsFromArray:translators];
    }
    // Also while a translation is worked out, which it stops.
    if (_madeTranslation) {
        __weak SGRKaraokeView *weakSelf = self;
        UIAction *remove = [UIAction actionWithTitle:SGL(@"settings.lyricstools.menu.translation.remove", @"Remove Translation")
                                               image:[UIImage systemImageNamed:@"trash"] identifier:nil
                                             handler:^(UIAction *action) { [weakSelf removeTranslationOf:menuTrack language:language]; }];
        remove.attributes = UIMenuElementAttributesDestructive;
        remove.subtitle = SGL(@"settings.lyricstools.menu.translation.remove.subtitle", @"This song only");
        [items addObject:remove];
    }
    // An AI service the user set up writes how each line sounds, or explains the lines a listener would miss.
    NSArray<NSNumber *> *services = SGLyricsAIAvailable();
    BOOL asking = _asking && _asking == _lines;
    if (services.count && !asking) {
        __weak SGRKaraokeView *weakSelf = self;
        NSMutableArray<UIMenuElement *> *pronounce = [NSMutableArray array], *explain = [NSMutableArray array];
        for (NSNumber *service in services) {
            SGLyricsAI ai = service.integerValue;
            NSString *name = SGLyricsAIName(ai);
            [pronounce addObject:[UIAction actionWithTitle:name image:nil identifier:nil handler:^(UIAction *action) {
                [weakSelf askAI:ai notes:NO track:menuTrack language:language];
            }]];
            [explain addObject:[UIAction actionWithTitle:name image:nil identifier:nil handler:^(UIAction *action) {
                [weakSelf askAI:ai notes:YES track:menuTrack language:language];
            }]];
        }
        UIMenu *spoken = [UIMenu menuWithTitle:SGL(@"settings.lyricstools.menu.pronounce", @"Write Pronunciation") image:[UIImage systemImageNamed:@"waveform"]
                                    identifier:nil options:0 children:pronounce];
        spoken.subtitle = [NSString stringWithFormat:SGL(@"settings.lyricstools.menu.pronounce.subtitle", @"Sends the lyrics to %@"),
                           services.count == 1 ? SGLyricsAIName(services.firstObject.integerValue) : SGL(@"settings.lyricstools.menu.ai.service", @"the service you pick")];
        [items addObject:spoken];
        if (SGFlag(SGKeyLyricsCulturalNotes, NO)) {
            if (_hasNotes) {
                [items addObject:[UIAction actionWithTitle:SGL(@"settings.lyricstools.menu.notes.hide", @"Hide Cultural Notes") image:[UIImage systemImageNamed:@"text.bubble"]
                                                identifier:nil handler:^(UIAction *action) {
                    SGSetEnabled(SGKeyLyricsCulturalNotes, NO);
                    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil];
                }]];
            } else {
                UIMenu *notes = [UIMenu menuWithTitle:SGL(@"settings.lyricstools.menu.notes", @"Explain References") image:[UIImage systemImageNamed:@"text.bubble"]
                                           identifier:nil options:0 children:explain];
                notes.subtitle = SGL(@"settings.lyricstools.menu.notes.subtitle", @"Notes under the lines that need them");
                [items addObject:notes];
            }
        }
    }
    // The song's own tools, under the languages: its timing, and which lyrics it gets. Asked as the menu opens, so
    // the heading names the timing and the source as they are then, which settle after the lines come in.
    NSString *track = _track;
    __weak SGRKaraokeView *weakSelf = self;
    UIDeferredMenuElement *tools = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
        completion(@[[SGRKaraokeView songToolsFor:track view:weakSelf]]);
    }];
    UIMenu *songLanguage = SGRSongLanguageMenu(track, _detectedLanguage, ^{ [weakSelf translationsChanged]; });
    NSMutableArray<UIMenuElement *> *groups = [NSMutableArray array];
    if (items.count) [groups addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:items]];
    [groups addObject:songLanguage];
    [groups addObject:tools];
    _extras.menu = [UIMenu menuWithChildren:groups];
    _extrasBox.hidden = NO;
    [self refreshTranslationStatus];
    [self setNeedsLayout];
}

// Sync, Search LRCLIB and Reload Lyrics as they always were, under a heading of how the lines shown are timed and
// where they came from; for lines timed by the line, the word estimate's switch above them, which applies at once.
+ (UIMenu *)songToolsFor:(NSString *)track view:(SGRKaraokeView *)view {
    UIAction *sync = [UIAction actionWithTitle:SGL(@"settings.lyricstools.menu.sync", @"Sync") image:[UIImage systemImageNamed:@"timer"] identifier:nil
                                       handler:^(UIAction *action) { SGRShowLyricsSync(track); }];
    sync.subtitle = SGRLyricsSyncSummary(track);
    UIAction *search = [UIAction actionWithTitle:SGL(@"settings.lyricstools.menu.search", @"Search LRCLIB") image:[UIImage systemImageNamed:@"magnifyingglass"] identifier:nil
                                         handler:^(UIAction *action) { SGRShowLyricsSearch(track); }];
    if (SGLyricsPinnedID(track)) search.subtitle = SGL(@"settings.lyricstools.menu.search.pinned", @"Picked by hand");
    UIAction *reload = [UIAction actionWithTitle:SGL(@"settings.lyricstools.menu.reload", @"Reload Lyrics") image:[UIImage systemImageNamed:@"arrow.clockwise"] identifier:nil
                                         handler:^(UIAction *action) { SGLyricsReload(track); }];
    NSMutableArray<UIMenuElement *> *children = [NSMutableArray array];
    // Only the lines this view shows for the same song say anything about timing.
    NSArray<SGKaraokeLine *> *lines = view && [view->_track isEqual:track] ? view->_lines : nil;
    NSString *heading = @"";
    if (lines.count) {
        SGKaraokeTiming timing = SGKaraokeLinesTiming(lines);
        BOOL estimates = SGFlag(SGKeyLyricsSimulateWords, NO);
        NSString *kind = timing == SGKaraokeTimingWords ? SGL(@"settings.lyricstools.menu.timing.words", @"Synced word by word")
            : timing == SGKaraokeTimingLine ? (estimates ? SGL(@"settings.lyricstools.menu.timing.estimated", @"Synced by line, words estimated")
                                                         : SGL(@"settings.lyricstools.menu.timing.line", @"Synced by line"))
            : SGL(@"settings.lyricstools.menu.timing.plain", @"Not synced");
        NSString *source = SGLyricsCreditFor(track);
        heading = source.length ? [NSString stringWithFormat:SGL(@"settings.lyricstools.menu.timing.source", @"%@ · from %@"), kind, source] : kind;
        if (timing == SGKaraokeTimingLine) {
            UIAction *estimate = [UIAction actionWithTitle:SGL(@"settings.lyricstools.menu.simulate_words", @"Simulate Word Timing")
                                                     image:[UIImage systemImageNamed:@"wand.and.rays"] identifier:nil handler:^(UIAction *action) {
                SGSetEnabled(SGKeyLyricsSimulateWords, !estimates);
                [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsWordTimingDidChangeNotification object:nil];
            }];
            estimate.state = estimates ? UIMenuElementStateOn : UIMenuElementStateOff;
            estimate.subtitle = SGL(@"settings.lyricstools.menu.simulate_words.scope", @"For all songs");
            [children addObject:estimate];
        }
    }
    [children addObjectsFromArray:@[sync, search, reload]];
    return [UIMenu menuWithTitle:heading image:nil identifier:nil options:UIMenuOptionsDisplayInline children:children];
}

// The Lyrics page's switch or the menu's: the lines are measured again and crossfaded, the estimated words swept or not.
- (void)wordTimingChanged {
    BOOL sweeps = SGFlag(SGKeyLyricsSimulateWords, NO);
    if (sweeps == _sweepsEstimates) return;
    _sweepsEstimates = sweeps;
    [self restyle];
}

#pragma mark - automatic translation's note

// Only for the song and language on screen, with translations shown; nothing for the preview or a restored result,
// which has no snapshot. A finished translation needs no note, and neither does an ended one whose lines are all
// translated by now (a source's translations coming in late): the lines are read again here rather than trusting
// _untranslated, since lines shared with the other view can take translations without this view recounting.
- (void)refreshTranslationStatus {
    if (!_status) return;
    NSString *language = SGLyricsGeminiLanguage();
    SGRAutoTranslationProgress *progress = nil;
    if (!_sample && self.window && _lines.count && _track.length && language.length && SGFlag(SGRKeyLyricsTranslation, NO))
        progress = SGRAutoTranslationProgressFor(_track, language);
    if (progress.phase == SGRAutoTranslationPhaseComplete) progress = nil;
    if (progress && progress.phase != SGRAutoTranslationPhaseRunning) {
        BOOL untranslated = NO;
        for (SGKaraokeLine *line in _lines) {
            if (!line.translation.length && SGRLyricsHasWords(line)) { untranslated = YES; break; }
        }
        if (!untranslated) progress = nil;
    }
    [_status showProgress:progress track:_track language:language];
}

- (void)translationProgressChanged:(NSNotification *)note {
    if (_sample || !_status) return;
    if (note.object && ![note.object isEqual:_track]) return;
    NSString *language = note.userInfo[@"language"];
    if (language && ![language isEqual:SGLyricsGeminiLanguage()]) return;
    [self refreshTranslationStatus];
}

// The note's Retry, for the song and language it was drawn for: a note left from another song or language does nothing.
- (void)retryTranslationOf:(NSString *)track language:(NSString *)language {
    if (!_sample && [track isEqual:_track] && [language isEqual:SGLyricsGeminiLanguage()] && SGRAutoTranslationRetry(track, language))
        [self queueAutomaticTranslation];
    [self refreshTranslationStatus];
}

// Settle source/rule updates before requesting. No work is scheduled by the display link's per-frame path.
- (void)queueAutomaticTranslation {
    if (_autoQueued || _sample || !self.window || !_lines.count || !SGRAutoTranslationEnabled()) return;
    SGRAutoTranslationRevision(); // Install settings/store observers even while translation display is hidden.
    _autoQueued = YES;
    __weak SGRKaraokeView *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SGRKaraokeView *view = weakSelf;
        if (!view) return;
        view->_autoQueued = NO;
        [view automaticTranslationIfNeeded];
    });
}
- (void)autoTranslationSettingsChanged {
    [self offerExtras];
    [self queueAutomaticTranslation];
}
- (UIView *)translationCover {
    for (UIView *view = self; view; view = view.superview) if (view.hidden || view.alpha < 0.01) return view;
    return nil;
}

- (BOOL)visibleForTranslationOf:(NSString *)track {
    if (!self.window || ![_track isEqual:track] || ![track isEqual:SGKaraokePlayingTrack()] ||
        UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return NO;
    return ![self translationCover];
}

static char kTranslationCoverContext;

- (void)stopWatchingTranslationCover {
    if (_alertCover) [_alertCover removeObserver:self forKeyPath:_coverKey context:&kTranslationCoverContext];
    _alertCover = nil;
    _coverKey = nil;
}

- (void)leaveTranslationPage {
    ++_translationPage;
    _translationAlert = nil;
    [self stopWatchingTranslationCover];
}

- (void)presentPendingTranslationAlert {
    if (!_translationAlert) return;
    [self stopWatchingTranslationCover];
    if (!self.window || ![_track isEqual:SGKaraokePlayingTrack()]) {
        _translationAlert = nil;
        return;
    }
    if (_inactive || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    UIView *cover = [self translationCover];
    if (cover) {
        // Only an outstanding error watches visibility; no display tick or retry timer.
        _alertCover = cover;
        _coverKey = cover.hidden ? @"hidden" : @"alpha";
        [cover addObserver:self forKeyPath:_coverKey options:0 context:&kTranslationCoverContext];
        return;
    }
    UIAlertController *alert = _translationAlert;
    _translationAlert = nil;
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == &kTranslationCoverContext) [self presentPendingTranslationAlert];
    else [super observeValueForKeyPath:path ofObject:object change:change context:context];
}
- (BOOL)automaticTranslationVisible {
    return _languageReady && !_sample && _lines.count && SGFlag(SGRKeyLyricsTranslation, NO) &&
        [self visibleForTranslationOf:_track] && SGRLyricsTranslationAllowed(_track, _detectedLanguage);
}
- (void)automaticTranslationIfNeeded {
    if (![self automaticTranslationVisible]) return;
    if (!SGRLyricsShouldTranslate(_foreign)) return;
    [self loadSavedTranslationThen:^{ [self automaticTranslationAfterSavedLoad]; }];
}
- (void)automaticTranslationAfterSavedLoad {
    if (![self automaticTranslationVisible] || !SGRLyricsShouldTranslate(_foreign)) return;
    NSString *language = SGLyricsGeminiLanguage();
    [self countTranslations];
    if (!SGRAutoTranslationEnabled() || !_untranslated || SGRTranslationJobRunning(_track, language)) return;
    BOOL available = NO;
    for (NSNumber *provider in SGRAutoTranslationOrder()) available = available || SGRAutoTranslationAvailable(provider.integerValue, language);
    if (!available) {
        SGRAutoTranslationUnavailable(_track, language);
        return;
    }
    NSUInteger revision = SGRAutoTranslationClaim(_track, language);
    if (!revision) return;
    __weak SGRKaraokeView *weakSelf = self;
    [self translateWith:^(NSArray *lines, NSString *track, NSString *to, SGRTranslated progress, SGRTranslated done) {
        SGRAutoTranslateInOrder(lines, track, to, revision, ^BOOL {
            SGRKaraokeView *view = weakSelf;
            return view && [view->_track isEqual:track] && [view automaticTranslationVisible];
        }, progress, done);
    } again:NO track:_track language:language automaticRevision:revision];
}

// The song's lines into the Lyrics page's language, or the phone's: each line without a translation, or with one
// made here, takes the translator's. The whole song goes, for the sense; asked again, with what was made here taken
// off, and the page keeps that until the new one is in. Translations are switched on as it is asked, and only then,
// so hiding them while it works stands. An answer a newer one, a removal or another language overtook changes nothing.
- (void)translateWith:(SGRTranslator)translator again:(BOOL)again track:(NSString *)asked language:(NSString *)askedIn {
    if (![_track isEqual:asked] || ![SGLyricsGeminiLanguage() isEqual:askedIn]) return;
    SGRAutoTranslationSuppress(asked, askedIn); // An explicit manual choice owns this song for the session.
    [self translateWith:translator again:again track:asked language:askedIn automaticRevision:0];
}
- (void)translateWith:(SGRTranslator)translator again:(BOOL)again track:(NSString *)asked language:(NSString *)askedIn automaticRevision:(NSUInteger)automaticRevision {
    NSArray<SGKaraokeLine *> *lines = _lines;
    NSString *track = _track, *language = SGLyricsGeminiLanguage();
    if (![track isEqualToString:asked] || ![language isEqualToString:askedIn]) return;   // a menu from before the song or the language changed
    BOOL had = SGLyricsHasTranslations(lines);
    __weak SGRKaraokeView *origin = self;
    NSUInteger page = _translationPage;
    SGRTranslateLyrics(lines, track, language, automaticRevision,
    ^(NSArray *sent, NSString *song, NSString *to, SGRTranslated progress, SGRTranslated done) {
        translator(again ? withoutMade(sent) : sent, song, to, progress, done);
    }, ^{
        if (!automaticRevision && !SGFlag(SGRKeyLyricsTranslation, NO)) SGRSetLyricsTextShown(SGRLyricsTextTranslation, YES);
    }, ^(NSArray<NSString *> *translations, NSString *error) {
        SGRKaraokeView *view = origin;
        if (error && !automaticRevision && view && view->_translationPage == page && [view->_track isEqual:track]) {
            BOOL needsDownload = [error isEqualToString:@"retrine.translation.languagesMissing"];
            NSString *detail = needsDownload ? SGL(@"settings.translation.download.message", @"Download the song's language and your translation language in Settings > Apps > Translate > Languages, then try again.") : error;
            NSString *message = had ? [NSString stringWithFormat:@"%@\n\n%@", detail, SGL(@"settings.lyricstools.translation.kept", @"Lines that could not be translated keep their previous translation.")] : detail;
            NSString *title = needsDownload ? SGL(@"settings.translation.download.title", @"Language not downloaded") : (translations ? SGL(@"settings.translation.partial.title", @"Partly translated") : SGL(@"settings.translation.none.title", @"No translation"));
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                           message:message preferredStyle:UIAlertControllerStyleAlert];
            // Over the player, which is dark whatever the system's appearance.
            alert.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
            if (needsDownload) {
                [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
                UIAlertAction *open = [UIAlertAction actionWithTitle:SGL(@"settings.translation.download.open", @"Open Settings") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    [SGOnDeviceTranslation openTranslateSettings];
                }];
                [alert addAction:open];
                alert.preferredAction = open;
            } else {
                [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.ok", @"OK") style:UIAlertActionStyleCancel handler:nil]];
            }
            view->_translationAlert = alert;
            [view presentPendingTranslationAlert];
        }
    });
}

// The translation made here for the song and language the menu was offered for deleted, and any job for it with it:
// in every lyrics view of that song the lines go back to what the lyrics came with.
- (void)removeTranslationOf:(NSString *)track language:(NSString *)language {
    if (!track.length || !language.length) return;
    SGRAutoTranslationSuppress(track, language);
    SGLyricsDeleteTranslationWithCompletion(track, language, ^(NSError *error) {
        if (error) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.lyricstools.menu.translation.remove", @"Remove Translation")
                message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.ok", @"OK") style:UIAlertActionStyleCancel handler:nil]];
            SGPresentDark(alert);
            [SGTopController() presentViewController:alert animated:YES completion:nil];
        }
    });
    SGRForgetTranslationJob(track, language);
    SGRTranslationChanged(track, language, kTranslationRemoved);
}

// A translation of this song started, stopped, was saved or was removed, from this view or the other. Its lines are
// synced only for the language this view asks in; the menu follows either way.
- (void)translationDidChange:(NSNotification *)note {
    if (!_lines || _sample || ![note.object isEqual:_track]) return;
    NSString *language = SGLyricsGeminiLanguage();
    if (![note.userInfo[kTranslationLanguage] isEqual:language]) [self offerExtras];
    else if (note.userInfo[kTranslationRemoved]) {
        // Removal owns the live state immediately; disk completion must not clear a newer answer.
        for (SGKaraokeLine *line in _lines) {
            if (!line.translationMade) continue;
            line.translation = nil;
            line.translationMade = NO;
        }
        [self countTranslations];
        [self offerExtras];
        [self restyle];
    } else if (note.userInfo[kTranslationLines]) {
        [self loadSavedTranslationThen:^{
            [self countTranslations];
            [self restyle];
        }];
    } else [self offerExtras];
}

// A rule kept for the song's language sets the translation and pronunciation switches as the song comes in,
// once per song, so a pick made from the menu afterwards stands until the next one.
- (NSString *)songLanguage {
    return (_sample ? nil : SGLyricsTrackLanguage(_track)) ?: _detectedLanguage;
}

- (void)analyzeLanguage {
    NSUInteger request = ++_languageRequest;
    NSArray *lines = _lines;
    NSString *track = _track, *target = SGLyricsGeminiLanguage();
    _languageReady = NO;
    _foreign = YES; // Too little evidence counts as foreign; no automatic request starts before the answer.
    _detectedLanguage = nil;
    __block BOOL immediate = YES;
    __weak SGRKaraokeView *weakSelf = self;
    SGRAnalyzeLyricsLanguage(lines, target, ^(BOOL foreign, NSString *detected) {
        SGRKaraokeView *view = weakSelf;
        if (!view || request != view->_languageRequest || lines != view->_lines ||
            ![track isEqual:view->_track] || ![target isEqual:SGLyricsGeminiLanguage()]) return;
        view->_foreign = foreign;
        view->_detectedLanguage = detected;
        view->_languageReady = YES;
        if (!view->_sample) [view followLanguageRule];
        if (immediate) return;
        // First presentation waits for the same language/style the synchronous path used.
        // Already rendered lines remain in place; language work never clears them or resets scrolling.
        if (!view->_tops) [view rebuild];
        else [view restyle];
        [view offerExtras];
        [view askMeanings];
        [view queueAutomaticTranslation];
    });
    immediate = NO;
}

- (void)followLanguageRule {
    // Once per song for every lyrics view there is: the player's and the full screen page's each have one, and the
    // second opened must not undo a switch flipped by hand in the first.
    static NSString *ruled;
    // Only the view showing the song that plays: one left behind on another song must not mark that song applied.
    if (!_track || ![_track isEqualToString:SGKaraokePlayingTrack()] || [ruled isEqualToString:_track]) return;
    ruled = _track;
    NSString *track = _track;
    NSString *language = [self songLanguage];
    BOOL translation = NO, pronunciation = NO;
    if (!language || !SGLyricsLanguageRule(language, &translation, &pronunciation)) return;
    SGLog(@"karaoke: %@ is in %@, which shows %@translation and %@pronunciation", _track, language,
          translation ? @"" : @"no ", pronunciation ? @"" : @"no ");
    // Posted after this pass, so the restyle the switches ask for measures the lines this pass has timed.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![SGKaraokePlayingTrack() isEqualToString:track]) return;   // the song moved on meanwhile
        if (SGFlag(SGRKeyLyricsTranslation, NO) != translation) SGRSetLyricsTextShown(SGRLyricsTextTranslation, translation);
        if (SGFlag(SGRKeyLyricsPronunciation, NO) != pronunciation) SGRSetLyricsTextShown(SGRLyricsTextPronunciation, pronunciation);
    });
}

// What an AI service wrote for the song before, in the notation and the language asked now, laid back over its
// lines: a pronunciation where the source has none, a note where the line has one.
- (void)takeSavedAI {
    NSString *notation = [NSString stringWithFormat:@"%ld", (long)SGInt(SGKeyLyricsPronunciationNotation, 0)];
    NSString *language = SGLyricsGeminiLanguage();
    NSDictionary<NSString *, NSString *> *spoken = SGLyricsAIValues(@"pronunciation", _track, notation);
    NSDictionary<NSString *, NSString *> *notes = !SGFlag(SGKeyLyricsCulturalNotes, NO) ? nil
        : SGLyricsAIValues(@"notes", _track, language);
    for (SGKaraokeLine *line in _lines) {
        NSString *text = SGKaraokeLineText(line);
        if (!text.length) continue;
        // A source's own pronunciation stays; one an AI service wrote follows what is saved now, in the notation set
        // now, and goes with it when the saved answers are deleted.
        NSString *sound = spoken[text];
        if (line.pronunciation && !line.pronunciationMade) {
        } else if (sound.length) {
            SGKaraokeLine *made = SGLyricsPronunciation(nil, sound, line);
            if (made && ![SGKaraokeLineText(made) isEqualToString:SGKaraokeLineText(line.pronunciation)]) {
                line.pronunciation = made;
                line.pronunciationMade = YES;
            }
        } else if (line.pronunciationMade) {
            // Taken off once nothing for the song in the notation set covers the line any more: the saved answers
            // were deleted, or the notation changed.
            line.pronunciation = nil;
            line.pronunciationMade = NO;
        }
        NSString *note = notes[text];
        if (note.length && ![line.note isEqualToString:note]) {
            line.note = note;
        }
        if (!note.length && line.note) {
            line.note = nil;
        }
    }
    _hasSpoken = _hasNotes = NO;
    for (SGKaraokeLine *line in _lines) {
        _hasSpoken = _hasSpoken || line.pronunciation || line.backing.pronunciation;
        _hasNotes = _hasNotes || line.note.length;
    }
}

- (void)aiResultsChanged:(NSNotification *)note {
    if (_sample || !_lines || (note.object && ![note.object isEqual:_track])) return;
    [self takeSavedAI];   // Recount even when another view already mutated these same objects.
    [self restyle];
}

// Asks the service for the song's pronunciation or its notes, keeps the answer for the song, and shows it.
- (void)askAI:(SGLyricsAI)service notes:(BOOL)notes track:(NSString *)asked language:(NSString *)askedIn {
    if (![_track isEqualToString:asked] || ![SGLyricsGeminiLanguage() isEqualToString:askedIn]) return;
    NSArray<SGKaraokeLine *> *lines = _lines;
    NSString *track = _track, *language = SGLyricsGeminiLanguage();
    NSString *notation = [NSString stringWithFormat:@"%ld", (long)SGInt(SGKeyLyricsPronunciationNotation, 0)];
    if (!lines.count || _asking == lines) return;
    _asking = lines;
    [self offerExtras];
    // The service keeps what it was given for the song (AIServices.m); the lines read it back from there.
    void (^answered)(NSArray<NSString *> *, NSString *) = ^(NSArray<NSString *> *values, NSString *error) {
        if (self->_asking == lines) self->_asking = nil;
        NSString *currentNotation = [NSString stringWithFormat:@"%ld", (long)SGInt(SGKeyLyricsPronunciationNotation, 0)];
        BOOL sameContext = lines == self->_lines && [track isEqual:self->_track] &&
            [language isEqual:SGLyricsGeminiLanguage()] && (notes || [notation isEqual:currentNotation]);
        if (values.count == lines.count && sameContext) {
            [self takeSavedAI];
            [self restyle];
        }
        [self offerExtras];
        if (!sameContext || !error) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:notes ? SGL(@"settings.lyricstools.notes.failed", @"No Notes")
                                                                                     : SGL(@"settings.lyricstools.pronounce.failed", @"No Pronunciation")
                                                                       message:error preferredStyle:UIAlertControllerStyleAlert];
        alert.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.ok", @"OK") style:UIAlertActionStyleCancel handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    };
    if (!notes && !SGFlag(SGRKeyLyricsPronunciation, NO)) SGRSetLyricsTextShown(SGRLyricsTextPronunciation, YES);
    if (notes) SGLyricsAINotes(service, track, lines, language, answered);
    else SGLyricsAIPronounce(service, track, lines, answered);
}

// A source picked from the player's ⋯ replaces the lines of the song playing, which the page otherwise keeps
// through any later answer: they are dropped as on a change of track, and the next tick takes the new ones.
- (void)sourceChosen:(NSNotification *)note {
    if (_sample || ![note.object isEqual:_track]) return;
    [self dropLines];
}

- (void)dropLines {
    [self stir];
    if (_plain) {
        [_plainRelease invalidate];
        _plainRelease = nil;
        _plain = NO;
    }
    _lines = nil;
    _builtWidth = 0;
    [self creditTo:nil];
    [self dropMeasuredLines];
    [self offerExtras];
}

// Saved translations deleted, the target language changed, or Translate any song switched: sync and redraw.
- (void)translationsChanged {
    if (!_lines) return;
    [self timeLines];
    [self restyle];
}

// Where a line starts on the page, for the stack as it is arranged now: an open break holds the room
// of one row at the anchor, and the lines from the one after it on are moved down by it.
//
// While the page is scrolled by hand the stack stands still, and so does what places it: the room can
// change meanwhile (the player's controls go as a scroll starts, and the anchor moves with the height)
// and a break can open or close, and a line made for the view then went by the new anchor while the
// lines beside it kept the old one, the two running into each other.
- (CGFloat)topOfLine:(NSInteger)index {
    CGFloat anchor = _browsing ? _browseAnchor : [self restingAnchor];
    NSInteger openBreak = _browsing ? _browseBreak : _openBreak;
    CGFloat top = anchor + _tops[index].doubleValue - _focusTop;
    return openBreak >= 0 && index >= openBreak ? top + [self breakRoom] : top;
}

- (CGFloat)breakRoom {
    return ceil(_font.lineHeight) + _lineGap;
}

- (BOOL)isSung:(NSInteger)index {
    for (NSUInteger i = 0; i < _sungCount; i++) {
        if (_sung[i] == index) return YES;
    }
    return NO;
}

// Where the sung line rests: anchorTop when set, else kAnchor of the height.
- (CGFloat)restingAnchor {
    return _anchorTop > 0 ? _anchorTop : self.bounds.size.height * kAnchor;
}

- (CGFloat)lineAscent {
    return _font.ascender;
}

- (void)setAnchorTop:(CGFloat)anchorTop {
    if (_anchorTop == anchorTop) return;
    _anchorTop = anchorTop;
    [self setNeedsLayout];
}

// How many lines away from what is sung a line is, which is what dims, shrinks and blurs it: from the
// nearest line being sung, from an open break as if it were a line of its own, and before the first
// line from the line before it, as ever.
- (NSInteger)distanceOf:(NSInteger)index {
    if (_plain) return 0;   // nothing is sung, so every line reads as clearly as the rest
    if (_openBreak >= 0) return index >= _openBreak ? index - _openBreak + 1 : _openBreak - index;
    if (!_sungCount) return labs(index - _focus);
    NSInteger nearest = NSIntegerMax;
    for (NSUInteger i = 0; i < _sungCount; i++) nearest = MIN(nearest, labs(index - _sung[i]));
    return nearest;
}

// The width a line is set in: the page's, less its margins, or kVocalGroupShare of that in a song where a second voice
// keeps to the far side.
- (CGFloat)lineWidth {
    CGFloat width = _builtWidth - 2 * _margin;
    if (_voicesOf != _lines) {
        _voicesOf = _lines;
        _twoVoices = NO;
        for (SGKaraokeLine *line in _lines) {
            if (line.align != SGKaraokeAlignTrailing) continue;
            _twoVoices = YES;
            break;
        }
    }
    return _twoVoices ? floor(width * kVocalGroupShare) : width;
}

// The view of a line, made the first time it is asked for and placed where the stack has it.
- (SGRKaraokeLineView *)viewForLine:(NSInteger)index {
    __block SGRKaraokeLineView *view = _shown[@(index)];
    if (view || _detached || !_tops || index < 0 || index >= (NSInteger)_tops.count) return view;
    // Made where it belongs even inside an animation of the page's (a new height), not flown in from the corner.
    [UIView performWithoutAnimation:^{
        view = [[SGRKaraokeLineView alloc] initWithLine:self->_lines[index] width:[self lineWidth] style:self->_style under:nil
                                                blurred:self->_maxBlur > 0 && !self->_plain sweepsEstimates:self->_sweepsEstimates];
        __weak SGRKaraokeView *page = self;
        SGKaraokeLine *line = view.line;
        view.activate = ^BOOL {
            SGRKaraokeView *owner = page;
            if (!owner || owner->_plain || ![owner->_lines containsObject:line]) return NO;
            [owner seekToLine:line];
            return YES;
        };
        // A preview is a picture of the page: nothing on it is held for a menu or a share.
        if (!self->_sample) {
            view.copyText = ^BOOL {
                SGRKaraokeView *owner = page;
                NSString *text = heldLineText(line);
                if (!owner || !text.length) return NO;
                [owner copyLine:text];
                return YES;
            };
            view.shareText = ^BOOL {
                SGRKaraokeView *owner = page;
                NSString *text = heldLineText(line);
                if (!owner || !text.length) return NO;
                [owner shareLine:text from:owner->_shown[@(index)]];
                return YES;
            };
            view.shareCard = ^BOOL {
                SGRKaraokeView *owner = page;
                if (!owner || !heldLineText(line).length) return NO;
                [owner shareCardFrom:line];
                return YES;
            };
        }
        if (self->_plain) [view showPlain];
        else view.active = [self isSung:index];
        [view markMeaning:self->_meanings[@(index)]];
        [self->_scroll addSubview:view];
        self->_shown[@(index)] = view;
        [self placeLine:view at:index animated:NO];
    }];
    return view;
}

// Views for the lines just outside the visible part as well as in it, wherever that is: around the
// sung line while following the song, around wherever the page has been scrolled to while browsing.
// The ones further off are let go, so a long song costs a couple of dozen line views rather than
// one for every line, and the lines in sight are the only ones the compositor has to draw.
- (CFTimeInterval)lineCreationClock {
    return CACurrentMediaTime();
}

- (void)showLinesInSight {
    CFTimeInterval started = [self lineCreationClock];
    const CFTimeInterval creationBudgetSeconds = 0.001;
    if (_detached || !_tops.count) return;
    CGFloat offset = ((CALayer *)_scroll.layer.presentationLayer ?: _scroll.layer).bounds.origin.y;
    if (_restoringRows) offset = _scroll.contentOffset.y;
    if (offset == _sightOffset && _focusTop == _sightFocus && _arrangement == _sightArrangement) return;
    _sightOffset = offset;
    _sightFocus = _focusTop;
    _sightArrangement = _arrangement;
    CGFloat height = self.bounds.size.height;
    CGFloat from = offset - kSightBehind * height, to = offset + (1 + kSightAhead) * height, slack = kSightSlack * height;
    if (_restoringRows) { from = offset; to = offset + height; }
    NSMutableArray<NSNumber *> *gone = [NSMutableArray array];
    id focusedElement = UIAccessibilityIsVoiceOverRunning() ? UIAccessibilityFocusedElement(UIAccessibilityNotificationVoiceOverIdentifier) : nil;
    for (NSNumber *key in _shown) {
        NSInteger index = key.integerValue;
        CGFloat top = [self topOfLine:index], bottom = top + _shown[key].bounds.size.height;
        // Keep the element VoiceOver is reading even when playback moves it out of sight.
        BOOL focused = focusedElement == _shown[key];
        if (!focused && ![self isSung:index] && (bottom < from - slack || top > to + slack)) [gone addObject:key];
    }
    for (NSNumber *key in gone) {
        [self letGoOfLineView:_shown[key]];
        [_shown removeObjectForKey:key];
    }
    NSInteger count = (NSInteger)_tops.count;
    NSMutableArray<NSNumber *> *wanted = [NSMutableArray array];
    for (NSInteger index = 0; index < count; index++) {
        if (_shown[@(index)]) continue;
        CGFloat top = [self topOfLine:index];
        CGFloat bottom = index + 1 < count ? [self topOfLine:index + 1] - _lineGap : top + height;
        if (bottom < from || top > to) continue;
        [wanted addObject:@(index)];
    }
    // A few a frame, the nearest the middle of the visible part first, so a page scrolled by hand
    // fills in what is in view before what is not; the next frame picks up where this one left off.
    CGFloat middle = offset + height / 2;
    [wanted sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        CGFloat da = fabs([self topOfLine:a.integerValue] - middle), db = fabs([self topOfLine:b.integerValue] - middle);
        return da < db ? NSOrderedAscending : da > db ? NSOrderedDescending : NSOrderedSame;
    }];
    NSUInteger made = 0;
    for (NSNumber *index in wanted) {
        if (!_restoringRows && (made == kLinesPerFrame || (made && [self lineCreationClock] - started >= creationBudgetSeconds))) {
            _sightOffset = -CGFLOAT_MAX;
            break;
        }
        [self viewForLine:index.integerValue];
        made++;
    }
}

// One line's place in the stack: the anchor sits on the edge its text is aligned to, so it scales
// toward its own text, and it dims and blurs with its distance from what is sung.
- (void)placeLine:(SGRKaraokeLineView *)view at:(NSInteger)index animated:(BOOL)animated {
    CGFloat height = self.bounds.size.height;
    NSInteger distance = [self distanceOf:index], below = index - _focus;
    CGFloat left = view.right ? _builtWidth - _margin - view.bounds.size.width : _margin;
    CGRect frame = CGRectMake(left, [self topOfLine:index], view.bounds.size.width, view.bounds.size.height);
    CGPoint center = CGPointMake(view.right ? CGRectGetMaxX(frame) : _margin, CGRectGetMidY(frame));
    CGFloat scale = distance == 0 ? 1 : kDimScale;
    CGAffineTransform transform = CGAffineTransformMakeScale(scale, scale);
    CGFloat steps = distance == 0 ? 0 : distance + (below < 0 ? kBlurBehind : kBlurAhead);
    view.blur = _browsing ? 0 : MIN(_maxBlur, steps * _blurScale);
    BOOL near = CGRectIntersectsRect(CGRectInset(self.bounds, 0, -height / 2), frame)
             || CGRectIntersectsRect(CGRectInset(self.bounds, 0, -height / 2), view.frame);
    if (!animated || !near) {
        view.center = center;
        view.transform = transform;
        return;
    }
    NSTimeInterval delay = below > 0 ? MIN(0.3, below * 0.04) : 0;
    [UIView animateWithDuration:0.7 delay:delay usingSpringWithDamping:0.86 initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        view.center = center;
        view.transform = transform;
    } completion:nil];
}

// The sung line rests at the anchor and the rest stack around it; lines below it follow a beat
// later, the further down the later, as Apple Music's do. A line sung over it stays where it is
// below, lit; the stack moves on to it once the line at the anchor is sung out.
- (void)placeLinesAnimated:(BOOL)animated {
    [self stir];
    if (!_tops.count) return;
    if (_browsing) {
        [self placeCreditAnimated:NO];
        [self updateScrollExtent];
        return;
    }
    _focusTop = _tops[(NSUInteger)MAX(_focus, 0)].doubleValue;
    [self showLinesInSight];
    for (NSNumber *key in _shown) [self placeLine:_shown[key] at:key.integerValue animated:animated];
    [self placeBreak];
    [self placeCreditAnimated:animated];
    [self updateScrollExtent];
}

- (void)updateScrollExtent {
    if (!_tops.count) return;
    CGFloat height = self.bounds.size.height;
    CGFloat anchor = _browsing ? _browseAnchor : [self restingAnchor];
    NSInteger openBreak = _browsing ? _browseBreak : _openBreak;
    CGFloat bottom = anchor + _stackEnd - _focusTop + (openBreak >= 0 ? [self breakRoom] : 0);
    if (_credit.text.length) bottom = MAX(bottom, CGRectGetMaxY(_credit.frame));
    // The third mask stop is the last fully opaque point, before the fade and bottom controls.
    CGFloat visibleBottom = height * [_fade.locations[2] doubleValue];
    CGFloat lastTop = _tops.lastObject.doubleValue + (openBreak >= 0 ? [self breakRoom] : 0);
    _scroll.contentInset = UIEdgeInsetsMake(_focusTop, 0, MAX(MAX(0, lastTop - _focusTop), bottom - visibleBottom), 0);
}

// The credit, under the last line as Spotify's and Apple Music's are: it moves with the stack, so it is seen at the
// song's end or scrolled to, rather than over every line.
- (void)placeCreditAnimated:(BOOL)animated {
    if (!_tops.count || !_credit.text.length) return;
    CGFloat anchor = _browsing ? _browseAnchor : [self restingAnchor];
    NSInteger openBreak = _browsing ? _browseBreak : _openBreak;
    CGFloat width = MAX(self.bounds.size.width - 2 * _margin, 0);
    CGSize size = [_credit sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    CGFloat top = anchor + _stackEnd - _focusTop + (openBreak >= 0 ? [self breakRoom] : 0) + kCreditGap;
    CGRect frame = CGRectMake(_margin, top, MIN(ceil(size.width), width), ceil(size.height));
    if (CGRectEqualToRect(_credit.frame, frame)) return;
    if (!animated || _credit.hidden) {
        _credit.frame = frame;
        return;
    }
    [UIView animateWithDuration:0.7 delay:0.3 usingSpringWithDamping:0.86 initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{ self->_credit.frame = frame; } completion:nil];
}

// What a break is called: before the first line the intro; before a last line with no words, which some
// sources end a song with to mark where the singing stops, the outro; anywhere else an interlude.
static NSString *breakName(NSInteger line, NSArray<SGKaraokeLine *> *lines) {
    if (line <= 0) return SGL(@"settings.lyrics.break.intro", @"Intro");
    BOOL last = line == (NSInteger)lines.count - 1;
    if (last && !SGRLyricsHasWords(lines[(NSUInteger)line])) return SGL(@"settings.lyrics.break.outro", @"Outro");
    return SGL(@"settings.lyrics.break.interlude", @"Interlude");
}

// The dots, at the anchor for as long as a break is open, against the edge the line after it is on.
// They are only ever where they belong: they come and go by their own timeline, not by moving.
- (void)placeBreak {
    if (_openBreak < 0) {
        [_dots removeFromSuperview];
        return;
    }
    if (!_dots) {
        _dots = [[SGRKaraokeBreakView alloc] initWithFont:_font];
        _dotsLine = -1;
    }
    if (_dotsLine != _openBreak) {
        _dots.rightToLeft = readsRightToLeft(SGKaraokeLineText(_lines[(NSUInteger)_openBreak]));
        _dots.label = SGFlag(SGRKeyLyricsBreakLabels, NO) ? breakName(_openBreak, _lines) : nil;
        for (NSUInteger i = 0; i < _breakCount; i++) {
            if (_breaks[i].line == _openBreak) [_dots playFrom:_breaks[i].start to:_breaks[i].end];
        }
        _dotsLine = _openBreak;
    }
    if (_dots.superview != _scroll) [_scroll addSubview:_dots];
    _dots.right = alignsRight(_lines[(NSUInteger)_openBreak]);
    CGFloat top = [self topOfLine:_openBreak] - [self breakRoom];
    _dots.frame = CGRectMake(_margin, top, _builtWidth - 2 * _margin, _dots.bounds.size.height);
}

// A credit the source's terms require shows whatever Show source says (Shared/LyricsSources/SpicyLyrics.m).
- (void)creditTo:(NSString *)source {
    _creditSource = source;
    BOOL shown = source.length && (_crediting || SGLyricsCreditRequired(source));
    NSString *text = shown ? [NSString stringWithFormat:SGL(@"settings.lyrics.credit.from", @"Lyrics from %@"), source] : nil;
    _creditLinks = shown ? SGLyricsCreditLinks(source) : nil;
    _credit.accessibilityTraits = _creditLinks.count ? UIAccessibilityTraitLink : UIAccessibilityTraitStaticText;
    if (text == _credit.text || [text isEqualToString:_credit.text]) return;
    _credit.text = text;
    _credit.hidden = !_showing || !text.length;
    [self placeCreditAnimated:NO];
    [self updateScrollExtent];
}

- (NSArray *)accessibilityElements {
    NSMutableArray *elements = [NSMutableArray array];
    for (NSNumber *key in [[_shown allKeys] sortedArrayUsingSelector:@selector(compare:)]) [elements addObject:_shown[key]];
    if (_extrasBox && !_extrasBox.hidden) [elements addObject:_extrasBox];
    if (_status.showsNote && _statusBox.alpha > 0) [elements addObject:_status];
    if (!_credit.hidden) [elements addObject:_credit];
    if (_sing && !_sing.hidden) [elements addObject:_sing];
    return elements;
}

- (void)syncSiblings {
    if (_sample) return;
    for (UIView *sibling in self.superview.subviews) {
        if (sibling != self && _showing) sibling.alpha = 0;
    }
}

- (void)setShowing:(BOOL)showing {
    if (showing == _showing) return;
    _showing = showing;
    self.hidden = !showing;
    if (showing) [self queueAutomaticTranslation];
    if (showing && !_browsing) _scroll.contentOffset = CGPointZero;
    _credit.hidden = !showing || !_credit.text.length;
    if (!_sample) for (UIView *sibling in self.superview.subviews) {
        if (sibling != self) sibling.alpha = showing ? 0 : 1;
    }
}

// The player's position run on by the frame times the display will show and eased toward each new
// reading, so the sweep follows neither the callback's jitter nor the small jumps of the core's
// corrections. A seek or a new track is too far off to ease and is taken at once.
- (double)clockMs {
    NSInteger raw = [self positionMs];
    CFTimeInterval shown = [self frameTime];
    if (_seekAt) {
        // A paused player never moves, so the hold ends by the position or the time, not by motion.
        BOOL reported = raw >= 0 && labs(raw - _seekTo) <= kSeekNearMs;
        if (!reported && CACurrentMediaTime() - _seekAt < kSeekWait) {
            _clock = _seekTo;
            _reported = raw;
            _clockTime = shown;
            return _clock;
        }
        _seekAt = 0;
    }
    BOOL running = raw != _reported;   // a paused player reports the same position every frame
    if (running) {
        _stillSince = 0;
        if (_poll) [self stir];   // resumed without a player report
    }
    else if (!_stillSince) _stillSince = shown;
    double reported = raw + (running ? (shown - CACurrentMediaTime()) * 1000 : 0);
    double predicted = _clock + (running ? (shown - _clockTime) * 1000 : 0);
    double error = reported - predicted;
    _clock = raw < 0 || fabs(error) > kClockSnapMs ? reported : predicted + error * kClockPull;
    _reported = raw;
    _clockTime = shown;
    return _clock;
}

- (void)holdAwake:(BOOL)wanted {
    if (_holdingAwake == wanted) return;
    _holdingAwake = wanted;
    SGRLyricsHoldAwake(self, wanted);
}

- (void)plainAwake {
    if (_sample || !_link) return;
    SPTPlayerState *state = SGPlayerState();
    if (!state) {
        id player = SGKaraokePlayer();
        if ([player respondsToSelector:@selector(state)]) state = [(id<SPTPlayer>)player state];
    }
    CFTimeInterval now = CACurrentMediaTime();
    CFTimeInterval previousPause = _stillSince;
    NSInteger rest = plainRestPosition(state);
    if (rest != NSNotFound) {
        if (!_stillSince || rest != _reported) _stillSince = now;
        _reported = rest;
    } else _stillSince = 0;
    double left = _stillSince ? _stillSince + kAwakeAfterPause - now : kAwakeAfterPause;
    BOOL hold = SGRLyricsKeepAwakeOn() && _showing && left > 0;
    [self holdAwake:hold];
    if (hold && _stillSince == previousPause && _plainRelease.valid) return;
    // A seek, resume, or a change of visibility replaces the pending release, not the pause epoch.
    [_plainRelease invalidate];
    _plainRelease = nil;
    if (hold && _stillSince) {
        __weak typeof(self) weakSelf = self;
        _plainRelease = [NSTimer timerWithTimeInterval:left repeats:NO block:^(NSTimer *timer) {
            [weakSelf plainAwake];
        }];
        [NSRunLoop.mainRunLoop addTimer:_plainRelease forMode:NSRunLoopCommonModes];
    }
}

- (void)tick {
    // A paused clock and a page at rest draw nothing new: once what was last set moving has finished, a few
    // frames a second still watch the track, its lines and the clock, and whatever moves stirs it back.
    if (_seekAt || _scroll.isTracking || _scroll.isDecelerating) [self stir];
    else if (!_tops && !_plain && _link && !_link.paused && [self frameTime] - _stirredAt > kCalmAfter) [self calmDown];
    NSString *track = _sample ? @"sample" : SGKaraokePlayingTrack();
    if (!(track == _track || [track isEqualToString:_track])) {
        SGLog(@"karaoke: page shows track %@, lyrics %@", track, [self linesFor:track] ? @"captured" : @"not captured yet");
        _track = track;
        [self leaveTranslationPage];
        _seekAt = 0;
        _seekTo = 0;
        _stillSince = 0;   // the last song's pause says nothing of this one's
        [self stir];   // a new song is drawn at full rate, paused or not
        [self dropLines];
    }
    NSArray<SGKaraokeLine *> *kept = _lines && track ? [self linesFor:track] : nil;
    if (kept && kept != _lines && kept != _reconciled) {
        if (samePresentedLines(_lines, kept)) {
            // Pending analysis, prepared extras and row actions belong to this snapshot's object identities.
            _reconciled = kept;
            [self creditTo:SGLyricsCreditFor(track)];
        } else if (kept.count == _lines.count && SGKaraokeLinesTiming(kept) == SGKaraokeLinesTiming(_lines)
            && translationsDiffer(_lines, kept)) {
            // The keeper replaces provider translations on a target change. Adopt removals and
            // replacements through the same in-place restyle as the first community reply.
            SGLog(@"karaoke: translations of %@ changed", track);
            if (_tops) {
                _lines = kept;
                [self timeLines];
                [self restyle];
            } else {
                // Nothing placed yet, and a measure may be in flight in the old style: it is dropped, and
                // the translated lines are built below as new ones.
                _lines = nil;
                _builtWidth = 0;
                [self dropMeasuredLines];
            }
        } else {
            // Selection and deferred replacements belong to the keeper, not the view.
            SGLog(@"karaoke: authoritative lines of %@ replaced what was shown", track);
            _lines = nil;
            _builtWidth = 0;
            [self creditTo:nil];
            [self dropMeasuredLines];
        }
    }
    if (!_lines && track && (_lines = [self linesFor:track])) {
        SGLog(@"karaoke: showing %lu lines of %@", (unsigned long)_lines.count, track);
        [self timeLines];
        [self setNeedsLayout];
    }
    BOOL failed = !_sample && !_lines.count && SGLyricsLoadFailed(track);
    _loadFailure.hidden = !failed;
    _loadFailure.enabled = failed && !SGKaraokeLooking(track);
    [self setShowing:_tops != nil || failed];
    // Keep screen on: held while lines are shown and the song moves, let go a few seconds into a pause.
    if (_plain && _lines.count) [self plainAwake];
    else if (!_sample)
        [self holdAwake:SGRLyricsKeepAwakeOn() && !failed && _showing && !(_stillSince && [self frameTime] - _stillSince > kAwakeAfterPause)];
    // The source is settled a moment after the lines are, so it is asked for until it answers.
    if (!_sample && _lines && !_creditSource) [self creditTo:SGLyricsCreditFor(track)];
    if (_plain && _lines.count) {
        [self alignFade];
        [self showLinesInSight];
        if (!_tops || _sightOffset == _scroll.contentOffset.y) {
            [_poll invalidate];
            _poll = nil;
            _link.paused = YES;
        }
        return;
    }
    if (!_tops) return;
    [self alignFade];

    double now = [self clockMs];
    [self arrangeAt:now glide:_sample != nil];   // the preview coming round glides back to its first line
    for (NSUInteger i = 0; i < _sungCount; i++) [_shown[@(_sung[i])] showTime:now];
    CFTimeInterval frame = [self frameTime];
    if (_dots.superview) [_dots showTime:now running:!_stillSince || frame - _stillSince < kStillFor at:frame];
    if (!_link || _link.paused || frame - _stirredAt <= kCalmAfter || _sightOffset != _scroll.contentOffset.y) return;
    if (_stillSince) {
        if (frame - _stillSince > kCalmAfter) [self calmDown];
        return;
    }
    [self parkUntilMotionAt:now frame:frame];
}

// Called after drawing so the decision includes the presented pronunciation and backing, not just
// the source's timing category. A paused clock still takes the existing pause/awake polling path.
- (void)parkUntilMotionAt:(double)now frame:(CFTimeInterval)frame {
    double next = _sample ? _sampleLength : INFINITY;
    for (NSUInteger i = 0; i < _sungCount; i++) {
        SGRKaraokeLineView *row = _shown[@(_sung[i])];
        if (!row) return;
        next = MIN(next, [row nextMotionAt:now]);
        if (next <= now) return;
    }
    // clockMs predicts at 1x, as does the CA timeline for the dots. At another speed keep
    // their per-frame corrections rather than projecting that clock across a sleep.
    // Sing can acquire lead while on, and retain it after switch-off. An output flush can
    // then advance this same state without a report; no wall-clock deadline is safe.
    if (!_sample && (SGPlayerState().playbackSpeed != 1 || SGSingOn() || SGSingHeldLead() > 0)) return;
    if (fabs(now - (_reported + (frame - CACurrentMediaTime()) * 1000)) > 2) return;
    for (NSUInteger i = 0; i < _lines.count; i++) {
        if (_spans[i].start > now) { next = MIN(next, _spans[i].start); break; }
        if (_spans[i].end > now) next = MIN(next, _spans[i].end);
    }
    for (NSUInteger i = 0; i < _breakCount; i++) {
        SGRKaraokeBreak b = _breaks[i];
        if (b.start > now) next = MIN(next, b.start);
        double collapse = b.end - kBreakCollapse * 1000;
        if (collapse > now) next = MIN(next, collapse);
        // b.end is the following span's start.
    }
    // Resume in time to receive the display callback targeting the boundary, not one frame later.
    double lead = _link.targetTimestamp - _link.timestamp;
    double wait = frame - CACurrentMediaTime() + (next - now) / 1000.0 - lead;
    if (wait <= lead) return;
    _link.paused = YES;
    if (!isfinite(next)) return;   // last line: reports and UI events still wake the page
    __weak typeof(self) weakSelf = self;
    _boundaryWake = [NSTimer timerWithTimeInterval:wait repeats:NO block:^(NSTimer *timer) {
        [weakSelf resumeFrames];
    }];
    [NSRunLoop.mainRunLoop addTimer:_boundaryWake forMode:NSRunLoopCommonModes];
}

// The keeper retires stale requests; retry never creates a separate UI-only lookup.
- (void)retryLyrics {
    SGLyricsRetry(_track);
    [self tick];
}

// What is sung at `now` lit and the stack arranged around it; a jump of more than a couple of lines is
// placed at once, unless it is a tapped line gliding over.
- (void)arrangeAt:(double)now glide:(BOOL)glide {
    NSInteger sung[kMostSung], focus, openBreak;
    NSUInteger count = [self sungAt:now into:sung focus:&focus openBreak:&openBreak];
    if (focus != _focus || openBreak != _openBreak || count != _sungCount || memcmp(sung, _sung, count * sizeof(NSInteger))) {
        // Lines sung out go back to dim, lines coming in light up, the ones sung throughout carry on.
        for (NSUInteger i = 0; i < _sungCount; i++) {
            BOOL still = NO;
            for (NSUInteger j = 0; j < count; j++) still = still || sung[j] == _sung[i];
            if (!still) _shown[@(_sung[i])].active = NO;
        }
        for (NSUInteger j = 0; j < count; j++) {
            if (![self isSung:sung[j]]) [self viewForLine:sung[j]].active = YES;
        }
        BOOL jump = labs(focus - _focus) > 2;   // a seek, not the song moving on
        memcpy(_sung, sung, count * sizeof(NSInteger));
        _sungCount = count;
        _focus = focus;
        _openBreak = openBreak;
        _arrangement++;
        if (openBreak < 0) [_dots removeFromSuperview];
        [self placeLinesAnimated:glide || !jump];
    } else {
        [self showLinesInSight];   // the page may be scrolling by hand, or springing back
    }
}

// What is sung at `now`: each line from its start until it is sung out, so two voices over each
// other are both lit, and the last line begun on through the pause after it, as Apple Music keeps a
// line lit until the next one comes. A pause that is a break is the dots' instead, until the moment
// before its end when the line after it moves up to the anchor, sharp but not yet lit.
- (NSUInteger)sungAt:(double)now into:(NSInteger *)sung focus:(NSInteger *)focus openBreak:(NSInteger *)openBreak {
    NSInteger count = (NSInteger)_lines.count, last = -1;
    while (last + 1 < count && _spans[last + 1].start <= now) last++;
    *openBreak = -1;
    NSInteger breakLine = -1;
    for (NSUInteger i = 0; i < _breakCount; i++) {
        SGRKaraokeBreak pause = _breaks[i];
        if (now < pause.start || now >= pause.end) continue;
        breakLine = pause.line;
        if (now < pause.end - kBreakCollapse * 1000) *openBreak = pause.line;
    }
    NSUInteger found = 0;
    for (NSInteger i = 0; i <= last && found < kMostSung; i++) {
        if (_spans[i].end > now || (i == last && breakLine < 0)) sung[found++] = i;
    }
    *focus = breakLine >= 0 ? breakLine : found ? sung[0] : last;
    return found;
}

@end
