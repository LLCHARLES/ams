// The cover read (Redesigned/Kit/SGRCoverRead.h) on covers drawn in code (cover-fixtures.h): the kind each is read as,
// the family of its page colour, where it stops being sharp, the pixel reading before the final one, a Vision error,
// a transparent cover, two images of the same picture, and page colours brought into sRGB by their chroma alone.
// Vision answers for itself except where a check says what it finds (the portrait's face) or that it fails.
// Logs PASS or FAIL lines and exits 1 on the first failure (../harness-fail.h).
#import <UIKit/UIKit.h>
#import <Vision/Vision.h>
#import "Redesigned/Kit/SGRCoverRead.h"
#import "../harness-fail.h"
#import "cover-fixtures.h"

UIColor *SGRAccentColor(void) { return nil; }

// What the next read's Vision step answers: the real detector unless told otherwise.
static NSArray<NSValue *> *givenFaces;
static BOOL visionFails;
static NSArray<NSValue *> *detectedFaces;

BOOL SGRCoverReadTestSubjects(CGImageRef bitmap, SGRCoverVision vision, NSArray<NSValue *> **faces, NSArray<NSValue *> **objects) {
    if (visionFails) return NO;
    if (givenFaces) {
        *faces = givenFaces;
        *objects = @[];
        return YES;
    }
    BOOL result = vision(bitmap, faces, objects);
    detectedFaces = *faces;
    return result;
}

// Every reading delivered for `image`, waiting for the final one.
static NSArray<SGRCoverReading *> *readAll(UIImage *image) {
    NSMutableArray *delivered = [NSMutableArray array];
    __block BOOL finished = NO;
    BOOL started = SGRCoverRead(image, ^(SGRCoverReading *reading) {
        if (!reading) {
            finished = YES;
            return;
        }
        [delivered addObject:reading];
        if (reading.final) finished = YES;
    });
    HARNESS_CHECK(started);
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:45];
    while (!finished && [limit timeIntervalSinceNow] > 0) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    HARNESS_CHECK(finished);
    return delivered;
}

static SGRCoverReading *readFinal(UIImage *image) {
    return readAll(image).lastObject;
}

static NSString *kindName(SGRCoverKind kind) {
    return @[@"foot", @"solid dark", @"solid light", @"solid colour", @"dark accent", @"portrait", @"colourful"][kind];
}

static CGFloat hueDegrees(SGRLab lab) {
    CGFloat hue = atan2(lab.b, lab.a) * 180 / M_PI;
    return hue < 0 ? hue + 360 : hue;
}

static SGRLab pageLab(SGRCoverReading *reading) {
    CGFloat r, g, b, a;
    [reading.pageColor getRed:&r green:&g blue:&b alpha:&a];
    return SGRLabFromRGB(r, g, b);
}

static void expectKind(NSString *name, SGRCoverReading *reading, SGRCoverKind kind) {
    if (!reading) HARNESS_FAIL(@"%@: no reading", name);
    if (reading.kind != kind) HARNESS_FAIL(@"%@ read as %@, not %@", name, kindName(reading.kind), kindName(kind));
    SGRLab page = pageLab(reading);
    // Every page colour is held to L 0.44.
    if (page.L > 0.44 + 0.005) HARNESS_FAIL(@"%@: page colour L %.3f over 0.44", name, page.L);
    NSLog(@"[harness] %@: %@, page L %.3f C %.3f h %.0f", name, kindName(kind), page.L, hypot(page.a, page.b), hueDegrees(page));
}

// The page colour's hue between `from` and `to` degrees with chroma, or no chroma to speak of when both are 0.
static void expectFamily(NSString *name, SGRCoverReading *reading, CGFloat from, CGFloat to, CGFloat maxL) {
    SGRLab page = pageLab(reading);
    CGFloat chroma = hypot(page.a, page.b), hue = hueDegrees(page);
    if (page.L > maxL) HARNESS_FAIL(@"%@: page colour L %.3f, not %.2f or under", name, page.L, maxL);
    if (from == 0 && to == 0) {
        if (chroma > 0.03) HARNESS_FAIL(@"%@: page colour chroma %.3f, not gray", name, chroma);
        return;
    }
    if (chroma < 0.04 || hue < from || hue > to) HARNESS_FAIL(@"%@: page colour hue %.0f chroma %.3f, not %.0f-%.0f", name, hue, chroma, from, to);
}

int main(void) {
    @autoreleasepool {
        // Solid: a flat border with centred art, dark, light and red; the art's bottom (80% of the side) and 5 points
        // more is where it stops being sharp, under 0.86.
        SGRCoverReading *dark = readFinal(solidDarkCover());
        expectKind(@"solid dark", dark, SGRCoverKindSolidDark);
        expectFamily(@"solid dark", dark, 0, 0, 0.2);
        HARNESS_CHECK(readAll(solidDarkCover()).count == 1);
        SGRCoverSharpness sharp = SGRCoverSharpnessFor(dark, 0.95);
        if (fabs(dark.contentBottom - 0.80) > 1.5 / 64 || fabs(sharp.sharpEnd - 0.85) > 1.5 / 64)
            HARNESS_FAIL(@"solid dark: content to %.3f, sharp to %.3f; not 0.80 and 0.85", dark.contentBottom, sharp.sharpEnd);
        // Its gray border is its own page colour: no blur, a 120 pt mix.
        if (sharp.blurRadius != 0 || sharp.mixLength != 120) HARNESS_FAIL(@"solid dark: blur %.0f mix %.0f, not 0 and 120", sharp.blurRadius, sharp.mixLength);

        SGRCoverReading *light = readFinal(solidLightCover());
        expectKind(@"solid light", light, SGRCoverKindSolidLight);
        expectFamily(@"solid light", light, 0, 0, 0.44 + 0.005);
        SGRCoverSharpness lightSharp = SGRCoverSharpnessFor(light, 0.95);
        if (lightSharp.blurRadius != 24 || lightSharp.sharpEnd > 0.86 || lightSharp.sharpEnd < 0.80)
            HARNESS_FAIL(@"solid light: sharp to %.3f blur %.0f; not 0.80-0.86 and 24", lightSharp.sharpEnd, lightSharp.blurRadius);

        SGRCoverReading *red = readFinal(solidRedCover());
        expectKind(@"solid red", red, SGRCoverKindSolidColour);
        expectFamily(@"solid red", red, 10, 45, 0.44 + 0.005);

        // Broken along 8% of the border it is still solid; with the art over 72% of the side it is not.
        expectKind(@"marked sleeve", readFinal(markedSleeveCover()), SGRCoverKindSolidDark);
        SGRCoverReading *large = readFinal(largeArtCover());
        if (SGRCoverKindIsSolid(large.kind)) HARNESS_FAIL(@"large art read as %@, not as art", kindName(large.kind));
        NSLog(@"[harness] large art: %@", kindName(large.kind));

        // A tiny bright logo on black: the black.
        SGRCoverReading *logo = readFinal(tinyLogoCover());
        expectKind(@"tiny logo", logo, SGRCoverKindSolidDark);
        expectFamily(@"tiny logo", logo, 0, 0, 0.2);

        // Dark with a large orange accent: the orange, not the dark.
        givenFaces = @[];
        NSArray<SGRCoverReading *> *accentReadings = readAll(darkAccentCover());
        SGRCoverReading *accent = accentReadings.lastObject;
        expectKind(@"dark accent", accent, SGRCoverKindDarkAccent);
        expectFamily(@"dark accent", accent, 40, 85, 0.44 + 0.005);
        // Not solid, so the pixel reading came first and the final one after it.
        if (accentReadings.count != 2 || accentReadings[0].final || !accentReadings[1].final)
            HARNESS_FAIL(@"dark accent: %lu readings, not a pixel one then a final one", (unsigned long)accentReadings.count);
        SGRCoverSharpness accentSharp = SGRCoverSharpnessFor(accent, 0.95);
        if (accentSharp.sharpEnd != 0.90 || accentSharp.blurRadius != 64)
            HARNESS_FAIL(@"dark accent: sharp to %.3f blur %.0f from 0.95, not 0.90 and 64", accentSharp.sharpEnd, accentSharp.blurRadius);
        if (SGRCoverSharpnessFor(accent, 0.3).sharpEnd != 0.60) HARNESS_FAIL(@"dark accent: sharp end from 0.3 not held to 0.60");

        // The old flat rectangle was only a test double, not a detectable face.
        VNDetectFaceRectanglesRequest *rectangleFaces = [VNDetectFaceRectanglesRequest new];
        NSError *visionError = nil;
        VNImageRequestHandler *rectangleHandler = [[VNImageRequestHandler alloc] initWithCGImage:portraitCover().CGImage options:@{}];
        HARNESS_CHECK([rectangleHandler performRequests:@[rectangleFaces] error:&visionError]);
        HARNESS_CHECK(rectangleFaces.results.count == 0);
        NSLog(@"[harness] original rectangle portrait: Vision detected 0 faces");
        // Keep the explicit face-box double for a face occupying most of the foot: exclusion picks grass, not skin.
        givenFaces = @[[NSValue valueWithCGRect:kPortraitFace]];
        NSArray<SGRCoverReading *> *portraitReadings = readAll(portraitCover());
        SGRCoverReading *portrait = portraitReadings.lastObject;
        expectKind(@"portrait", portrait, SGRCoverKindPortrait);
        expectFamily(@"portrait", portrait, 120, 160, 0.44 + 0.005);
        if (portraitReadings.firstObject.kind == SGRCoverKindPortrait) HARNESS_FAIL(@"portrait: the pixel reading saw a face");
        // Held under the face's bottom (1.0) to 0.9; with the face over half of it the sharp end reaches the face.
        if (SGRCoverSharpnessFor(portrait, 0.5).sharpEnd != 0.90) HARNESS_FAIL(@"portrait: sharp end not under the face, held to 0.90");

        // Vision fails on the same picture: the pixel reading, final.
        givenFaces = nil;
        visionFails = YES;
        UIImage *failed = fixture(^(CGContextRef c, CGFloat side) {
            [portraitCover() drawInRect:CGRectMake(0, 0, side, side)];
            fill(c, CGRectMake(0, 0, 24, 24), 0, 0, 0);   // another picture, so not the portrait's cached reading
        });
        NSArray<SGRCoverReading *> *failedReadings = readAll(failed);
        if (failedReadings.count != 2 || !failedReadings[1].final || failedReadings[1].kind != failedReadings[0].kind
            || failedReadings[1].kind == SGRCoverKindPortrait)
            HARNESS_FAIL(@"Vision failing: %lu readings, final %@", (unsigned long)failedReadings.count, kindName(failedReadings.lastObject.kind));
        NSLog(@"[harness] Vision failing: kept the pixel reading, %@", kindName(failedReadings[1].kind));
        visionFails = NO;

        // A drawn face Vision itself finds, its lowest edge past half the height: a portrait, the colour of the
        // foot around the face, the shoulders and the sky, both blue.
        NSArray<SGRCoverReading *> *faceReadings = readAll(faceCover());
        SGRCoverReading *face = faceReadings.lastObject;
        if (faceReadings.firstObject.kind == SGRCoverKindPortrait) HARNESS_FAIL(@"drawn face: the pixel reading saw a face");
        expectKind(@"drawn face (Vision)", face, SGRCoverKindPortrait);
        expectFamily(@"drawn face (Vision)", face, 230, 280, 0.44 + 0.005);
        HARNESS_CHECK(detectedFaces.count > 0);
        CGFloat faceBottom = 0, faceArea = 0;
        for (NSValue *box in detectedFaces) {
            CGRect rect = box.CGRectValue;
            faceBottom = MAX(faceBottom, CGRectGetMaxY(rect));
            faceArea += rect.size.width * rect.size.height;
        }
        HARNESS_CHECK(faceArea >= 0.05 && faceBottom >= 0.5);
        CGFloat faceSharpEnd = SGRCoverSharpnessFor(face, 0.5).sharpEnd;
        HARNESS_CHECK(faceSharpEnd >= faceBottom && faceSharpEnd >= 0.60 && faceSharpEnd <= 0.90);
        NSLog(@"[harness] real Vision: %@, area %.3f, face bottom %.3f, sharp boundary %.3f", detectedFaces, faceArea, faceBottom, faceSharpEnd);

        // Colourful: the widest of the strong colours, magenta, not their average. Vision answers for itself.
        SGRCoverReading *colourful = readFinal(colourfulCover());
        expectKind(@"colourful", colourful, SGRCoverKindColourful);
        expectFamily(@"colourful", colourful, 300, 350, 0.44 + 0.005);

        // Two images of the same picture: the second is the first's reading, from the cache.
        SGRCoverReading *again = readFinal(colourfulCover());
        if (again != colourful || again.identity != colourful.identity) HARNESS_FAIL(@"the same picture again was read again");

        // Nothing opaque to read: nil, and nothing at all for a cover narrower than 80 pt.
        __block BOOL answered = NO, nilReading = NO;
        HARNESS_CHECK(SGRCoverRead(transparentCover(), ^(SGRCoverReading *reading) { answered = YES; nilReading = reading == nil; }));
        NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:45];
        while (!answered && [limit timeIntervalSinceNow] > 0) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        if (!answered || !nilReading) HARNESS_FAIL(@"a transparent cover was %@", answered ? @"read" : @"never answered");
        UIImage *small = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(60, 60)] imageWithActions:^(UIGraphicsImageRendererContext *c) {}];
        HARNESS_CHECK(!SGRCoverRead(small, ^(SGRCoverReading *reading) { HARNESS_FAIL(@"a 60 pt cover was answered"); }));

        // Page colours out of sRGB come back in it with their hue, their chroma reduced and their lightness held.
        for (NSArray<NSNumber *> *rgb in @[@[@0, @1, @0], @[@0, @0, @1], @[@1, @0, @1], @[@0, @1, @1]]) {
            SGRLab source = SGRLabFromRGB(rgb[0].doubleValue, rgb[1].doubleValue, rgb[2].doubleValue);
            SGRLab page = SGRCoverPageLab(source, NO);
            CGFloat r, g, b;
            SGRLabToRGB(page, &r, &g, &b);
            SGRLab back = SGRLabFromRGB(r, g, b);
            CGFloat hueShift = fabs(remainder(hueDegrees(page) - hueDegrees(source), 360));
            if (SGRLabDistance(back, page) > 0.002 || hueShift > 0.5 || fabs(page.L - MIN(source.L, 0.44)) > 1e-6)
                HARNESS_FAIL(@"page colour of %@ is off sRGB or its hue: moved %.4f in and out, hue %.2f", rgb, SGRLabDistance(back, page), hueShift);
            if (SGRCoverPageLab(source, YES).L > 0.40 + 1e-6) HARNESS_FAIL(@"Increase Contrast page colour over L 0.40");
        }
        NSLog(@"[harness] PASS cover read: solid dark/light/red, a marked sleeve, large art, a tiny logo, a dark accent, a portrait, "
              "Vision failing, a face Vision finds, colourful, the same picture twice, transparent and narrow covers, page colours in sRGB");
    }
    return 0;
}
