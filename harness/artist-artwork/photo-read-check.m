// The artist variant of the picture read (Redesigned/Kit/SGRCoverRead.h, SGRPhotoRead) on photos drawn in code
// (photo-fixtures.h): faces found by Vision itself (a face on the bottom edge, a large centred one, none, a dark stage),
// faces given (one in the foot, a tiny one, a group, one partly outside the photo, one over all of
// the foot), Vision failing, one Vision pass per picture, and the page colour picked against today's.
// Logs PASS or FAIL lines and exits 1 on the first failure (../harness-fail.h); photo-check.sh runs it, and again on
// mutated copies of SGRCoverRead.m that have to fail it.
#import <UIKit/UIKit.h>
#import "Redesigned/Kit/SGRCoverRead.h"
#import "../harness-fail.h"
#import "photo-fixtures.h"

UIColor *SGRAccentColor(void) { return nil; }

// What the next read's Vision step answers: the real detector unless told otherwise. Counted, on the read's queue.
static NSArray<NSValue *> *givenFaces;
static BOOL visionFails;
static NSArray<NSValue *> *detectedFaces;
static NSUInteger visionPasses;

BOOL SGRCoverReadTestSubjects(CGImageRef bitmap, SGRCoverVision vision, NSArray<NSValue *> **faces, NSArray<NSValue *> **objects) {
    visionPasses++;
    if (visionFails) return NO;
    if (givenFaces) {
        *faces = givenFaces;
        *objects = @[];
        return YES;
    }
    BOOL result = vision(bitmap, faces, objects);
    detectedFaces = *faces;
    if (result && (*objects).count) HARNESS_FAIL(@"a photo's Vision step found salient objects; it looks for faces alone");
    return result;
}

static NSValue *box(CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    return [NSValue valueWithCGRect:CGRectMake(x, y, w, h)];
}

// The one reading delivered for `image`; a second delivery fails.
static SGRPhotoReading *readOf(UIImage *image) {
    __block NSUInteger calls = 0;
    __block SGRPhotoReading *result = nil;
    HARNESS_CHECK(SGRPhotoRead(image, ^(SGRPhotoReading *reading) {
        calls++;
        if (calls != 1) HARNESS_FAIL(@"duplicate photo reading");
        result = reading;
    }));
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:45];
    while (!calls && [limit timeIntervalSinceNow] > 0) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    if (calls != 1) HARNESS_FAIL(@"%lu deliveries of one read, not 1", (unsigned long)calls);
    return result;
}

static CGFloat chromaOf(SGRLab lab) {
    return hypot(lab.a, lab.b);
}

static CGFloat hueOf(SGRLab lab) {
    CGFloat hue = atan2(lab.b, lab.a) * 180 / M_PI;
    return hue < 0 ? hue + 360 : hue;
}

static CGFloat hueDistance(CGFloat one, CGFloat other) {
    return fabs(remainder(one - other, 360));
}

static SGRLab labOf(const CGFloat rgb[3]) {
    return SGRLabFromRGB(rgb[0], rgb[1], rgb[2]);
}

// The spec's foot colour from a mean: chroma lifted 1.15 times unless under 0.03, held to 0.15.
static SGRLab lifted(SGRLab lab) {
    CGFloat chroma = chromaOf(lab), hue = atan2(lab.b, lab.a);
    if (chroma >= 0.03) chroma = MIN(chroma * 1.15, 0.15);
    return (SGRLab){lab.L, chroma * cos(hue), chroma * sin(hue)};
}

static SGRLab polar(CGFloat L, CGFloat chroma, CGFloat hueDegrees) {
    return (SGRLab){L, chroma * cos(hueDegrees * M_PI / 180), chroma * sin(hueDegrees * M_PI / 180)};
}

static void expectNear(NSString *name, SGRLab got, SGRLab want, CGFloat within) {
    CGFloat distance = SGRLabDistance(got, want);
    if (distance > within)
        HARNESS_FAIL(@"%@: L %.3f a %.3f b %.3f, %.4f from L %.3f a %.3f b %.3f (allowed %.3f)", name, got.L, got.a, got.b, distance,
                     want.L, want.a, want.b, within);
}

static CGFloat largestDetected(void) {
    CGFloat largest = 0;
    for (NSValue *face in detectedFaces) {
        CGRect shown = CGRectIntersection(face.CGRectValue, CGRectMake(0, 0, 1, 1));
        largest = MAX(largest, shown.size.width * shown.size.height);
    }
    return largest;
}

int main(void) {
    @autoreleasepool {
        // A face given over the middle of the foot: the foot's colour is the teal either side of it, lifted.
        givenFaces = @[[NSValue valueWithCGRect:kGivenFootFace]];
        SGRPhotoReading *given = readOf(givenFaceAtBottomPhoto());
        expectNear(@"face exclusion: the foot around a face given in it", given.foot, lifted(labOf(kTeal)), 0.005);
        HARNESS_CHECK(given.faceCount == 1 && fabs(given.largestFace - 0.12) < 1e-6);

        // A face over all of the foot leaves none of it outside: the whole foot, half teal and half red.
        givenFaces = @[box(0, 0.75, 1, 0.25)];
        SGRPhotoReading *covered = readOf(splitFootPhoto());
        CGFloat red[3] = {0.80, 0.15, 0.15};
        SGRLab teal = labOf(kTeal), redLab = labOf(red);
        SGRLab half = {(teal.L + redLab.L) / 2, (teal.a + redLab.a) / 2, (teal.b + redLab.b) / 2};
        expectNear(@"a face over the whole foot", covered.foot, lifted(half), 0.005);

        // A tiny face, a group of four (the largest, not their 25% together), and one half outside the photo (its part
        // in the photo): the largest face's share of the photo and the count.
        UIImage *grass = noFacePhoto();
        NSArray<NSArray *> *cases = @[
            @[@"a tiny face", @[box(0.42, 0.2, 0.15, 0.15)], @0.0225, @1],
            @[@"a group of four", @[box(0.0, 0.3, 0.25, 0.25), box(0.25, 0.3, 0.25, 0.25), box(0.5, 0.3, 0.25, 0.25), box(0.75, 0.3, 0.25, 0.25)], @0.0625, @4],
            @[@"a face 16% in all, 8% of it in the photo", @[box(0.3, 0.8, 0.4, 0.4)], @0.08, @1],
        ];
        NSUInteger mark = 1;
        for (NSArray *c in cases) {
            givenFaces = c[1];
            SGRPhotoReading *reading = readOf(variant(grass, mark++));
            if (fabs(reading.largestFace - [c[2] doubleValue]) > 1e-6 || reading.faceCount != [c[3] unsignedIntegerValue])
                HARNESS_FAIL(@"%@: largest face %.4f of %lu, not %@ of %@", c[0], reading.largestFace, (unsigned long)reading.faceCount, c[2], c[3]);
            // The foot is the grass whatever faces sit above it.
            expectNear(c[0], reading.foot, lifted(labOf(kGrass)), 0.005);
        }
        NSLog(@"[harness] PASS given faces: exclusion, the whole foot, tiny, a group, partly outside");

        // Vision itself. A face whose chin is on the bottom edge: found, the foot teal, not skin.
        givenFaces = nil;
        NSUInteger passes = visionPasses;
        UIImage *bottomFace = faceAtBottomPhoto();
        SGRPhotoReading *bottom = readOf(bottomFace);
        if (!detectedFaces.count) HARNESS_FAIL(@"Vision found no face on the bottom edge");
        HARNESS_CHECK(bottom.faceCount == detectedFaces.count && fabs(bottom.largestFace - largestDetected()) < 1e-9);
        // The same image again and the same picture in another image: no second Vision pass.
        HARNESS_CHECK(readOf(bottomFace) == bottom);
        HARNESS_CHECK(readOf(faceAtBottomPhoto()) == bottom);
        if (visionPasses != passes + 1) HARNESS_FAIL(@"%lu Vision passes for one picture read three times", (unsigned long)(visionPasses - passes));
        CGFloat bottomHue = hueOf(bottom.foot), skinHue = hueOf(labOf(kSkin));
        NSLog(@"[harness] real Vision, face at the bottom edge: %@, largest %.3f, foot L %.3f C %.3f h %.0f (teal C %.3f h %.0f, skin h %.0f)",
              detectedFaces, bottom.largestFace, bottom.foot.L, chromaOf(bottom.foot), bottomHue, chromaOf(teal), hueOf(teal), skinHue);
        if (hueDistance(bottomHue, hueOf(teal)) > 20 || chromaOf(bottom.foot) < 0.06)
            HARNESS_FAIL(@"face exclusion: the foot under a face on the bottom edge is hue %.0f C %.3f, not the teal's %.0f", bottomHue,
                         chromaOf(bottom.foot), hueOf(teal));
        // With Vision failing on the same picture nothing is left out: the face's skin is in the foot, which is further
        // from the teal than the foot with the face left out.
        visionFails = YES;
        SGRPhotoReading *failed = readOf(variant(bottomFace, 1));
        visionFails = NO;
        HARNESS_CHECK(failed && failed.faceCount == 0 && failed.largestFace == 0);
        CGFloat kept = SGRLabDistance(bottom.foot, lifted(teal)), whole = SGRLabDistance(failed.foot, lifted(teal));
        NSLog(@"[harness] the foot %.3f from the teal with the face left out, %.3f with Vision failing", kept, whole);
        if (kept + 0.02 > whole) HARNESS_FAIL(@"face exclusion: the foot is %.3f from the teal, %.3f without leaving the face out", kept, whole);

        SGRPhotoReading *large = readOf(largeFacePhoto());
        if (!detectedFaces.count) HARNESS_FAIL(@"Vision found no large centred face");
        HARNESS_CHECK(fabs(large.largestFace - largestDetected()) < 1e-9 && large.largestFace >= 0.10);
        NSLog(@"[harness] real Vision, large centred face: largest %.3f, foot L %.3f C %.3f h %.0f", large.largestFace, large.foot.L,
              chromaOf(large.foot), hueOf(large.foot));

        SGRPhotoReading *open = readOf(grass);
        HARNESS_CHECK(open.faceCount == 0 && open.largestFace == 0);
        expectNear(@"no face: the foot is the grass", open.foot, lifted(labOf(kGrass)), 0.005);

        SGRPhotoReading *dark = readOf(darkPhoto());
        if (dark.meanL >= 0.24) HARNESS_FAIL(@"the dark stage reads mean L %.3f, not under 0.24", dark.meanL);
        NSLog(@"[harness] dark stage: %lu faces, mean L %.3f, foot L %.3f C %.3f h %.0f", (unsigned long)dark.faceCount, dark.meanL,
              dark.foot.L, chromaOf(dark.foot), hueOf(dark.foot));

        // Nothing opaque: nil; narrower than 80 pt: not read at all.
        UIGraphicsImageRendererFormat *clear = [UIGraphicsImageRendererFormat preferredFormat];
        clear.opaque = NO;
        UIImage *transparent = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(200, 200) format:clear] imageWithActions:^(UIGraphicsImageRendererContext *c) {}];
        HARNESS_CHECK(readOf(transparent) == nil);
        UIImage *narrow = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(60, 60)] imageWithActions:^(UIGraphicsImageRendererContext *c) {}];
        HARNESS_CHECK(!SGRPhotoRead(narrow, ^(SGRPhotoReading *reading) { HARNESS_FAIL(@"a 60 pt photo was answered"); }));
        NSLog(@"[harness] PASS real Vision: bottom-edge face, large centred face, none, a dark stage; Vision failing; one pass per picture");

        // The page colour. The grass foot over a gray current colour: the grass's hue, held to L 0.44 (0.40).
        SGRLab gray = {0.35, 0.004, 0.004};
        SGRLab page = SGRPhotoPageLab(open, gray, NO);
        if (hueDistance(hueOf(page), hueOf(open.foot)) > 1 || fabs(page.L - MIN(open.foot.L, 0.44)) > 1e-6)
            HARNESS_FAIL(@"colour choice: the grass foot over gray gave L %.3f h %.0f", page.L, hueOf(page));
        HARNESS_CHECK(SGRPhotoPageLab(open, gray, YES).L <= 0.40 + 1e-9);
        // A current colour only 0.03 short of the foot's chroma keeps the page.
        SGRLab close = polar(0.35, chromaOf(open.foot) - 0.03, 300);
        page = SGRPhotoPageLab(open, close, NO);
        if (hueDistance(hueOf(page), 300) > 1) HARNESS_FAIL(@"colour choice: a foot 0.03 more chromatic took the page (h %.0f)", hueOf(page));
        // The skin and yellow band, and a foot under 0.06 of chroma, keep the current colour.
        SGRPhotoReading *gold = readOf(goldFootPhoto());
        CGFloat goldHue = hueOf(gold.foot);
        HARNESS_CHECK(goldHue >= 70 && goldHue <= 115 && chromaOf(gold.foot) >= 0.10);
        if (chromaOf(SGRPhotoPageLab(gold, gray, NO)) > 0.01) HARNESS_FAIL(@"colour choice: a golden foot (h %.0f) took the page", goldHue);
        SGRPhotoReading *muted = readOf(mutedFootPhoto());
        if (chromaOf(muted.foot) < 0.04 || chromaOf(muted.foot) >= 0.06) HARNESS_FAIL(@"the muted foot's chroma is %.3f", chromaOf(muted.foot));
        if (chromaOf(SGRPhotoPageLab(muted, (SGRLab){0.35, 0, 0}, NO)) > 1e-9)
            HARNESS_FAIL(@"colour choice: a foot of chroma %.3f took the page", chromaOf(muted.foot));
        // A very dark photo brings a lighter current colour down to its foot's lightness, hue kept; a lighter photo does not.
        SGRLab violet = polar(0.40, 0.12, 300);
        page = SGRPhotoPageLab(dark, violet, NO);
        if (fabs(page.L - dark.foot.L) > 1e-6 || hueDistance(hueOf(page), 300) > 0.5)
            HARNESS_FAIL(@"dark photo: page L %.3f h %.0f, not the foot's L %.3f at h 300", page.L, hueOf(page), dark.foot.L);
        if (fabs(SGRPhotoPageLab(open, violet, NO).L - 0.40) > 1e-6) HARNESS_FAIL(@"a photo that is not dark had its page colour darkened");
        // Into sRGB by chroma alone.
        CGFloat r, g, b;
        page = SGRPhotoPageLab(dark, polar(0.40, 0.30, 300), NO);
        SGRLabToRGB(page, &r, &g, &b);
        if (SGRLabDistance(SGRLabFromRGB(r, g, b), page) > 0.002 || hueDistance(hueOf(page), 300) > 0.5)
            HARNESS_FAIL(@"page colour off sRGB or its hue");
        NSLog(@"[harness] PASS colour choice: foot over gray, a close current colour kept, gold and muted feet, dark photo, caps, sRGB");
    }
    return 0;
}
