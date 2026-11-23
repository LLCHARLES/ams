#import "LyricsBackground.h"
#import <Accelerate/Accelerate.h>
#import <CommonCrypto/CommonDigest.h>
#include <math.h>

static double bounded(double value, double fallback, double maximum) {
    return isfinite(value) ? MIN(MAX(value, 0), maximum) : fallback;
}
static SGLyricsBackgroundStyle normalized(SGLyricsBackgroundStyle style) {
    style.mode = MIN(MAX(style.mode, SGLyricsBackgroundCover), SGLyricsBackgroundSolid);
    style.darkness = bounded(style.darkness, .45, .85);
    style.blur = bounded(style.blur, 20, SGLyricsBackgroundMaxBlur);
    style.color &= 0xFFFFFF;
    return style;
}
static double number(NSUserDefaults *values, NSString *key, double fallback) {
    id value = [values objectForKey:key];
    return [value isKindOfClass:NSNumber.class] && isfinite([value doubleValue]) ? [value doubleValue] : fallback;
}
SGLyricsBackgroundStyle SGLyricsBackgroundDefault(NSString *prefix) {
    BOOL lock = [prefix isEqualToString:SGLyricsBackgroundLockScreen];
    return (SGLyricsBackgroundStyle){lock ? SGLyricsBackgroundBlur : SGLyricsBackgroundCover, .45, lock ? 60 : 20, 0x18181B};
}
SGLyricsBackgroundStyle SGLyricsBackgroundRead(NSString *prefix) {
    NSUserDefaults *values = NSUserDefaults.standardUserDefaults;
    SGLyricsBackgroundStyle fallback = SGLyricsBackgroundDefault(prefix);
    SGLyricsBackgroundStyle style = {
        .mode = (NSInteger)bounded(number(values, [prefix stringByAppendingString:@".mode"], fallback.mode), fallback.mode, 4),
        .darkness = bounded(number(values, [prefix stringByAppendingString:@".darkness"], fallback.darkness * 100),
                            fallback.darkness * 100, 85) / 100,
        .blur = bounded(number(values, [prefix stringByAppendingString:@".blur"], fallback.blur), fallback.blur, SGLyricsBackgroundMaxBlur),
        .color = (uint32_t)bounded(number(values, [prefix stringByAppendingString:@".color"], 0x18181B), 0x18181B, 0xFFFFFF),
    };
    return style;
}
NSString *SGLyricsBackgroundIdentity(SGLyricsBackgroundStyle style) {
    style = normalized(style);
    NSString *text = [NSString stringWithFormat:@"background-1:%ld:%.17g:%.17g:%06x",
                      (long)style.mode, (double)style.darkness, (double)style.blur, style.color];
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *key = [NSMutableString stringWithString:@"bg1"];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [key appendFormat:@"%02x", digest[i]];
    return key;
}

@interface SGLyricsBackgroundImage : NSObject {
@public
    CGImageRef source, image;
}
@end
@implementation SGLyricsBackgroundImage
- (void)dealloc { CGImageRelease(source); CGImageRelease(image); }
@end

static CGContextRef contextFor(size_t width, size_t height) {
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space,
                                                kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    return context;
}
static void fill(CGContextRef context, CGRect bounds, uint32_t rgb) {
    CGContextSetRGBFillColor(context, ((rgb >> 16) & 255) / 255., ((rgb >> 8) & 255) / 255., (rgb & 255) / 255., 1);
    CGContextFillRect(context, bounds);
}

CGImageRef SGLyricsBackgroundCreate(CGImageRef cover, CGSize size, SGLyricsBackgroundStyle style) {
    if (!isfinite(size.width) || !isfinite(size.height) || size.width < 1 || size.height < 1) return NULL;
    size = CGSizeMake(round(size.width), round(size.height));
    style = normalized(style);
    static NSCache<NSString *, SGLyricsBackgroundImage *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [NSCache new];
        cache.countLimit = 8;
        cache.totalCostLimit = 32 * 1024 * 1024;
    });
    NSString *key = [NSString stringWithFormat:@"%p:%@:%gx%g", cover, SGLyricsBackgroundIdentity(style), size.width, size.height];
    // The cached entry retains its source, so an allocator cannot reuse the pointer under a live key.
    // Serialize misses too: preview and video requests for one snapshot render the backdrop only once.
    @synchronized (cache) {
        SGLyricsBackgroundImage *ready = [cache objectForKey:key];
        if (ready) return CGImageRetain(ready->image);
        size_t width = (size_t)size.width, height = (size_t)size.height;
        CGContextRef context = contextFor(width, height);
        if (!context) return NULL;
        CGRect bounds = {CGPointZero, size};
        fill(context, bounds, style.mode == SGLyricsBackgroundSolid ? style.color : 0x18181B);
        if (cover && style.mode != SGLyricsBackgroundSolid) {
            CGFloat w = CGImageGetWidth(cover), h = CGImageGetHeight(cover);
            CGFloat scale = MAX(size.width / w, size.height / h);
            CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
            CGContextDrawImage(context, CGRectMake((size.width - w * scale) / 2, (size.height - h * scale) / 2,
                                                   w * scale, h * scale), cover);
            uint8_t *pixels = CGBitmapContextGetData(context);
            if (style.mode == SGLyricsBackgroundMonochrome) {
                for (size_t i = 0; i < width * height; i++) {
                    uint8_t *p = pixels + i * 4;
                    uint8_t gray = (54 * p[0] + 183 * p[1] + 19 * p[2]) / 256;
                    p[0] = p[1] = p[2] = gray;
                }
            } else if (style.mode == SGLyricsBackgroundBlur && style.blur > 0) {
                uint32_t kernel = 2 * (uint32_t)round(style.blur * size.width / 640) + 1;
                vImage_Buffer a = {pixels, height, width, width * 4};
                NSMutableData *scratch = [NSMutableData dataWithLength:width * height * 4];
                vImage_Buffer b = {scratch.mutableBytes, height, width, width * 4};
                // Three edge-extended box passes approximate a Gaussian without GPU or a low-resolution cover.
                vImageBoxConvolve_ARGB8888(&a, &b, NULL, 0, 0, kernel, kernel, NULL, kvImageEdgeExtend);
                vImageBoxConvolve_ARGB8888(&b, &a, NULL, 0, 0, kernel, kernel, NULL, kvImageEdgeExtend);
                vImageBoxConvolve_ARGB8888(&a, &b, NULL, 0, 0, kernel, kernel, NULL, kvImageEdgeExtend);
                memcpy(pixels, scratch.bytes, scratch.length);
            } else if (style.mode == SGLyricsBackgroundGradient) {
                // Average the actual cover's four quadrants; no curated or invented palette.
                CGFloat colors[16] = {0};
                for (size_t q = 0; q < 4; q++) {
                    size_t x0 = q % 2 * width / 2, x1 = (q % 2 + 1) * width / 2;
                    size_t y0 = q / 2 * height / 2, y1 = (q / 2 + 1) * height / 2;
                    double sums[3] = {0};
                    size_t count = 0;
                    for (size_t y = y0; y < y1; y++) for (size_t x = x0; x < x1; x++) {
                        uint8_t *p = pixels + (y * width + x) * 4;
                        for (NSUInteger c = 0; c < 3; c++) sums[c] += p[c];
                        count++;
                    }
                    for (NSUInteger c = 0; c < 3; c++) colors[q * 4 + c] = count ? sums[c] / count / 255 : 0;
                    colors[q * 4 + 3] = 1;
                }
                CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
                CGGradientRef gradient = CGGradientCreateWithColorComponents(space, colors, NULL, 4);
                CGContextDrawLinearGradient(context, gradient, CGPointZero, CGPointMake(size.width, size.height), 0);
                CGGradientRelease(gradient);
                CGColorSpaceRelease(space);
            }
        }
        CGContextSetRGBFillColor(context, 0, 0, 0, style.darkness);
        CGContextFillRect(context, bounds);
        SGLyricsBackgroundImage *made = [SGLyricsBackgroundImage new];
        made->source = CGImageRetain(cover);
        made->image = CGBitmapContextCreateImage(context);
        CGContextRelease(context);
        [cache setObject:made forKey:key cost:width * height * 4 + (cover ? CGImageGetBytesPerRow(cover) * CGImageGetHeight(cover) : 0)];
        return CGImageRetain(made->image);
    }
}
