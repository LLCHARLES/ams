#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <sys/resource.h>
#include <math.h>
#import "Shared/LyricsBackground/LyricsBackground.h"

static int failures;
static void check(BOOL yes, NSString *what) {
    printf("%s %s\n", yes ? "ok  " : "FAIL", what.UTF8String);
    if (!yes) failures++;
}
static CGContextRef context(size_t w, size_t h) {
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef c = CGBitmapContextCreate(NULL, w, h, 8, w * 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    return c;
}
static CGImageRef cover(BOOL stripes, BOOL blue) {
    CGContextRef c = context(640, 640);
    for (NSUInteger x = 0; x < 640; x++) {
        BOOL lit = !stripes || x % 4 < 2;
        CGContextSetRGBFillColor(c, blue ? 0 : lit, 0, blue ? lit : 0, 1);
        CGContextFillRect(c, CGRectMake(x, 0, 1, 640));
    }
    CGImageRef image = CGBitmapContextCreateImage(c);
    CGContextRelease(c);
    return image;
}
static NSData *pixels(CGImageRef image) {
    size_t w = CGImageGetWidth(image), h = CGImageGetHeight(image);
    CGContextRef c = context(w, h);
    CGContextDrawImage(c, CGRectMake(0, 0, w, h), image);
    NSData *data = [NSData dataWithBytes:CGBitmapContextGetData(c) length:w * h * 4];
    CGContextRelease(c);
    return data;
}
static NSUInteger channel(CGImageRef image, NSUInteger x, NSUInteger component) {
    NSData *data = pixels(image);
    return ((const uint8_t *)data.bytes)[(CGImageGetWidth(image) * (CGImageGetHeight(image) / 2) + x) * 4 + component];
}

int main(void) {
    @autoreleasepool {
        NSString *prefix = @"retrine.harness.background";
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        // Volatile arguments shadow persistent preferences and disappear with this process.
        [defaults setVolatileDomain:@{} forName:NSArgumentDomain];
        SGLyricsBackgroundStyle initial = SGLyricsBackgroundRead(prefix);
        check(initial.mode == 0 && initial.darkness == .45 && initial.blur == 20 && initial.color == 0x18181B, @"defaults are the frozen API values");
        NSDictionary *invalid = @{
            [prefix stringByAppendingString:@".mode"]: @99,
            [prefix stringByAppendingString:@".darkness"]: @999,
            [prefix stringByAppendingString:@".blur"]: @(-20),
            [prefix stringByAppendingString:@".color"]: @(-1),
        };
        [defaults setVolatileDomain:invalid forName:NSArgumentDomain];
        SGLyricsBackgroundStyle clamped = SGLyricsBackgroundRead(prefix);
        check(clamped.mode == 4 && clamped.darkness == .85 && clamped.blur == 0 && clamped.color == 0, @"stored values clamp to their bounds");
        check([[defaults volatileDomainForName:NSArgumentDomain] isEqual:invalid], @"reading does not mutate preferences");
        [defaults setVolatileDomain:@{
            [prefix stringByAppendingString:@".mode"]: @"bad",
            [prefix stringByAppendingString:@".darkness"]: @(NAN),
            [prefix stringByAppendingString:@".blur"]: @(INFINITY),
            [prefix stringByAppendingString:@".color"]: @"bad"
        } forName:NSArgumentDomain];
        check([SGLyricsBackgroundIdentity(SGLyricsBackgroundRead(prefix)) isEqual:SGLyricsBackgroundIdentity(initial)],
              @"non-finite and wrong-type stored values use defaults");
        [defaults setVolatileDomain:@{} forName:NSArgumentDomain];

        CGImageRef detailed = cover(YES, NO), red = cover(NO, NO), blue = cover(NO, YES);
        CGSize size = CGSizeMake(640, 640);
        SGLyricsBackgroundStyle sharpStyle = {SGLyricsBackgroundCover, 0, 20, 0x18181B};
        CGImageRef sharp = SGLyricsBackgroundCreate(detailed, size, sharpStyle);
        check(channel(sharp, 320, 0) > 250 && channel(sharp, 322, 0) < 5, @"sharp cover retains two-pixel detail at full raster");
        CGImageRef again = SGLyricsBackgroundCreate(detailed, size, sharpStyle);
        check(again == sharp, @"same source/style/size returns the cached image");
        CGImageRelease(again);
        CGImageRef other = SGLyricsBackgroundCreate(blue, size, sharpStyle);
        check(other != sharp && channel(other, 320, 2) > 250, @"source identity separates cached images");
        CGImageRelease(other);
        other = SGLyricsBackgroundCreate(detailed, CGSizeMake(320, 320), sharpStyle);
        check(other != sharp && CGImageGetWidth(other) == 320, @"raster size separates cached images");
        CGImageRelease(other);

        for (SGLyricsBackgroundMode mode = 0; mode <= 4; mode++) {
            SGLyricsBackgroundStyle style = {mode, 0, 20, 0x336699};
            CFAbsoluteTime at = CFAbsoluteTimeGetCurrent();
            CGImageRef image = SGLyricsBackgroundCreate(detailed, CGSizeMake(1200, 1600), style);
            double elapsed = (CFAbsoluteTimeGetCurrent() - at) * 1000;
            printf("mode %ld: 1200x1600 %.2f ms\n", (long)mode, elapsed);
            check(image && CGImageGetWidth(image) == 1200 && CGImageGetHeight(image) == 1600, @"mode renders requested raster");
            CGImageRef repeated = SGLyricsBackgroundCreate(detailed, CGSizeMake(1200, 1600), style);
            check([pixels(image) isEqual:pixels(repeated)], @"mode output is deterministic");
            CGImageRelease(repeated);
            if (mode == SGLyricsBackgroundMonochrome) {
                NSData *data = pixels(image);
                const uint8_t *p = data.bytes;
                BOOL equal = YES;
                for (NSUInteger i = 0; i < data.length; i += 4) if (p[i] != p[i + 1] || p[i] != p[i + 2]) equal = NO;
                check(equal, @"monochrome channels are equal throughout");
            } else if (mode == SGLyricsBackgroundSolid) {
                check(channel(image, 300, 0) == 0x33 && channel(image, 300, 1) == 0x66 && channel(image, 300, 2) == 0x99,
                      @"solid uses the selected RGB");
            }
            CGImageRelease(image);
        }
        SGLyricsBackgroundStyle style = sharpStyle;
        style.mode = SGLyricsBackgroundBlur;
        CGImageRef blurred = SGLyricsBackgroundCreate(detailed, size, style);
        check(abs((int)channel(blurred, 320, 0) - (int)channel(blurred, 322, 0)) < 10, @"blur removes fine stripe contrast");
        style.blur = 0;
        CGImageRef unblurred = SGLyricsBackgroundCreate(detailed, size, style);
        check([pixels(unblurred) isEqual:pixels(sharp)], @"zero blur retains sharp detail");
        style.mode = SGLyricsBackgroundGradient;
        CGImageRef redGradient = SGLyricsBackgroundCreate(red, size, style);
        CGImageRef blueGradient = SGLyricsBackgroundCreate(blue, size, style);
        check(channel(redGradient, 320, 0) > 250 && channel(redGradient, 320, 2) < 5
              && channel(blueGradient, 320, 2) > 250 && channel(blueGradient, 320, 0) < 5,
              @"gradient colors come from the actual album, not a preset palette");
        style = sharpStyle;
        style.darkness = .85;
        CGImageRef dark = SGLyricsBackgroundCreate(red, size, style);
        check(abs((int)channel(dark, 320, 0) - 38) <= 1, @"85 percent darkening has the expected brightness");
        check(![SGLyricsBackgroundIdentity(style) isEqual:SGLyricsBackgroundIdentity(sharpStyle)], @"style changes separate render identities");
        style.darkness = INFINITY;
        SGLyricsBackgroundStyle fallback = sharpStyle;
        fallback.darkness = .45;
        check([SGLyricsBackgroundIdentity(style) isEqual:SGLyricsBackgroundIdentity(fallback)], @"non-finite style normalizes before identity");
        for (NSInteger mode = 0; mode <= 4; mode++) {
            style = (SGLyricsBackgroundStyle){mode, 0, 20, 0x336699};
            CGImageRef empty = SGLyricsBackgroundCreate(NULL, size, style);
            check(channel(empty, 320, 0) == (mode == 4 ? 0x33 : 0x18)
                  && channel(empty, 320, 2) == (mode == 4 ? 0x99 : 0x1B), @"no cover is safe; Solid still uses the chosen color");
            CGImageRelease(empty);
        }
        CGImageRelease(detailed); CGImageRelease(red); CGImageRelease(blue); CGImageRelease(sharp);
        CGImageRelease(blurred); CGImageRelease(unblurred); CGImageRelease(redGradient); CGImageRelease(blueGradient); CGImageRelease(dark);
        struct rusage usage;
        getrusage(RUSAGE_SELF, &usage);
        printf("peak RSS %.2f MiB\n", usage.ru_maxrss / 1048576.);
        printf("%s\n", failures ? "FAILED" : "all passed");
        return failures ? 1 : 0;
    }
}
