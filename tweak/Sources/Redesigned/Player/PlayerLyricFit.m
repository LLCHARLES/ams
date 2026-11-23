// Player redesign: the line under the cover's fit and clock (PlayerLyricFit.h). A line is measured once for the width
// it has, its portions kept, so a tick that finds the same line and width measures nothing.
#import "PlayerLyricFit.h"
#import "Shared/Lyrics/Lyrics.h"
#import <math.h>

const CGFloat SGRLyricMinScale = 0.85;
const NSTimeInterval SGRLyricMinWait = 0.02;
const NSTimeInterval SGRLyricMaxWait = 0.5;
const NSTimeInterval SGRLyricMaxTolerance = 0.1;

UIFont *SGRLyricFontAtScale(UIFont *font, CGFloat scale) {
    return scale >= 0.999 ? font : [font fontWithSize:font.pointSize * scale];
}

@interface SGRLyricPortion ()
@property (nonatomic, copy, readwrite) NSString *text;
@property (nonatomic, readwrite) CGFloat scale;
@property (nonatomic, readwrite) NSInteger start, end;
@end

@implementation SGRLyricPortion
@end

// One place a portion may begin at, as the label shows the line: a whole word where the text spaces its words (so the
// syllables a source splits "beautiful" into are not cut apart), and one character where it does not (so a Chinese or
// Japanese span the source holds whole is not left wider than the label). `start` is when its first character is sung,
// its share of the source word the character belongs to; `end` is when that word stops.
@interface SGRLyricUnit : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic) BOOL spaceBefore;
@property (nonatomic) NSInteger start, end;
@end

@implementation SGRLyricUnit
@end

// The words as the label shows them: a space between the ones the source did not join.
static NSString *wordsText(NSArray<SGKaraokeWord *> *words) {
    NSMutableString *text = [NSMutableString string];
    for (SGKaraokeWord *word in words) {
        if (text.length && !word.joined) [text appendString:@" "];
        [text appendString:word.text ?: @""];
    }
    return text;
}

static CGFloat widthOf(NSString *text, UIFont *font) {
    return text.length ? [text sizeWithAttributes:@{NSFontAttributeName : font}].width : 0;
}

// The largest share of the font, between SGRLyricMinScale and 1, the whole line fits `width` at: a share's width
// does not shrink in exact step with it, so the one that fits is measured, not worked out from the full size.
static CGFloat fittingScale(NSString *text, CGFloat width, UIFont *font) {
    CGFloat low = SGRLyricMinScale, high = 1;
    for (int i = 0; i < 8; i++) {
        CGFloat middle = (low + high) / 2;
        if (widthOf(text, SGRLyricFontAtScale(font, middle)) <= width) low = middle;
        else high = middle;
    }
    return low;
}

static SGRLyricPortion *portion(NSArray<SGRLyricUnit *> *units, CGFloat scale, NSInteger start, NSInteger end) {
    NSMutableString *text = [NSMutableString string];
    BOOL started = NO;
    for (SGRLyricUnit *unit in units) {
        if (started && unit.spaceBefore) [text appendString:@" "];
        [text appendString:unit.text];
        started = YES;
    }
    SGRLyricPortion *one = [SGRLyricPortion new];
    one.text = text;
    one.scale = scale;
    one.start = start;
    one.end = end;
    return one;
}

static NSCharacterSet *spaceSet(void) {
    static NSCharacterSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ set = NSCharacterSet.whitespaceAndNewlineCharacterSet; });
    return set;
}

// The whole line as one portion, every word its own unit: what a line shown at `scale` is while it fits.
static SGRLyricPortion *wholePortion(SGKaraokeLine *line, CGFloat scale) {
    NSMutableArray<SGRLyricUnit *> *units = [NSMutableArray array];
    for (SGKaraokeWord *word in line.words) {
        SGRLyricUnit *unit = [SGRLyricUnit new];
        unit.text = word.text ?: @"";
        unit.spaceBefore = units.count > 0 && !word.joined;
        unit.start = word.start;
        unit.end = word.end;
        [units addObject:unit];
    }
    return portion(units, scale, line.start, line.end);
}

// The display text of the source words, and each source word's range in it: a space between the ones not joined.
static NSString *displayOf(NSArray<SGKaraokeWord *> *words, NSMutableArray<NSValue *> *ranges) {
    NSMutableString *text = [NSMutableString string];
    for (SGKaraokeWord *word in words) {
        if (text.length && !word.joined) [text appendString:@" "];
        NSUInteger at = text.length;
        [text appendString:word.text ?: @""];
        [ranges addObject:[NSValue valueWithRange:NSMakeRange(at, word.text.length)]];
    }
    return text;
}

// The source word a display offset belongs to: the one holding it, or the last one to begin before it.
static NSUInteger wordAtOffset(NSArray<NSValue *> *ranges, NSUInteger offset) {
    NSUInteger found = 0;
    for (NSUInteger i = 0; i < ranges.count; i++) {
        NSRange range = ranges[i].rangeValue;
        if (range.location <= offset) found = i;
        if (range.location <= offset && offset < NSMaxRange(range)) return i;
    }
    return found;
}

// When the character at `offset` of `text` is sung, shared out within the word it belongs to: a character of a word
// the source timed only as a whole is taken at its share of that word's time.
static NSInteger sungStartOfCharacter(SGKaraokeWord *word, NSString *text, NSUInteger offset) {
    __block NSUInteger characters = 0, index = 0;
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationByComposedCharacterSequences
                          usingBlock:^(NSString *piece, NSRange range, NSRange enclosing, BOOL *stop) {
        if (range.location <= offset) index = characters;
        characters++;
    }];
    if (characters < 2) return word.start;
    return word.start + (NSInteger)((double)(word.end - word.start) * (double)index / (double)characters);
}

// Where a portion may begin in `line` as the label shows it, in order, each with when it is sung: whole words where
// the text spaces them, so the syllables a source splits one word into stay together, and one character at a time
// where it does not, so a long Chinese or Japanese span is not left wider than the label. Punctuation and the spaces
// around them stay with the word before them.
static NSArray<SGRLyricUnit *> *unitsOf(SGKaraokeLine *line) {
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    NSString *display = displayOf(line.words, ranges);
    NSMutableIndexSet *cuts = [NSMutableIndexSet indexSetWithIndex:0];
    [display enumerateSubstringsInRange:NSMakeRange(0, display.length) options:NSStringEnumerationByWords
                             usingBlock:^(NSString *word, NSRange range, NSRange enclosing, BOOL *stop) {
        if (!range.length) return;
        // A comma or a bracket before a word is not a place of its own to begin at.
        if (![spaceSet() characterIsMember:[display characterAtIndex:range.location]]) [cuts addIndex:range.location];
        if (!SGKaraokeUnspacedScript(word)) return;
        // Each character of an unspaced run is a place to begin at, as the source wrote no space to break at.
        [word enumerateSubstringsInRange:NSMakeRange(0, word.length)
                                 options:NSStringEnumerationByComposedCharacterSequences
                              usingBlock:^(NSString *piece, NSRange pieceRange, NSRange e, BOOL *stop) {
            if (pieceRange.location) [cuts addIndex:range.location + pieceRange.location];
        }];
    }];
    [cuts addIndex:display.length];

    NSMutableArray<SGRLyricUnit *> *units = [NSMutableArray array];
    __block NSUInteger previous = NSNotFound;
    [cuts enumerateIndexesUsingBlock:^(NSUInteger location, BOOL *stop) {
        if (previous == NSNotFound) {
            previous = location;
            return;
        }
        NSRange segment = NSMakeRange(previous, location - previous);
        previous = location;
        NSString *raw = [display substringWithRange:segment];
        NSRange trimmed = [raw rangeOfCharacterFromSet:spaceSet().invertedSet];
        if (trimmed.location == NSNotFound) return;   // a gap between words: shown by the space before the next one
        NSUInteger length = NSMaxRange([raw rangeOfCharacterFromSet:spaceSet().invertedSet options:NSBackwardsSearch])
            - trimmed.location;
        NSUInteger at = segment.location + trimmed.location;
        SGRLyricUnit *unit = [SGRLyricUnit new];
        unit.text = [display substringWithRange:NSMakeRange(at, length)];
        unit.spaceBefore = units.count > 0 && [spaceSet() characterIsMember:[display characterAtIndex:at - 1]];
        NSUInteger owner = wordAtOffset(ranges, at);
        SGKaraokeWord *word = line.words[owner];
        NSRange wordRange = ranges[owner].rangeValue;
        unit.start = at == wordRange.location
            ? word.start
            : sungStartOfCharacter(word, [display substringWithRange:wordRange], at - wordRange.location);
        unit.end = MAX(word.end, word.start);
        [units addObject:unit];
    }];
    return units;
}

// The line's words in two-row portions at the selected font. Every portion is whole words, so no
// portion is cut in the middle of one; a single word wider than the label keeps a portion to itself.
static NSArray<SGRLyricPortion *> *splitPortions(SGKaraokeLine *line, CGFloat width, UIFont *font, NSInteger rows) {
    NSArray<SGRLyricUnit *> *units = unitsOf(line);
    NSMutableArray<NSArray<SGRLyricUnit *> *> *groups = [NSMutableArray array];
    NSMutableArray<SGRLyricUnit *> *group = [NSMutableArray array];
    NSMutableString *candidate = [NSMutableString string];
    for (SGRLyricUnit *unit in units) {
        BOOL oversized = widthOf(unit.text, font) > width;
        if (group.count && unit.spaceBefore) [candidate appendString:@" "];
        [candidate appendString:unit.text];
        CGFloat height = [candidate boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX)
            options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
            attributes:@{NSFontAttributeName:font} context:nil].size.height;
        if (group.count && (oversized || height > rows * ceil(font.lineHeight))) {
            [groups addObject:group];
            group = [NSMutableArray array];
            [candidate setString:unit.text];
        }
        [group addObject:unit];
        if (oversized) {
            [groups addObject:group];
            group = [NSMutableArray array];
            [candidate setString:@""];
        }
    }
    if (group.count) [groups addObject:group];
    if (!groups.count) return @[];

    NSMutableArray<SGRLyricPortion *> *portions = [NSMutableArray arrayWithCapacity:groups.count];
    NSInteger count = (NSInteger)groups.count;
    NSInteger span = MAX(line.end - line.start, count);
    for (NSUInteger i = 0; i < groups.count; i++) {
        NSInteger start = line.start + (NSInteger)i * span / count;
        NSInteger end = i + 1 < groups.count ? line.start + (NSInteger)(i + 1) * span / count : line.start + span;
        if (line.timing == SGKaraokeTimingWords) {
            start = groups[i].firstObject.start;
            end = i + 1 < groups.count ? groups[i + 1].firstObject.start : MAX(line.end, groups[i].lastObject.end);
        }
        NSString *word = groups[i].firstObject.text;
        CGFloat scale = groups[i].count == 1 && widthOf(word, font) > width ? fittingScale(word, width, font) : 1;
        [portions addObject:portion(groups[i], scale, start, end)];
    }
    return portions;
}

// The portions measured for one line, width and font. The line is held, so another line can never take its address
// and read its portions. The font is kept whole, not by name: Bold Text changes what a name and a size measure at.
@interface SGRLyricPortionEntry : NSObject
@property (nonatomic, strong) SGKaraokeLine *line;
@property (nonatomic) CGFloat width;
@property (nonatomic) NSInteger rows;
@property (nonatomic, strong) UIFont *font;
@property (nonatomic, copy) NSArray<SGRLyricPortion *> *portions;
@end

@implementation SGRLyricPortionEntry
- (BOOL)isFor:(SGKaraokeLine *)line width:(CGFloat)width font:(UIFont *)font {
    return self.line == line && self.width == width && [self.font isEqual:font];
}
@end

static NSMutableArray<SGRLyricPortionEntry *> *sg_kept;
// Portions kept before the oldest is dropped, a screen showing one line at a time.
static const NSUInteger kPortionCacheLimit = 32;

NSArray<SGRLyricPortion *> *SGRLyricPortions(SGKaraokeLine *line, CGFloat width, UIFont *font) {
    return SGRLyricPortionsInRows(line, width, font, 2);
}
NSArray<SGRLyricPortion *> *SGRLyricPortionsInRows(SGKaraokeLine *line, CGFloat width, UIFont *font, NSInteger rows) {
    if (!line.words.count) return @[];
    if (width <= 0) return @[wholePortion(line, 1)];
    if (!sg_kept) sg_kept = [NSMutableArray array];
    for (SGRLyricPortionEntry *entry in sg_kept) {
        if (entry.rows == rows && [entry isFor:line width:width font:font]) return entry.portions;
    }

    NSArray<SGRLyricPortion *> *measured = nil;
    NSString *whole = wordsText(line.words);
    if (widthOf(whole, font) <= width) {
        measured = @[wholePortion(line, 1)];
    } else {
        measured = splitPortions(line, width, font, rows);
    }
    if (sg_kept.count >= kPortionCacheLimit) [sg_kept removeObjectAtIndex:0];
    SGRLyricPortionEntry *entry = [SGRLyricPortionEntry new];
    entry.line = line;
    entry.width = width;
    entry.rows = rows;
    entry.font = font;
    entry.portions = measured;
    [sg_kept addObject:entry];
    return measured;
}

NSInteger SGRLyricPortionAt(NSArray<SGRLyricPortion *> *portions, NSInteger ms) {
    NSInteger index = 0;
    for (NSUInteger i = 0; i < portions.count; i++) {
        if (portions[i].start <= ms) index = (NSInteger)i;
    }
    return index;
}

static SGRLyricWait fallbackWait(void) {
    return (SGRLyricWait){.wait = SGRLyricMaxWait, .tolerance = SGRLyricMaxTolerance};
}

const NSInteger SGRLyricReportSlack = 500;

BOOL SGRLyricRearmNeeded(NSInteger armedMs, double armedRate, NSInteger reportedMs, double reportedRate,
                         NSTimeInterval elapsed) {
    // A change of the rate is a pause, a resume or a new speed, and the armed wait was aimed at the old rate's
    // boundaries, so it is aimed again first, before the position is looked at: a resume is often reported at the very
    // place the song stopped, which would otherwise read as the ordinary report it is not.
    if (reportedRate != armedRate) return YES;
    // Paused, the song's time does not run on, so the armed place is the whole of the comparison.
    if (reportedRate <= 0) return reportedMs != armedMs;
    // Playing, a report that lands where the armed timer was heading is the ordinary one and asks for nothing.
    double expected = (double)armedMs + elapsed * 1000 * armedRate;
    return fabs((double)reportedMs - expected) > (double)SGRLyricReportSlack;
}

SGRLyricWait SGRLyricLineWait(NSArray<SGKaraokeLine *> *ordered, NSInteger positionMs, NSInteger delayMs,
                              CGFloat width, UIFont *font, double rate) {
    return SGRLyricLineWaitInRows(ordered, positionMs, delayMs, width, font, rate, 2);
}
SGRLyricWait SGRLyricLineWaitInRows(NSArray<SGKaraokeLine *> *ordered, NSInteger positionMs, NSInteger delayMs,
                                    CGFloat width, UIFont *font, double rate, NSInteger rows) {
    // A position not known yet, or a paused song (rate 0), has nothing to aim at: no boundary is nearer than that.
    if (!ordered.count || positionMs < 0 || !(rate > 0)) return fallbackWait();
    NSInteger position = positionMs - delayMs;
    NSInteger index = SGKaraokeLeadLine(ordered, position);
    // The earliest transition still to come, from whichever line turns over: every line's start, end and sung end,
    // and the portions of the line being sung. The retained line's own end counts here, as with overlapping lines it
    // can be later than the next line's start, which the lead line has already passed.
    NSInteger boundary = NSIntegerMax;
    for (NSUInteger i = 0; i < ordered.count; i++) {
        SGKaraokeLine *line = ordered[i];
        NSInteger ends[] = {line.start, line.end, SGKaraokeSungEnd(line)};
        for (size_t e = 0; e < sizeof ends / sizeof *ends; e++) {
            if (ends[e] > position && ends[e] < boundary) boundary = ends[e];
        }
        if (index >= 0 && (NSInteger)i == index) {
            NSArray<SGRLyricPortion *> *portions = SGRLyricPortionsInRows(line, width, font, rows);
            for (SGRLyricPortion *portion in portions) {
                if (portion.start > position && portion.start < boundary) boundary = portion.start;
            }
        }
    }
    // Only a transition still to come is aimed at; one already reached would wake at the floor over and over.
    if (boundary == NSIntegerMax || boundary <= position) return fallbackWait();
    // Song time to wall time: at 2x a boundary 400 ms off arrives in 200 ms.
    NSTimeInterval wait = (boundary - position) / 1000.0 / rate;
    if (wait >= SGRLyricMaxWait) return fallbackWait();
    return (SGRLyricWait){.wait = MAX(wait, SGRLyricMinWait), .tolerance = 0};
}
