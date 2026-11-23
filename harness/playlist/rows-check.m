// The hairline under a playlist's track row (applyRow in Redesigned/Playlist/PlaylistRows.x): a 402x64 Encore.ListRow
// with its 48pt artwork 16pt in from the leading edge (trees/clean/playlist/02.txt). Left to right the line runs from
// 12pt after the artwork to 16pt short of the right edge; right to left the artwork is on the right and the line runs
// from 16pt in from the left edge to 12pt before the artwork. This file includes the generated rows source to reach the
// static function. Exits nonzero on the first failed check.
#import <UIKit/UIKit.h>
#import "../harness-fail.h"
#include "gen/PlaylistRows.m"

__attribute__((constructor(101))) static void sgr_rowsDefaults(void) {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"spotifyglass.redesign"];
}

static CGRect hairlineOf(BOOL rtl) {
    UISemanticContentAttribute direction = rtl ? UISemanticContentAttributeForceRightToLeft : UISemanticContentAttributeForceLeftToRight;
    UIView *cell = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 402, 64)];
    UIView *row = [[UIView alloc] initWithFrame:cell.bounds];
    row.accessibilityIdentifier = @"Encore.ListRow";
    cell.semanticContentAttribute = row.semanticContentAttribute = direction;
    [cell addSubview:row];
    UIView *art = [[UIView alloc] initWithFrame:CGRectMake(rtl ? 402 - 16 - 48 : 16, 8, 48, 48)];
    art.accessibilityIdentifier = @"Encore.ImageView";
    [row addSubview:art];
    HARNESS_CHECK(applyRow(cell));
    CALayer *line = nil;
    for (CALayer *layer in row.layer.sublayers) if (CGRectGetHeight(layer.frame) < 1) line = layer;
    if (!line || line.hidden || CGRectGetWidth(line.frame) < 1)
        HARNESS_FAIL(@"%@: the row has no hairline (%@)", rtl ? @"right to left" : @"left to right", line ? NSStringFromCGRect(line.frame) : @"none");
    return line.frame;
}

static void expect(NSString *what, CGRect line, CGFloat from, CGFloat to) {
    if (fabs(CGRectGetMinX(line) - from) > 0.01 || fabs(CGRectGetMaxX(line) - to) > 0.01) {
        HARNESS_FAIL(@"%@: the hairline spans %.1f..%.1f, expected %.1f..%.1f", what, CGRectGetMinX(line), CGRectGetMaxX(line), from, to);
    }
    NSLog(@"[harness] %@: hairline %.1f..%.1f", what, CGRectGetMinX(line), CGRectGetMaxX(line));
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        expect(@"left to right", hairlineOf(NO), 76, 386);
        expect(@"right to left", hairlineOf(YES), 16, 326);
        NSLog(@"[harness] PASS rows");
        fprintf(stderr, "[harness] PASS rows\n");
    }
    return 0;
}
