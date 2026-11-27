// The field color a page takes from its cover: the main color, not the bottom edge. A blue cover with a
// pale scanner border along its foot, which read by the edge turned the album page gray (device, 2026-09-18).
#import <UIKit/UIKit.h>
#import "Redesigned/Kit/SGRPalette.h"

// SGRTokens.m's accent comes from SGRAccent.x, which this does not compile.
UIColor *SGRAccentColor(void) { return UIColor.greenColor; }

static UIImage *cover(void) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(300, 300)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor colorWithRed:0.1 green:0.3 blue:0.9 alpha:1] setFill];
        UIRectFill(CGRectMake(0, 0, 300, 300));
        [[UIColor colorWithWhite:0.85 alpha:1] setFill];
        UIRectFill(CGRectMake(0, 255, 300, 45));
    }];
}

// An opaque, scale-one white cover isolates the backdrop's dimming and alpha ramp.
static UIImage *backdropCover(void) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    format.opaque = YES;
    format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(16, 16) format:format]
        imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [UIColor.whiteColor setFill];
            UIRectFill(CGRectMake(0, 0, 16, 16));
        }];
}

enum { kBackdropWidthPixels = 160, kBackdropHeightPixels = 400 };

static BOOL backdropMatches(UIImage *image) {
    CGImageRef backdrop = image.CGImage;
    if (!backdrop || CGImageGetWidth(backdrop) != kBackdropWidthPixels || CGImageGetHeight(backdrop) != kBackdropHeightPixels) {
        fprintf(stderr, "FAIL: backdrop must be 160x400 pixels\n");
        return NO;
    }
    uint8_t pixels[kBackdropHeightPixels][kBackdropWidthPixels][4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef bitmap = CGBitmapContextCreate(pixels, kBackdropWidthPixels, kBackdropHeightPixels, 8, kBackdropWidthPixels * 4, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!bitmap) {
        fprintf(stderr, "FAIL: backdrop bitmap context\n");
        return NO;
    }
    CGContextDrawImage(bitmap, CGRectMake(0, 0, kBackdropWidthPixels, kBackdropHeightPixels), backdrop);
    CGContextRelease(bitmap);
    // Independent contract: black rises from 25% to 55% at 55% of the height;
    // opacity stays one until there, then falls linearly to zero. Sample pixel centers.
    // At 400 rows, half a raster pixel shifts even the steeper alpha ramp by
    // less than 1/255; allow that plus one 8-bit rounding/dithering code value.
    const double quantizationBound = 2.0 / 255.0;
    for (NSNumber *row in @[@0, @109, @219, @220, @309, @399]) {
        NSUInteger y = row.unsignedIntegerValue;
        double position = (y + 0.5) / kBackdropHeightPixels;
        double dim = 0.25 + (0.55 - 0.25) * MIN(position / 0.55, 1.0);
        double alpha = position <= 0.55 ? 1.0 : (1.0 - position) / (1.0 - 0.55);
        double expected[] = {(1.0 - dim) * alpha, (1.0 - dim) * alpha, (1.0 - dim) * alpha, alpha};
        for (NSNumber *column in @[@0, @79, @159]) {
            NSUInteger x = column.unsignedIntegerValue;
            for (NSUInteger channel = 0; channel < 4; channel++) {
                double actual = pixels[y][x][channel] / 255.0;
                if (fabs(actual - expected[channel]) > quantizationBound) {
                    fprintf(stderr, "FAIL: backdrop (%lu,%lu) channel %lu: %.6f expected %.6f within 2/255\n",
                        (unsigned long)x, (unsigned long)y, (unsigned long)channel, actual, expected[channel]);
                    return NO;
                }
            }
        }
    }
    printf("backdrop: dimming and alpha ramp match within 2/255\n");
    return YES;
}

int main(void) {
    @autoreleasepool {
        __block int done = 0, fails = 0;
        for (int main = 0; main < 2; main++) {
            SGRPaletteRequest request = {.mainColor = main};
            [SGRPalette paletteForImage:cover() request:request completion:^(SGRPalette *palette) {
                CGFloat r, g, b, a;
                [palette.fieldColor getRed:&r green:&g blue:&b alpha:&a];
                BOOL blue = b > r + 0.05 && b > g;
                printf("%s: field %.3f %.3f %.3f, %s\n", main ? "main color" : "bottom edge", r, g, b, blue ? "blue" : "gray");
                if (blue != (BOOL)main) fails++;
                done++;
            }];
        }
        [SGRPalette paletteForImage:backdropCover() request:(SGRPaletteRequest){.backdropSize = {kBackdropWidthPixels, kBackdropHeightPixels}}
            completion:^(SGRPalette *palette) {
                if (!backdropMatches(palette.backdrop)) fails++;
                done++;
            }];
        NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:45];
        while (done < 3 && limit.timeIntervalSinceNow > 0)
            [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        if (done != 3) { fprintf(stderr, "FAIL: received %d of 3 palette completions\n", done); return 1; }
        printf(fails ? "FAIL\n" : "PASS\n");
        return fails;
    }
}
