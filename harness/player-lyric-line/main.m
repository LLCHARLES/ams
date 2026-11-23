// Asserts the line under the cover's fit and clock offline (Redesigned/Player/PlayerLyricFit.m): a line that fits,
// one that shrinks, one that splits into portions of whole words (word timed and not, syllable spans and CJK spans
// written without spaces), and the wait to the next transition at different speeds and delays, with both clamps and
// overlapping lines, and the translation under the line (PlayerLyricLine.h): shown, absent, off, repeating the line,
// arriving late, and left out where the room does not hold it, and when the line takes Spotify's own preview's place
// (SGRPlayerLineTakesPreview). The contract's own numbers are asserted, not the
// constants that carry them. Exits 1 on any failure.
#import <UIKit/UIKit.h>
#import "Redesigned/Player/PlayerLyricFit.h"
#import "Redesigned/Player/PlayerLyricLine.h"
#import "Shared/Lyrics/Lyrics.h"
#import "../harness-fail.h"

static const CGFloat kWidth = 200;
// The contract: the smallest share of the font before splitting.
static const CGFloat kMinScale = 0.85;

static UIFont *font(void) { return [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]; }

static CGFloat widthOf(NSString *text, CGFloat scale) {
    return [text sizeWithAttributes:@{NSFontAttributeName : SGRLyricFontAtScale(font(), scale)}].width;
}

// A word as a source times it: its own text, from `start` to `end`, joined to the one before when the source wrote
// them as one run (a syllable of a word it split, or a character of an unspaced script).
static SGKaraokeWord *word(NSString *text, NSInteger start, NSInteger end, BOOL joined) {
    SGKaraokeWord *one = [SGKaraokeWord new];
    one.text = text;
    one.start = start;
    one.end = end;
    one.joined = joined;
    return one;
}

// A line of `words` from `start` to `end`.
static SGKaraokeLine *makeWords(NSArray<SGKaraokeWord *> *words, NSInteger start, NSInteger end, BOOL wordTimed) {
    SGKaraokeLine *line = [SGKaraokeLine new];
    line.words = words;
    line.start = start;
    line.end = end;
    line.timing = wordTimed ? SGKaraokeTimingWords : SGKaraokeTimingLine;
    return line;
}

// Words of `texts`, one after another from `start` to `end`, as a word-timed line when `wordTimed` and with its words
// joined (no spaces between them, as an unspaced script's) when `joined`.
static SGKaraokeLine *makeLine(NSArray<NSString *> *texts, NSInteger start, NSInteger end, BOOL wordTimed,
                               BOOL joined) {
    NSMutableArray<SGKaraokeWord *> *words = [NSMutableArray array];
    NSInteger step = (end - start) / (NSInteger)MAX(texts.count, 1);
    for (NSUInteger i = 0; i < texts.count; i++) {
        [words addObject:word(texts[i], start + (NSInteger)i * step, start + (NSInteger)(i + 1) * step, joined)];
    }
    return makeWords(words, start, end, wordTimed);
}

static NSString *textOf(SGKaraokeLine *line) { return SGKaraokeLineText(line); }

static SGRLyricWait waitFor(NSArray<SGKaraokeLine *> *lines, NSInteger position, NSInteger delay, double rate) {
    return SGRLyricLineWait(lines, position, delay, kWidth, font(), rate);
}

static SGRLyricWait waitAtWidth(NSArray<SGKaraokeLine *> *lines, NSInteger position, CGFloat width) {
    return SGRLyricLineWait(lines, position, 0, width, font(), 1);
}

int main(void) {
    for (NSArray<NSNumber *> *metrics in @[@[@23,@18], @[@21,@17]]) {
        CGFloat row = metrics[0].doubleValue, translation = metrics[1].doubleValue;
        for (NSInteger count = 0; count <= 2; count++) {
            CGFloat tr = translation;
            HARNESS_CHECK(SGRPlayerCompactRows((count + 1) * row - .25, row, &tr) == count);
            tr = translation;
            HARNESS_CHECK(SGRPlayerCompactRows(count * row, row, &tr) == count && tr == 0);
        }
        CGFloat tr = translation;
        HARNESS_CHECK(SGRPlayerCompactRows(2 * row + translation - .25, row, &tr) == 2 && tr == 0);
        tr = translation;
        HARNESS_CHECK(SGRPlayerCompactRows(2 * row + translation, row, &tr) == 2 && tr == translation);
    }
    @autoreleasepool {
        // The contract's own numbers, not the constants that carry them.
        HARNESS_CHECK(SGRLyricMinScale == 0.85);
        HARNESS_CHECK(SGRLyricMinWait == 0.02 && SGRLyricMaxWait == 0.5 && SGRLyricMaxTolerance == 0.1);

        // A line that fits is one portion at full size, and the same line, width and font is kept.
        SGKaraokeLine *shortLine = makeLine(@[ @"hold", @"me", @"close" ], 0, 3000, YES, NO);
        NSArray<SGRLyricPortion *> *fits = SGRLyricPortions(shortLine, kWidth, font());
        HARNESS_CHECK(fits.count == 1);
        HARNESS_CHECK(fits.firstObject.scale == 1);
        HARNESS_CHECK([fits.firstObject.text isEqualToString:textOf(shortLine)]);
        HARNESS_CHECK(SGRLyricPortions(shortLine, kWidth, font()) == fits);
        // A different width is measured for itself.
        HARNESS_CHECK(SGRLyricPortions(shortLine, 60, font()) != fits);
        // A different font is measured for itself: a new text size or Bold Text never reads the last font's portions.
        UIFont *larger = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
        HARNESS_CHECK(SGRLyricPortions(shortLine, kWidth, larger) != fits);
        UIFont *bold = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
        HARNESS_CHECK(SGRLyricPortions(shortLine, kWidth, bold) != fits);
        // A line an empty label has no width for yet is not measured.
        HARNESS_CHECK(SGRLyricPortions(shortLine, 0, font()).count == 1);
        HARNESS_CHECK(SGRLyricPortions(shortLine, 0, font()).firstObject.scale == 1);

        // A line just wider than one row uses its second row, at full size.
        NSString *tight = @"one two three four";
        SGKaraokeLine *tightLine = makeLine([tight componentsSeparatedByString:@" "], 0, 4000, NO, NO);
        CGFloat full = widthOf(textOf(tightLine), 1);
        CGFloat shrunkWidth = widthOf(textOf(tightLine), 0.88);
        NSArray<SGRLyricPortion *> *shrunk = SGRLyricPortions(tightLine, shrunkWidth, font());
        HARNESS_CHECK(shrunk.count == 1);
        HARNESS_CHECK(shrunk.firstObject.scale == 1);
        HARNESS_CHECK([shrunk.firstObject.text isEqualToString:textOf(tightLine)]);
        HARNESS_CHECK(full > shrunkWidth);
        SGKaraokeLine *wideWord = makeLine(@[@"extraordinary"], 0, 4000, NO, NO);
        SGRLyricPortion *alone = SGRLyricPortions(wideWord, widthOf(@"extraordinary", .9), font()).firstObject;
        HARNESS_CHECK(alone.scale >= kMinScale && alone.scale < 1 && [alone.text isEqual:@"extraordinary"]);

        // Far too narrow: successive portions of whole words, each one fitting at 85%, nothing dropped.
        NSString *longText = @"and every word I ever said comes back to me tonight";
        SGKaraokeLine *longLine = makeLine([longText componentsSeparatedByString:@" "], 1000, 5000, YES, NO);
        CGFloat narrow = 100;
        NSArray<SGRLyricPortion *> *split = SGRLyricPortions(longLine, narrow, font());
        HARNESS_CHECK(split.count > 1);
        NSMutableArray<NSString *> *kept = [NSMutableArray array];
        for (SGRLyricPortion *portion in split) {
            HARNESS_CHECK(portion.scale == 1);
            HARNESS_CHECK([portion.text boundingRectWithSize:CGSizeMake(narrow, CGFLOAT_MAX)
                  options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName:font()} context:nil].size.height <= 2 * ceil(font().lineHeight));
            [kept addObject:portion.text];
        }
        HARNESS_CHECK([[kept componentsJoinedByString:@" "] isEqualToString:textOf(longLine)]);

        // Word timed: the portion holding the word being sung, and the next one from its own first word.
        HARNESS_CHECK(SGRLyricPortionAt(split, 1000) == 0);
        HARNESS_CHECK(SGRLyricPortionAt(split, split[1].start - 1) == 0);
        HARNESS_CHECK(SGRLyricPortionAt(split, split[1].start) == 1);
        HARNESS_CHECK(SGRLyricPortionAt(split, 4999) == (NSInteger)split.count - 1);
        HARNESS_CHECK(split[1].start > split.firstObject.start);
        HARNESS_CHECK(split.lastObject.end == 5000);
        // Earlier than any of them: the first, not the last.
        HARNESS_CHECK(SGRLyricPortionAt(split, 0) == 0);

        // Not word timed: the line's own time shared out evenly, one share per portion.
        SGKaraokeLine *plain = makeLine([longText componentsSeparatedByString:@" "], 0, 4000, NO, NO);
        NSArray<SGRLyricPortion *> *plainPortions = SGRLyricPortions(plain, narrow, font());
        HARNESS_CHECK(plainPortions.count == split.count);
        for (NSUInteger i = 0; i < plainPortions.count; i++) {
            HARNESS_CHECK(plainPortions[i].start == (NSInteger)(i * 4000 / plainPortions.count));
            HARNESS_CHECK(plainPortions[i].end == (NSInteger)((i + 1) * 4000 / plainPortions.count));
        }
        HARNESS_CHECK(SGRLyricPortionAt(plainPortions, 0) == 0);
        HARNESS_CHECK(SGRLyricPortionAt(plainPortions, plainPortions[1].start - 1) == 0);
        HARNESS_CHECK(SGRLyricPortionAt(plainPortions, plainPortions[1].start) == 1);

        // A word a source times syllable by syllable: "beau", "ti", "ful" are one word, so no portion cuts it, and
        // the label shows it as "beautiful" with no space the source did not have.
        SGKaraokeLine *syllables = makeWords(@[
            word(@"beau", 0, 100, NO), word(@"ti", 100, 200, YES), word(@"ful", 200, 400, YES)
        ], 0, 400, YES);
        HARNESS_CHECK([textOf(syllables) isEqualToString:@"beautiful"]);
        NSArray<SGRLyricPortion *> *syllablePortions = SGRLyricPortions(syllables, 1000, font());
        HARNESS_CHECK(syllablePortions.count == 1);
        HARNESS_CHECK([syllablePortions.firstObject.text isEqualToString:@"beautiful"]);

        // The same syllables beside a word that does not fit: the word they spell stays in one portion whole.
        SGKaraokeLine *syllablesBeside = makeWords(@[
            word(@"and", 0, 200, NO), word(@"beau", 200, 300, NO), word(@"ti", 300, 400, YES),
            word(@"ful", 400, 600, YES), word(@"night", 600, 900, NO),
        ], 0, 900, YES);
        CGFloat beautiful = widthOf(@"beautiful", kMinScale);
        NSArray<SGRLyricPortion *> *besidePortions = SGRLyricPortions(syllablesBeside, beautiful + 1, font());
        HARNESS_CHECK(besidePortions.count > 1);
        for (SGRLyricPortion *portion in besidePortions) {
            HARNESS_CHECK([portion.text rangeOfString:@"beauti"].location == NSNotFound
                          || [portion.text rangeOfString:@"beautiful"].location != NSNotFound);
            HARNESS_CHECK([portion.text rangeOfString:@"ful"].location == NSNotFound
                          || [portion.text rangeOfString:@"beautiful"].location != NSNotFound);
        }
        NSMutableArray<NSString *> *besideJoined = [NSMutableArray array];
        for (SGRLyricPortion *portion in besidePortions) [besideJoined addObject:portion.text];
        HARNESS_CHECK([[besideJoined componentsJoinedByString:@" "] isEqualToString:textOf(syllablesBeside)]);

        // CJK written without spaces, where a source holds several characters in one span: split between the
        // characters, so no portion is wider than the label, and nothing inserted between them.
        NSMutableArray<SGKaraokeWord *> *spans = [NSMutableArray array];
        NSInteger at = 0;
        for (NSString *span in @[ @"君の名前を", @"呼んでいる夜", @"の向こうで光" ]) {
            [spans addObject:word(span, at, at + (NSInteger)span.length * 100, spans.count > 0)];
            at += (NSInteger)span.length * 100;
        }
        SGKaraokeLine *cjkLine = makeWords(spans, 0, at, YES);
        NSString *cjkText = @"君の名前を呼んでいる夜の向こうで光";
        HARNESS_CHECK([textOf(cjkLine) isEqualToString:cjkText]);
        NSArray<SGRLyricPortion *> *cjkPortions = SGRLyricPortions(cjkLine, 60, font());
        HARNESS_CHECK(cjkPortions.count > 1);
        NSMutableString *joined = [NSMutableString string];
        for (SGRLyricPortion *portion in cjkPortions) {
            HARNESS_CHECK([portion.text rangeOfString:@" "].location == NSNotFound);
            HARNESS_CHECK(portion.scale == 1);
            [joined appendString:portion.text];
        }
        HARNESS_CHECK([joined isEqualToString:cjkText]);
        // A span holding several characters is cut across its own time, not shown only from the span's start: some
        // portion begins inside one of the source spans.
        BOOL cutInsideSpan = NO;
        for (SGRLyricPortion *portion in cjkPortions) {
            for (SGKaraokeWord *span in spans) {
                if (portion.start > span.start && portion.start < span.end) cutInsideSpan = YES;
            }
        }
        HARNESS_CHECK(cutInsideSpan);

        // The wait: the next line 300 ms off is aimed at, with no tolerance.
        SGKaraokeLine *first = makeLine(@[ @"one" ], 0, 1000, NO, NO);
        SGKaraokeLine *second = makeLine(@[ @"two" ], 1300, 2000, NO, NO);
        NSArray<SGKaraokeLine *> *lines = @[ first, second ];
        SGRLyricWait wait = waitFor(lines, 1000, 0, 1);
        HARNESS_CHECK(fabs(wait.wait - 0.3) < 0.001 && wait.tolerance == 0);
        // At 2x the same boundary arrives in half the time.
        wait = waitFor(lines, 1000, 0, 2);
        HARNESS_CHECK(fabs(wait.wait - 0.15) < 0.001 && wait.tolerance == 0);
        // At 0.5x a 200 ms boundary is 400 ms off, still a boundary with no tolerance.
        wait = waitFor(lines, 1100, 0, 0.5);
        HARNESS_CHECK(fabs(wait.wait - 0.4) < 0.001 && wait.tolerance == 0);
        // At 0.5x a 300 ms one would be 600 ms off: clamped to 500 ms, with 100 ms of tolerance.
        wait = waitFor(lines, 1000, 0, 0.5);
        HARNESS_CHECK(wait.wait == 0.5 && wait.tolerance == 0.1);
        // The Lyrics delay moves the position the line is read at: 250 ms of it puts 1000 ms 50 ms ahead, and the
        // line's own end turns over before the next line's start.
        HARNESS_CHECK(fabs(waitFor(lines, 1200, 0, 1).wait - 0.1) < 0.001);
        wait = waitFor(lines, 1200, 250, 1);
        HARNESS_CHECK(fabs(wait.wait - 0.05) < 0.001 && wait.tolerance == 0);
        // 100 ms of delay: the line's end is 400 ms off the position the line is read at.
        wait = waitFor(lines, 700, 100, 1);
        HARNESS_CHECK(fabs(wait.wait - 0.4) < 0.001 && wait.tolerance == 0);
        // No boundary before 500 ms: 500 ms with 100 ms of tolerance.
        wait = waitFor(@[ second ], 0, 0, 1);
        HARNESS_CHECK(wait.wait == 0.5 && wait.tolerance == 0.1);
        HARNESS_CHECK(waitFor(lines, 0, 0, 1).wait == 0.5);
        // A paused song is the fallback too, with its tolerance.
        HARNESS_CHECK(waitFor(lines, 1000, 0, 0).wait == 0.5 && waitFor(lines, 1000, 0, 0).tolerance == 0.1);
        // A boundary less than 20 ms away is aimed at 20 ms.
        wait = waitFor(@[ first, makeLine(@[ @"soon" ], 2005, 4000, NO, NO) ], 2000, 0, 1);
        HARNESS_CHECK(wait.wait == 0.02 && wait.tolerance == 0);
        // One word per row, two per portion, a new portion every 300 ms.
        NSMutableArray<NSString *> *las = [NSMutableArray array];
        for (NSUInteger i = 0; i < 6; i++) [las addObject:@"la"];
        SGKaraokeLine *worded = makeLine(las, 0, 900, YES, NO);
        CGFloat three = widthOf(@"la", 1) + 1;
        NSArray<SGRLyricPortion *> *wordedPortions = SGRLyricPortions(worded, three, font());
        HARNESS_CHECK(wordedPortions.count == 3);
        HARNESS_CHECK([wordedPortions[1].text isEqual:@"la la"] && wordedPortions[1].scale == 1);
        HARNESS_CHECK(wordedPortions[1].start == 300 && wordedPortions[2].start == 600);
        wait = waitAtWidth(@[ worded ], 0, three);
        HARNESS_CHECK(fabs(wait.wait - 0.3) < 0.001 && wait.tolerance == 0);
        // In the second portion already: the third one, not the second.
        wait = waitAtWidth(@[ worded ], 300, three);
        HARNESS_CHECK(fabs(wait.wait - 0.3) < 0.001 && wait.tolerance == 0);
        // At 2x that portion arrives in 150 ms.
        wait = SGRLyricLineWait(@[ worded ], 300, 0, three, font(), 2);
        HARNESS_CHECK(fabs(wait.wait - 0.15) < 0.001 && wait.tolerance == 0);
        // Nothing to aim at: no lines, no position.
        HARNESS_CHECK(waitFor(@[], 0, 0, 1).wait == 0.5);
        HARNESS_CHECK(waitFor(lines, -1, 0, 1).wait == 0.5);

        // A resume reported at the very place the song stopped re-arms at once: the paused timer is the wrong one.
        const NSInteger armed = 1000;
        HARNESS_CHECK(SGRLyricRearmNeeded(armed, 0, armed, 1, 0.05));
        HARNESS_CHECK(SGRLyricRearmNeeded(armed, 0, armed, 0.5, 0.05));
        // A pause is the same, and so is a new speed at the same place.
        HARNESS_CHECK(SGRLyricRearmNeeded(armed, 1, armed, 0, 0.05));
        HARNESS_CHECK(SGRLyricRearmNeeded(armed, 1, armed, 2, 0.05));
        // Armed while playing, a report where the armed timer was heading asks for nothing.
        HARNESS_CHECK(!SGRLyricRearmNeeded(armed, 1, armed + 200, 1, 0.2));
        // Paused, any move of the place is a seek, however small; the same place is not.
        HARNESS_CHECK(!SGRLyricRearmNeeded(armed, 0, armed, 0, 5));
        HARNESS_CHECK(SGRLyricRearmNeeded(armed, 0, armed + 1, 0, 5));
        // Playing, only a report away from where the armed timer was heading beyond 500 ms is a seek.
        HARNESS_CHECK(!SGRLyricRearmNeeded(armed, 1, armed + 700, 1, 0.2));
        HARNESS_CHECK(SGRLyricRearmNeeded(armed, 1, armed + 701, 1, 0.2));

        // Overlapping lines: the first is still sung after the second has begun, so SGKaraokeLeadLine keeps it. Its
        // own sung end is the next thing to come, and the start already passed is never aimed at again.
        SGKaraokeLine *held = makeLine(@[ @"held" ], 0, 3000, NO, NO);
        SGKaraokeLine *over = makeLine(@[ @"over" ], 800, 1400, NO, NO);
        NSArray<SGKaraokeLine *> *overlapping = @[ held, over ];
        HARNESS_CHECK(SGKaraokeLeadLine(overlapping, 1000) == 0);
        wait = waitFor(overlapping, 1000, 0, 1);
        HARNESS_CHECK(fabs(wait.wait - 0.4) < 0.001 && wait.tolerance == 0);
        wait = waitFor(overlapping, 1400, 0, 1);
        HARNESS_CHECK(wait.wait == 0.5 && wait.tolerance == 0.1);
        // Every position inside the overlap is aimed at something in the future, never at 20 ms over and over.
        for (NSInteger ms = 800; ms < 1400; ms += 50) {
            SGRLyricWait at = waitFor(overlapping, ms, 0, 1);
            HARNESS_CHECK(at.wait > 0.02 && at.wait <= 0.5);
        }

        // A line ending in an emoji (two UTF-16 units) keeps it whole, as the last character of a word and as a
        // word of its own, in one portion and split across several.
        SGKaraokeLine *emojiLine = makeLine(@[ @"hold", @"me", @"close", @"😀" ], 0, 4000, YES, NO);
        NSArray<SGRLyricPortion *> *emojiFit = SGRLyricPortions(emojiLine, kWidth * 4, font());
        HARNESS_CHECK(emojiFit.count == 1 && [emojiFit.firstObject.text isEqualToString:@"hold me close 😀"]);
        NSArray<SGRLyricPortion *> *emojiSplit = SGRLyricPortions(emojiLine, widthOf(@"hold me", kMinScale) + 1, font());
        HARNESS_CHECK(emojiSplit.count > 1 && [emojiSplit.lastObject.text hasSuffix:@"😀"]);
        NSMutableArray<NSString *> *emojiTexts = [NSMutableArray array];
        for (SGRLyricPortion *portion in emojiSplit) [emojiTexts addObject:portion.text];
        HARNESS_CHECK([[emojiTexts componentsJoinedByString:@" "] isEqualToString:@"hold me close 😀"]);
        SGKaraokeLine *emojiWord = makeLine(@[ @"love😀" ], 0, 1000, NO, NO);
        HARNESS_CHECK([SGRLyricPortions(emojiWord, kWidth, font()).firstObject.text isEqualToString:@"love😀"]);

        // The translation under the line (PlayerLyricLine.h): none while the line has none, then the one that arrives
        // later on the same line, trimmed; none with translations off, and none for one that only repeats the line.
        SGKaraokeLine *sung = makeLine(@[ @"Woke", @"up", @"feeling", @"damned" ], 0, 2000, YES, NO);
        HARNESS_CHECK(SGRPlayerLineTranslation(sung, YES) == nil);
        sung.translation = @" 저주받은 기분으로 깼어\n";
        HARNESS_CHECK([SGRPlayerLineTranslation(sung, YES) isEqualToString:@"저주받은 기분으로 깼어"]);
        HARNESS_CHECK(SGRPlayerLineTranslation(sung, NO) == nil);
        sung.translation = @"Woke up, feeling DAMNED!";
        HARNESS_CHECK(SGRPlayerLineTranslation(sung, YES) == nil);
        sung.translation = @" \n";
        HARNESS_CHECK(SGRPlayerLineTranslation(sung, YES) == nil);

        // Spotify's own preview under the cover: the line takes its place only while it is on, translations are shown
        // and the player is taller than wide; every other case leaves the preview as Spotify shows it.
        HARNESS_CHECK(SGRPlayerLineTakesPreview(YES, YES, YES));
        HARNESS_CHECK(!SGRPlayerLineTakesPreview(NO, YES, YES));
        HARNESS_CHECK(!SGRPlayerLineTakesPreview(YES, NO, YES));
        // A track the line has no synced lines for keeps Spotify's preview, its only lyrics.
        HARNESS_CHECK(!SGRPlayerLineTakesPreview(YES, YES, NO));
        HARNESS_CHECK(!SGRPlayerLineTakesPreview(NO, NO, NO));

        // Giving the previews back: none while the line takes their place; then every one hidden, the one a list
        // keeps for reuse (out of any view) included, and none twice.
        NSHashTable<UIView *> *hidden = [NSHashTable weakObjectsHashTable];
        UIView *cell = [UIView new], *onScreen = [UIView new], *pooled = [UIView new];
        [cell addSubview:onScreen];
        [hidden addObject:onScreen];
        [hidden addObject:pooled];
        HARNESS_CHECK(SGRPlayerPreviewsToGiveBack(hidden, YES).count == 0);
        NSArray<UIView *> *given = SGRPlayerPreviewsToGiveBack(hidden, NO);
        HARNESS_CHECK(given.count == 2 && [given containsObject:onScreen] && [given containsObject:pooled]);
        HARNESS_CHECK(SGRPlayerPreviewsToGiveBack(hidden, NO).count == 0);

        printf("player lyric line: all checks passed\n");
        return 0;
    }
}
