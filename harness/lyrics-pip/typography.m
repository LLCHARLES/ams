// Font storage is an external dependency; font matching, geometry, fitting and pixels are production.
#import "tests.h"
#import "Shared/LyricsPiP/LyricsPiPFrame.h"
#import "Shared/Fonts/Fonts.h"
#import "Shared/Fonts/FontLibrary.h"
#import <ImageIO/ImageIO.h>

SGAppFont SGAppFontChosen(void) { return [NSUserDefaults.standardUserDefaults integerForKey:SGKeyAppFont]; }
NSArray *SGAppFontFamilies(void) { return @[@"Georgia", @"Avenir Next"]; }
NSString *SGRegisteredCustomFont(void) { return @"Georgia"; }
int SGTestFontAsks;   // how many times the font page asked for the families, in pairs of library and imported
void SGRegisterCustomFontAsync(void) { SGTestFontAsks++; }
void SGFontLibraryRegisterInstalled(void) { SGTestFontAsks++; }
NSArray *SGFontLibrary(void) { return @[]; }
BOOL SGFontLibraryInstalled(NSString *identifier) { return NO; }
NSString *SGFontLibraryRegisteredFamily(NSString *identifier) { return nil; }
void SGFontLibraryRegisterAsync(NSString *identifier, void (^done)(NSString *family)) {}
SGLibraryFont *SGFontLibraryFont(NSString *identifier) { return nil; }

static NSString *fontName(SGLyricsPiPStyle *s, NSUInteger role) {
    CTFontRef font = SGLyricsPiPCreateFont(s, role, 32);
    NSString *name = CFBridgingRelease(CTFontCopyPostScriptName(font)); CFRelease(font);
    return name;
}
static NSData *render(NSArray *content, SGLyricsPiPStyle *s) {
    NSData *png = SGLyricsPiPStyledPNG(content, s, SGTestCover().CGImage);
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)png, NULL);
    CGImageRef image = source ? CGImageSourceCreateImageAtIndex(source, 0, NULL) : NULL;
    SGTestAssert(image && CGImageGetWidth(image) == s.raster.width && CGImageGetHeight(image) == s.raster.height,
        @"PNG dimensions equal the selected production raster");
    if (image) CGImageRelease(image);
    if (source) CFRelease(source);
    return png;
}
static void visibleRoles(NSArray *content, SGLyricsPiPStyle *style) {
    CGSize size = style.raster;
    NSMutableData *pixels = [NSMutableData dataWithLength:(NSUInteger)size.width * (NSUInteger)size.height * 4];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, size.width, size.height, 8, size.width * 4, space,
        kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    NSArray *rects = SGLyricsPiPFrameRects(content, style);
    for (NSUInteger i = 0; i < 7; i++) {
        memset(pixels.mutableBytes, 0, pixels.length);
        CGContextSaveGState(context);
        CGContextClipToRect(context, [rects[i] CGRectValue]);
        SGLyricsPiPDrawStyledFrame(context, content, style, NULL, NULL);
        CGContextRestoreGState(context);
        const uint8_t *p = pixels.bytes;
        NSUInteger bright = 0;
        for (NSUInteger b = 0; b < pixels.length; b += 4) if (p[b] > 100 && p[b + 1] > 100 && p[b + 2] > 100) bright++;
        SGTestAssert(bright > 0, [NSString stringWithFormat:@"layout %ld role %lu draws visible ink inside its actual box",
            (long)style.layout, (unsigned long)i]);
    }
    CGContextRelease(context);
}
void SGTestTypography(NSString *directory) {
    SGLyricsPiPStyle *s = SGLyricsPiPReadStyle();
    SGTestAssert(s.layout == 0 && s.info && s.alignment == 1 && CGSizeEqualToSize(s.raster, CGSizeMake(640, 640)),
        @"default is square, centered, with metadata");
    SGTestAssert([s.sizes isEqual:@[@40, @26, @26]] && [s.weights isEqual:@[@2, @0, @0]],
        @"default role sizes and weights preserve original hierarchy");
    NSArray *content = @[@"별빛을 따라 걸어요\n바람이 불어오는 밤",
        @"A new day is on its way", @"Sample lyrics · Retrine · Provider credit",
        @"Byeolbicheul ttara georeoyo\nBarami bureooneun bam",
        @"We walk beneath the stars\nOn a night carried by the wind",
        @"Sample song · Night walk", @"Sample artist · Retrine"];
    NSArray *sizes = @[[NSValue valueWithCGSize:CGSizeMake(640, 640)],
        [NSValue valueWithCGSize:CGSizeMake(800, 450)], [NSValue valueWithCGSize:CGSizeMake(480, 720)]];
    NSArray *names = @[@"sample-square", @"sample-landscape", @"sample-portrait"];
    for (NSInteger layout = 0; layout < 3; layout++) {
        s.layout = layout;
        SGTestAssert(CGSizeEqualToSize(s.raster, [sizes[layout] CGSizeValue]), @"aspect dimensions follow independent contract");
        NSArray *rects = SGLyricsPiPFrameRects(content, s);
        CGRect bounds = (CGRect){CGPointZero, s.raster};
        for (NSUInteger i = 0; i < rects.count; i++) {
            CGRect box = [rects[i] CGRectValue];
            SGTestAssert(CGRectContainsRect(bounds, box), @"each role stays within the production raster");
            for (NSUInteger j = 0; j < i; j++)
                SGTestAssert(!CGRectIntersectsRect(box, [rects[j] CGRectValue]), @"roles and cover never overlap");
            if (i < 7) {
                SGLyricsPiPTextFit fit = SGLyricsPiPFitRole(content[i], box.size, s, i);
                SGTestAssert(fit.lines > 0, @"every visible role has at least one rendered line");
            }
        }
        SGTestAssert(CGRectGetMinY([rects[0] CGRectValue]) > CGRectGetMinY([rects[3] CGRectValue]) &&
            CGRectGetMinY([rects[3] CGRectValue]) > CGRectGetMinY([rects[4] CGRectValue]) &&
            CGRectGetMinY([rects[4] CGRectValue]) > CGRectGetMinY([rects[1] CGRectValue]),
            @"original, pronunciation, translation, next appear in order");
        visibleRoles(content, s);
        NSData *png = render(content, s);
        NSString *path = [directory stringByAppendingPathComponent:[names[layout] stringByAppendingString:@".png"]];
        SGTestAssert([png writeToFile:path atomically:YES], @"actual renderer sample PNG saved");
        printf("  frame: %s\n", path.UTF8String);
        s.info = NO;
        NSArray *hidden = SGLyricsPiPFrameRects(content, s);
        SGTestAssert(CGRectIsEmpty([hidden[7] CGRectValue]) && CGRectIsEmpty([hidden[5] CGRectValue]) &&
            CGRectIsEmpty([hidden[6] CGRectValue]), @"hiding info removes all cover and metadata boxes");
        CGRect a = [hidden[0] CGRectValue], b = [rects[0] CGRectValue];
        SGTestAssert(a.size.width * a.size.height > b.size.width * b.size.height, @"hidden info gives space back to lyrics");
        s.info = YES;
    }
    s.layout = 0;
    NSArray *emptySupplements = @[content[0], content[1], content[2], @"", @"", content[5], content[6]];
    NSArray *emptyRects = SGLyricsPiPFrameRects(emptySupplements, s);
    SGTestAssert(CGRectIsEmpty([emptyRects[3] CGRectValue]) && CGRectIsEmpty([emptyRects[4] CGRectValue]),
        @"absent supplements consume no layout space");

    NSData *center = render(content, s);
    s.alignment = 0; NSData *left = render(content, s);
    s.alignment = 2; NSData *right = render(content, s);
    SGTestAssert(![center isEqual:left] && ![left isEqual:right], @"alignment choices change production pixels");
    s.alignment = 1;
    s.font = @"system"; NSString *system = fontName(s, 0);
    NSData *systemPNG = render(content, s);
    s.font = @"Georgia";
    SGTestAssert(![fontName(s, 0) isEqual:system] && ![render(content, s) isEqual:systemPNG],
        @"PiP family changes actual Core Text font and pixels");
    NSString *bold = fontName(s, 0);
    s.weights = @[@0, @0, @0];
    SGTestAssert(![fontName(s, 0) isEqual:bold], @"role weight selects a different real face");
    s.font = @"a missing family";
    SGTestAssert([fontName(s, 0) isEqual:fontName(({ SGLyricsPiPStyle *v = SGLyricsPiPReadStyle(); v.font = @"system"; v.weights = @[@0,@0,@0]; v; }), 0)],
        @"unavailable family falls back to system");
    s.font = @"system"; s.sizes = @[@64, @48, @48];
    NSString *longText = [@[@"這是一段很長的翻譯，文字必須換行並且留在自己的範圍內。", @"日本語の歌詞と翻訳を複数行で表示します。",
        @"긴 번역도 원문과 발음 아래에 읽기 쉽게 표시합니다.", @"هذه ترجمة طويلة متعددة الأسطر لا تتداخل مع النص الأصلي.",
        @"Long sample translation, with explicit wrapping and an honest ellipsis when the available space is exhausted."]
        componentsJoinedByString:@"\n"];
    NSMutableArray *longContent = [content mutableCopy]; longContent[4] = longText;
    for (NSInteger layout = 0; layout < 3; layout++) {
        s.layout = layout;
        NSArray *rects = SGLyricsPiPFrameRects(longContent, s);
        SGLyricsPiPTextFit fit = SGLyricsPiPFitRole(longText, [rects[4] CGRectValue].size, s, 4);
        visibleRoles(longContent, s);
        SGTestAssert(fit.lines > 0 && fit.size >= 16 && fit.size <= 48,
            @"largest long CJK/multiline/RTL supplement fits within bounded sizes");
        NSMutableArray *overflow = [NSMutableArray array];
        for (NSUInteger i = 0; i < 50; i++) [overflow addObject:@"A sample line"];
        SGLyricsPiPTextFit cut = SGLyricsPiPFitRole([overflow componentsJoinedByString:@"\n"],
            [rects[4] CGRectValue].size, s, 4);
        SGTestAssert(cut.lines > 0 && cut.lines < 50 && cut.truncated,
            @"content that cannot fit is explicitly ellipsized, never silently omitted");
        NSData *png = render(longContent, s);
        NSString *path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"sample-largest-%ld.png", (long)layout]];
        SGTestAssert([png writeToFile:path atomically:YES], @"largest-size stress sample saved");
        printf("  frame: %s\n", path.UTF8String);
    }
    SGTestSetting(SGLyricsPiPRoleKey(0, @"size"), @1000);
    SGTestSetting(SGLyricsPiPRoleKey(1, @"size"), @-1);
    SGTestSetting(SGLyricsPiPRoleKey(2, @"weight"), @99);
    SGTestAssert(SGLyricsPiPReadStyle().sizes[0].doubleValue == 64 &&
        SGLyricsPiPReadStyle().sizes[1].doubleValue == 16 && SGLyricsPiPReadStyle().weights[2].integerValue == 3,
        @"malformed preferences are normalized to bounded role ranges");
    SGTestSetting(SGLyricsPiPRoleKey(0, @"size"), nil);
    SGTestSetting(SGLyricsPiPRoleKey(1, @"size"), nil);
    SGTestSetting(SGLyricsPiPRoleKey(2, @"weight"), nil);
    SGTestSetting(SGKeyPiPFont, @"custom");
    SGTestAssert([SGLyricsPiPReadStyle().font isEqual:@"Georgia"], @"imported choice reuses existing registration");
    SGTestSetting(SGKeyPiPFont, nil);
}

void SGTestRTLEllipsis(NSString *directory) {
    SGLyricsPiPStyle *s = SGLyricsPiPReadStyle();
    s.layout = 1; s.info = YES; s.font = @"system"; s.sizes = @[@40, @26, @16];
    NSString *arabic = @"هذه ترجمة طويلة متعددة الأسطر لا تتداخل مع النص الأصلي.";
    NSString *prefix = @"First sample line\nSecond sample line\nThird sample line\n";
    NSMutableArray *actual = [@[@"Sample original", @"Sample next", @"Sample credit", @"Sample pronunciation",
        [prefix stringByAppendingFormat:@"%@\nA fifth line that cannot fit", arabic], @"Sample song", @"Sample artist"] mutableCopy];
    NSMutableArray *explicitToken = [actual mutableCopy], *noToken = [actual mutableCopy];
    explicitToken[4] = [prefix stringByAppendingFormat:@"%@…", arabic];
    noToken[4] = [prefix stringByAppendingString:arabic];
    for (NSInteger alignment = 0; alignment < 3; alignment++) {
        s.alignment = alignment;
        CGRect box = [SGLyricsPiPFrameRects(actual, s)[4] CGRectValue];
        SGLyricsPiPTextFit cut = SGLyricsPiPFitRole(actual[4], box.size, s, 4);
        SGLyricsPiPTextFit full = SGLyricsPiPFitRole(explicitToken[4], box.size, s, 4);
        SGTestAssert(cut.truncated && cut.lines == 4 && !full.truncated && full.lines == 4,
            @"RTL fixture uses truncation versus an independently explicit four-line ellipsis");
        NSData *rendered = SGLyricsPiPStyledPNG(actual, s, NULL);
        NSData *expected = SGLyricsPiPStyledPNG(explicitToken, s, NULL);
        NSData *absent = SGLyricsPiPStyledPNG(noToken, s, NULL);
        SGTestAssert([rendered isEqual:expected], @"truncated RTL pixels exactly match a fully drawn literal ellipsis");
        SGTestAssert(![rendered isEqual:absent], @"RTL truncation token changes visible pixels, not only the fit flag");
        if (directory) {
            NSString *path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"sample-rtl-ellipsis-%ld.png", (long)alignment]];
            SGTestAssert([rendered writeToFile:path atomically:YES], @"RTL ellipsis pixel-regression artifact saved");
        }
    }
}
