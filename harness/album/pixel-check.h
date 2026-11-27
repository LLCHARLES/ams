// What faces-check.h and more-check.h share: a run of steps on the main queue, a view drawn as the screen shows it, its
// pixels read in sRGB, and OKLab worked out here (Björn Ottosson's matrices), apart from the tweak's own conversion.
#pragma once
#import <UIKit/UIKit.h>
#import "../harness-wait.h"

// One independent run-loop turn per action; run from a timer so an action
// waiting for a delivered image can service the main queue.
static void checkSteps(NSArray *steps, NSUInteger index) {
    if (index >= steps.count) return;
    id step = steps[index];
    ((void (^)(void))step)();
    [NSTimer scheduledTimerWithTimeInterval:0 repeats:NO block:^(NSTimer *timer) {
        checkSteps(steps, index + 1);
    }];
}

static void checkShot(NSString *name) {
    NSLog(@"[harness] SHOT %@", name);
    if (![NSProcessInfo.processInfo.arguments containsObject:@"capture-shots"]) return;
    NSString *ack = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [CATransaction flush];
    NSLog(@"[harness] CAPTURE %@ %@", name, ack);
    HARNESS_AWAIT([NSFileManager.defaultManager fileExistsAtPath:ack]);
    HARNESS_CHECK([NSFileManager.defaultManager removeItemAtPath:ack error:nil]);
}

// `view` and what it holds alone, as the screen draws it (masks included), on a clear sRGB canvas.
static UIImage *checkRender(UIView *view) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
    format.opaque = NO;
    return [[[UIGraphicsImageRenderer alloc] initWithBounds:view.bounds format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:YES];
    }];
}

typedef struct { CGFloat r, g, b, a; } CheckPixel;

// The pixel of `image` under `point` (in points), straight alpha, sRGB.
static CheckPixel checkPixel(UIImage *image, CGPoint point) {
    CGImageRef cg = image.CGImage;
    size_t width = CGImageGetWidth(cg), height = CGImageGetHeight(cg);
    long x = (long)floor(point.x * image.scale), y = (long)floor(point.y * image.scale);
    HARNESS_CHECK(x >= 0 && y >= 0 && x < (long)width && y < (long)height);
    uint8_t rgba[4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(rgba, 1, 1, 8, 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGContextSetBlendMode(context, kCGBlendModeCopy);
    CGContextDrawImage(context, CGRectMake(-x, -((long)height - y - 1), width, height), cg);
    CGContextRelease(context);
    CheckPixel pixel = {0, 0, 0, rgba[3] / 255.0};
    if (rgba[3]) pixel = (CheckPixel){rgba[0] / (CGFloat)rgba[3], rgba[1] / (CGFloat)rgba[3], rgba[2] / (CGFloat)rgba[3], rgba[3] / 255.0};
    return pixel;
}

typedef struct { CGFloat L, a, b; } CheckLab;

static CGFloat checkLinear(CGFloat c) {
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

static CheckLab checkLab(CGFloat red, CGFloat green, CGFloat blue) {
    CGFloat r = checkLinear(red), g = checkLinear(green), b = checkLinear(blue);
    CGFloat l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    CGFloat m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    CGFloat s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    return (CheckLab){0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                      1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                      0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s};
}

static CGFloat checkChroma(CheckLab lab) {
    return hypot(lab.a, lab.b);
}

// Degrees between two hues, 0 to 180.
static CGFloat checkHueGap(CheckLab one, CheckLab other) {
    CGFloat gap = fabs(atan2(one.b, one.a) - atan2(other.b, other.a)) * 180 / M_PI;
    return gap > 180 ? 360 - gap : gap;
}

// Depth first, `root` included.
static UIView *checkFind(UIView *root, BOOL (^match)(UIView *view)) {
    if (match(root)) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = checkFind(sub, match);
        if (found) return found;
    }
    return nil;
}
