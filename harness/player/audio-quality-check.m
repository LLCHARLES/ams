// The audio quality badge's rules (tweak/Sources/Shared/Player/AudioQualityRules.m), compiled as they ship: which of
// Spotify's playback quality reports show a badge, and in which words.
#import <Foundation/Foundation.h>
#import "Shared/Player/AudioQualityRules.h"

// The bundle's English, which SGL hands back for a language without a table.
NSString *SGL(NSString *key, NSString *english) {
    return english;
}

static int failures;
static void check(BOOL passed, NSString *name) {
    if (!passed) failures++;
    NSLog(@"%@: %@", passed ? @"PASS" : @"FAIL", name);
}

// A view chain without UIKit: hidden and alpha per level, the superview above.
@interface FakeView : NSObject <SGAudioQualityViewChain>
@property (nonatomic, strong) FakeView *parent;
@property (nonatomic) BOOL hiddenFlag;
@property (nonatomic) CGFloat alphaValue;
@end
@implementation FakeView
- (id)superview { return self.parent; }
- (BOOL)isHidden { return self.hiddenFlag; }
- (CGFloat)alpha { return self.alphaValue; }
@end

static FakeView *view(FakeView *parent, BOOL hidden, CGFloat alpha) {
    FakeView *v = [FakeView new];
    v.parent = parent;
    v.hiddenFlag = hidden;
    v.alphaValue = alpha;
    return v;
}

static NSString *shown(BOOL on, BOOL local, NSString *uri, long long level) {
    return SGAudioTierName(SGAudioTierShown(on, local, uri, level)) ?: @"nothing";
}

int main(void) {
    @autoreleasepool {
        NSString *song = @"spotify:track:4uLU6hMCjMI75M1A2tKUQC";
        NSDictionary<NSNumber *, NSString *> *levels = @{
            @0: @"nothing", @1: @"Low", @2: @"Normal", @3: @"High", @4: @"Very high",
            @5: @"Lossless", @6: @"Lossless 24-bit", @7: @"nothing", @8: @"nothing", @-1: @"nothing",
        };
        for (NSNumber *level in levels) {
            check([shown(YES, YES, song, level.longLongValue) isEqualToString:levels[level]],
                  [NSString stringWithFormat:@"bitrateLevel %@ shows %@", level, levels[level]]);
        }
        // The redesign's words and details, the Music app's way; Very high is Spotify's lossy 320 kbps, not lossless.
        NSDictionary<NSNumber *, NSArray<NSString *> *> *redesign = @{
            @1: @[@"Low Quality", @"About 24 kbps"], @2: @[@"Normal Quality", @"About 96 kbps"], @3: @[@"High Quality", @"About 160 kbps"],
            @4: @[@"Highest Quality", @"About 320 kbps"], @5: @[@"Lossless", @"16-bit/44.1 kHz"], @6: @[@"Lossless 24-bit", @"24-bit/44.1 kHz"],
        };
        for (NSNumber *level in redesign) {
            SGAudioTier tier = SGAudioTierForBitrateLevel(level.longLongValue);
            check([SGAudioTierBadgeName(tier) isEqualToString:redesign[level][0]] && [SGAudioTierRateText(tier, 0) isEqualToString:redesign[level][1]]
                  && SGAudioTierSummary(tier).length > 0,
                  [NSString stringWithFormat:@"bitrateLevel %@ reads %@, %@, with a sentence (got %@, %@)", level, redesign[level][0], redesign[level][1],
                   SGAudioTierBadgeName(tier), SGAudioTierRateText(tier, 0)]);
        }
        check([SGAudioTierRateText(SGAudioTierLossless24, 48000) isEqualToString:@"24-bit/48 kHz"], @"a lossless rate reported is the one read");
        check([SGAudioTierFootnote(SGAudioTierVeryHigh) isEqualToString:@"Playing now · Spotify Very high"], @"the footnote names Spotify's own tier");
        check(!SGAudioTierBadgeName(SGAudioTierNone) && !SGAudioTierRateText(SGAudioTierNone, 44100) && !SGAudioTierSummary(SGAudioTierNone)
              && !SGAudioTierFootnote(SGAudioTierNone), @"no tier has no words");
        check(SGAudioTierIsLossless(SGAudioTierForBitrateLevel(5)) && SGAudioTierIsLossless(SGAudioTierForBitrateLevel(6))
              && !SGAudioTierIsLossless(SGAudioTierForBitrateLevel(4)), @"only hifi and hifi_24 draw the lossless glyph");
        check([shown(NO, YES, song, 6) isEqualToString:@"nothing"], @"the switch off shows nothing");
        check([shown(YES, NO, song, 6) isEqualToString:@"nothing"], @"another device playing shows nothing");
        check([shown(YES, YES, @"spotify:episode:0Q86acNRm6V9GYx55SXKwf", 4) isEqualToString:@"nothing"], @"a podcast shows nothing");
        check([shown(YES, YES, @"spotify:ad:000000012c603a6600000020316a17a1", 2) isEqualToString:@"nothing"], @"an ad shows nothing");
        check([shown(YES, YES, @"spotify:local:Artist:Album:Title:215", 6) isEqualToString:@"nothing"], @"a local file shows nothing");
        check([shown(YES, YES, nil, 6) isEqualToString:@"nothing"], @"no track shows nothing");

        NSDictionary<NSNumber *, NSString *> *sources = @{
            @0: @"none", @1: @"Streamed", @2: @"Streamed", @3: @"Downloaded", @4: @"Cached", @5: @"Local file", @6: @"none",
        };
        for (NSNumber *strategy in sources) {
            NSString *name = SGAudioSourceName(SGAudioSourceForStrategy(strategy.longLongValue)) ?: @"none";
            check([name isEqualToString:sources[strategy]], [NSString stringWithFormat:@"strategy %@ is %@", strategy, sources[strategy]]);
        }

        check([SGAudioSampleRateText(44100) isEqualToString:@"44.1 kHz"], @"44100 Hz reads 44.1 kHz");
        check([SGAudioSampleRateText(48000) isEqualToString:@"48 kHz"], @"48000 Hz reads 48 kHz");
        check([SGAudioSampleRateText(96000) isEqualToString:@"96 kHz"], @"96000 Hz reads 96 kHz");
        check(SGAudioSampleRateText(0) == nil, @"an unreported rate has no text");

        NSString *other = @"spotify:track:0VjIjW4GlUZAMYd2vXMi3b";
        check(SGAudioQualityDetailsStay(song, song, SGAudioTierHigh, YES), @"details stay while the same song shows a tier");
        check(!SGAudioQualityDetailsStay(song, other, SGAudioTierHigh, YES), @"a skip dismisses the details");
        check(!SGAudioQualityDetailsStay(song, nil, SGAudioTierNone, YES), @"another device or the switch off dismisses the details");
        check(!SGAudioQualityDetailsStay(song, song, SGAudioTierHigh, NO), @"the badge going dismisses the details");

        FakeView *window = view(nil, NO, 1), *units = view(window, NO, 1);
        check(SGAudioQualityViewDrawn(view(view(units, NO, 1), NO, 1)), @"a badge drawn all the way up takes taps");
        check(!SGAudioQualityViewDrawn(view(view(units, NO, 0), NO, 1)), @"a badge in a faded unit takes no taps");
        check(!SGAudioQualityViewDrawn(view(view(units, NO, 1), NO, 0.005)), @"a badge under UIKit's alpha floor takes no taps");
        check(!SGAudioQualityViewDrawn(view(view(view(window, YES, 1), NO, 1), NO, 1)), @"a badge under a hidden ancestor takes no taps");
    }
    if (failures) {
        NSLog(@"audio quality: %d check(s) failed", failures);
        return 1;
    }
    NSLog(@"audio quality: all checks passed");
    return 0;
}
