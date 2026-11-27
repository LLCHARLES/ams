// The artist's hero (Redesigned/Artist/ArtistHeader.x, compiled whole) on a page with its field (ArtistField.x), showing
// the photos of photo-fixtures.h. The first argument says what is checked:
//
//   on <photo> <dir>   (-spotifyglass.redesign.artist.adaptivePhoto YES) the photo read once, the page's field in the
//                      colour picked against the field's own palette colour for it, the photo filling the hero as it
//                      always does
//   off <photo> <dir>  the setting off: nothing read, no colour given to the field
//                      Both draw the page to <dir>/<photo>-<on|off>.png and the hero above its dissolve to
//                      <dir>/<photo>-<on|off>-photo.png, which photo-check.sh requires to be the same bytes on and off
//                      (and compares an off page with an earlier revision's)
//   swap               (on) a photo replaced by another while it is read: the first one's read and colour never reach
//                      the page
//   source             (on, with Apple Music's photo) Apple Music's photo arriving and the page's identity changing while
//                      it is read, so that the hero goes back to Spotify's: Apple's colour never reaches the page
//
// <photo> is faceAtBottom, largeFace, noFace or dark. Logs PASS or FAIL lines and exits 1 on the first failure
// (../harness-fail.h).
#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRField.h"
#import "Redesigned/Kit/SGRPalette.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "Shared/AnimatedArtwork/SGMotionCatalog.h"
#if __has_include("Redesigned/Kit/SGRCoverRead.h")
#import "Redesigned/Kit/SGRCoverRead.h"
#define PHOTO_READ 1
#endif
#import "../harness-fail.h"
#import "photo-fixtures.h"

// The classes the two files hook, which the harness never lays out but the page.
@interface _TtC32CreativeWorkPlatform_TemplateKit12TemplateView : UIView @end
@implementation _TtC32CreativeWorkPlatform_TemplateKit12TemplateView @end
@interface _TtC32CreativeWorkPlatform_TemplateKit28CreativeWorkTemplateListView : UIView @end
@implementation _TtC32CreativeWorkPlatform_TemplateKit28CreativeWorkTemplateListView @end
@interface _TtCOOOE16PodcastUI_ECMKitO19LegacyUI_ECMCoreKit10Components18TabsSectionHeading2UI7Private9TabButton : UIView @end
@implementation _TtCOOOE16PodcastUI_ECMKitO19LegacyUI_ECMCoreKit10Components18TabsSectionHeading2UI7Private9TabButton @end
@interface _TtC35CreativeWorkPlatform_ImageHeaderKit15ImageHeaderView : UIView @end
@implementation _TtC35CreativeWorkPlatform_ImageHeaderKit15ImageHeaderView @end
@interface _TtC12Element_List18CollectionViewCell : UICollectionViewCell @end
@implementation _TtC12Element_List18CollectionViewCell @end

@interface UIView (SGRArtistHero)
- (void)followArtwork:(UIImageView *)source;
- (void)updateAppleArtwork:(UIView *)header name:(NSString *)name;
@end

static const CGFloat kWidth = 402, kHeroHeight = 470, kPageHeight = 874, kShotScale = 3;
// The share of the hero's height the hero's dissolve into the page's colour covers, at its foot (ArtistHeader.x).
static const CGFloat kDissolveShare = 0.46;

#pragma mark - the boundaries

// Vision, counted, on the read's queue; the real detector answers. The first two passes wait for the harness to let
// them go while it holds them.
static NSUInteger visionPasses;
static dispatch_semaphore_t visionHolds[2];
static BOOL secondPassEntered;
#ifdef PHOTO_READ
BOOL SGRCoverReadTestSubjects(CGImageRef bitmap, SGRCoverVision vision, NSArray<NSValue *> **faces, NSArray<NSValue *> **objects) {
    NSUInteger pass = visionPasses++;
    if (pass == 1 && visionHolds[1])
        dispatch_async(dispatch_get_main_queue(), ^{ secondPassEntered = YES; });
    if (pass < 2 && visionHolds[pass]) dispatch_semaphore_wait(visionHolds[pass], DISPATCH_TIME_FOREVER);
    return vision(bitmap, faces, objects);
}
#endif

// The photo's watch: the last block the hero gave it, fired by the harness when the photo changes.
static void (^observed)(UIImageView *);
BOOL SGRObserveImage(UIImageView *view, void (^changed)(UIImageView *view)) {
    observed = changed;
    return YES;
}

// Apple Music's artist artwork: the request's completion, answered by the harness.
static void (^appleDone)(UIImage *, NSURL *, SGMotionArtistArtworkOutcome);
void SGMotionArtistArtwork(NSString *name, NSArray *titles, CGFloat pixels, BOOL photo, BOOL motion,
                          void (^done)(UIImage *, NSURL *, SGMotionArtistArtworkOutcome)) {
    appleDone = done;
}

#import "../harness-wait.h"

#pragma mark - the page

typedef struct {
    UIView *page, *hero;
    UIImageView *source;
} Page;

static Page makePage(UIImage *photo) {
    Page p;
    p.page = [[_TtC32CreativeWorkPlatform_TemplateKit12TemplateView alloc] initWithFrame:CGRectMake(0, 0, kWidth, kPageHeight)];
    p.page.accessibilityIdentifier = @"creator-page";
    [p.page layoutIfNeeded];
    HARNESS_CHECK([p.page.subviews.firstObject isKindOfClass:SGRArtworkField.class]);
    p.hero = [[NSClassFromString(@"SGRArtistHero") alloc] initWithFrame:CGRectMake(0, 0, kWidth, kHeroHeight)];
    HARNESS_CHECK(p.hero);
    [p.page addSubview:p.hero];
    p.source = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, kWidth, 424)];
    p.source.image = photo;
    [p.hero followArtwork:p.source];
    [p.hero layoutIfNeeded];
    return p;
}

static SGRArtworkField *fieldOf(Page p) {
    return (SGRArtworkField *)p.page.subviews.firstObject;
}

// The hero's own photo view: it sits in the hero's stretching content, not directly under the hero.
static UIImageView *pictureOf(Page p) {
    return [p.hero valueForKey:@"picture"];
}

static CGColorSpaceRef sRGB(void) {
    static CGColorSpaceRef space;
    if (!space) space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    return space;
}

// RGBA8 rows from the top, drawn by `draw` in points from the top left at `scale`.
static NSMutableData *pixels(size_t wide, size_t high, CGFloat scale, void (^draw)(CGContextRef c)) {
    NSMutableData *data = [NSMutableData dataWithLength:wide * high * 4];
    CGContextRef c = CGBitmapContextCreate(data.mutableBytes, wide, high, 8, wide * 4, sRGB(), (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGContextTranslateCTM(c, 0, high);
    CGContextScaleCTM(c, scale, -scale);
    UIGraphicsPushContext(c);
    draw(c);
    UIGraphicsPopContext();
    CGContextRelease(c);
    return data;
}

// `layer` from its top left, `size` points of it, drawn to a PNG at kShotScale.
static void writeLayer(CALayer *layer, CGSize size, NSString *path) {
    size_t wide = (size_t)(size.width * kShotScale), high = (size_t)(size.height * kShotScale);
    NSData *page = pixels(wide, high, kShotScale, ^(CGContextRef c) { [layer renderInContext:c]; });
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)page);
    CGImageRef image = CGImageCreate(wide, high, 8, 32, wide * 4, sRGB(), (CGBitmapInfo)kCGImageAlphaPremultipliedLast, provider, NULL, NO,
                                     kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    HARNESS_CHECK([UIImagePNGRepresentation([UIImage imageWithCGImage:image]) writeToFile:path atomically:YES]);
    CGImageRelease(image);
}

// The page to <dir>/<photo>-<state>.png, and the hero above its dissolve -- the photo and the scrim over its top, none
// of it in the page's colour -- to <dir>/<photo>-<state>-photo.png.
static void writeShots(Page p, const char *dir, const char *photo, NSString *state) {
    NSString *base = [@(dir) stringByAppendingPathComponent:[NSString stringWithFormat:@"%s-%@", photo, state]];
    writeLayer(p.page.layer, p.page.bounds.size, [base stringByAppendingString:@".png"]);
    CGFloat height = p.hero.bounds.size.height;
    writeLayer(p.hero.layer, CGSizeMake(p.hero.bounds.size.width, height - round(height * kDissolveShare)),
               [base stringByAppendingString:@"-photo.png"]);
}

static UIImage *fixtureNamed(NSString *name) {
    NSDictionary<NSString *, UIImage *(^)(void)> *all = @{
        @"faceAtBottom": ^{ return faceAtBottomPhoto(); },
        @"largeFace": ^{ return largeFacePhoto(); },
        @"noFace": ^{ return noFacePhoto(); },
        @"dark": ^{ return darkPhoto(); },
    };
    if (!all[name]) HARNESS_FAIL(@"no photo named %@", name);
    return all[name]();
}

#ifdef PHOTO_READ
#pragma mark - what the page should show

// SGRPalette's colour for the photo, as the page's field would take it without the read.
static UIColor *paletteColour(UIImage *photo) {
    __block UIColor *colour = nil;
    [SGRPalette paletteForImage:photo request:(SGRPaletteRequest){.mainColor = YES} completion:^(SGRPalette *palette) { colour = palette.fieldColor; }];
    HARNESS_AWAIT(colour != nil);
    return colour;
}

static SGRPhotoReading *readingOf(UIImage *photo) {
    __block SGRPhotoReading *reading = nil;
    HARNESS_CHECK(SGRPhotoRead(photo, ^(SGRPhotoReading *read) { reading = read; }));
    HARNESS_AWAIT(reading != nil);
    return reading;
}

static BOOL sameColour(UIColor *one, UIColor *other) {
    CGFloat a[4], b[4];
    [one getRed:&a[0] green:&a[1] blue:&a[2] alpha:&a[3]];
    [other getRed:&b[0] green:&b[1] blue:&b[2] alpha:&b[3]];
    for (int i = 0; i < 4; i++) {
        if (fabs(a[i] - b[i]) > 1e-4) return NO;
    }
    return YES;
}

// The page in the read photo's colour: the hero's reading the photo's, the field's palette colour SGRPalette's for the
// photo, and the field's colour the one picked from the two.
static void checkColour(Page p, UIImage *photo, NSString *name) {
    SGRPhotoReading *expected = readingOf(photo);
    UIColor *palette = paletteColour(photo);
    SGRPhotoReading *reading = [p.hero valueForKey:@"_photoReading"];
    if (reading.identity != expected.identity) HARNESS_FAIL(@"%@: the hero's reading is another picture's", name);
    if (!sameColour(fieldOf(p).paletteColor, palette)) HARNESS_FAIL(@"%@: the field's palette colour is not SGRPalette's for the photo", name);
    UIColor *picked = SGRPhotoPageColor(expected, palette);
    if (!sameColour(fieldOf(p).fieldColor, picked) || !sameColour(fieldOf(p).overrideColor, picked))
        HARNESS_FAIL(@"%@: the page is %@, not the colour picked, %@", name, fieldOf(p).fieldColor, picked);
}

static BOOL settled(Page p) {
    return fieldOf(p).overrideColor != nil;
}
#endif

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSString *mode = argc > 1 ? @(argv[1]) : @"";
        if ([mode isEqualToString:@"off"]) {
            HARNESS_CHECK(argc > 3);
            Page p = makePage(fixtureNamed(@(argv[2])));
            // The field's own colour from the photo, then time for anything else to land.
            HARNESS_AWAIT(![fieldOf(p).fieldColor isEqual:SGRNeutralField()]);
            HARNESS_CHECK(visionPasses == 0);
#ifdef PHOTO_READ
            HARNESS_CHECK(fieldOf(p).overrideColor == nil);
#endif
            writeShots(p, argv[3], argv[2], @"off");
            NSLog(@"[harness] PASS setting off (%s): nothing read, no colour given", argv[2]);
            return 0;
        }
#ifdef PHOTO_READ
        if ([mode isEqualToString:@"on"]) {
            HARNESS_CHECK(argc > 3);
            NSString *name = @(argv[2]);
            UIImage *photo = fixtureNamed(name);
            Page p = makePage(photo);
            HARNESS_AWAIT(settled(p));
            if (visionPasses != 1) HARNESS_FAIL(@"%@: %lu Vision passes, not 1", name, (unsigned long)visionPasses);
            if (!CGRectEqualToRect(pictureOf(p).frame, p.hero.bounds)) HARNESS_FAIL(@"%@: the photo does not fill the hero", name);
            checkColour(p, photo, name);
            writeShots(p, argv[3], argv[2], @"on");
            NSLog(@"[harness] PASS %@: one read, the page in the colour picked, the photo as it is drawn off", name);
            return 0;
        }
        if ([mode isEqualToString:@"swap"]) {
            UIImage *first = largeFacePhoto(), *second = noFacePhoto();
            NSMutableArray<UIColor *> *shown = [NSMutableArray array];
            [NSNotificationCenter.defaultCenter addObserverForName:SGRFieldColorDidChangeNotification object:nil queue:nil
                                                        usingBlock:^(NSNotification *note) { [shown addObject:note.userInfo[@"color"]]; }];
            // The first photo's read held in Vision until the second photo is shown; the second's held until the
            // first's has had time to land.
            visionHolds[0] = dispatch_semaphore_create(0);
            visionHolds[1] = dispatch_semaphore_create(0);
            Page p = makePage(first);
            p.source.image = second;
            observed(p.source);
            HARNESS_CHECK(pictureOf(p).image == second);
            dispatch_semaphore_signal(visionHolds[0]);
            // Both reads use the same serial queue: its first completion was
            // enqueued on main before the second pass announced entry there.
            HARNESS_AWAIT(secondPassEntered);
            if ([p.hero valueForKey:@"_photoReading"] || fieldOf(p).overrideColor)
                HARNESS_FAIL(@"stale completion: the replaced photo's read landed on the hero");
            dispatch_semaphore_signal(visionHolds[1]);
            HARNESS_AWAIT(settled(p));
            HARNESS_CHECK(pictureOf(p).image == second && visionPasses == 2);
            UIColor *firstColour = SGRPhotoPageColor(readingOf(first), paletteColour(first));
            for (UIColor *colour in shown) {
                if (sameColour(colour, firstColour)) HARNESS_FAIL(@"stale completion: the replaced photo's colour reached the page");
            }
            checkColour(p, second, @"swap");
            NSLog(@"[harness] PASS stale completion: the replaced photo's read and colour never reached the page");
            return 0;
        }
        if ([mode isEqualToString:@"source"]) {
            UIImage *spotify = noFacePhoto(), *apple = largeFacePhoto();
            UIColor *appleColour = SGRPhotoPageColor(readingOf(apple), paletteColour(apple));
            NSUInteger passes = visionPasses;
            NSMutableArray<UIColor *> *shown = [NSMutableArray array];
            [NSNotificationCenter.defaultCenter addObserverForName:SGRFieldColorDidChangeNotification object:nil queue:nil
                                                        usingBlock:^(NSNotification *note) { [shown addObject:note.userInfo[@"color"]]; }];
            Page p = makePage(spotify);
            UIView *header = [UIView new], *more = [UIView new];
            [p.page addSubview:header];
            [header addSubview:more];
            more.accessibilityIdentifier = @"Components.UI.ContextMenuButton-first";
            for (NSString *title in @[@"After Hours", @"Starboy"]) {
                UIView *row = [UIView new];
                row.accessibilityIdentifier = @"Components.UI.RetrievalRowElementUI_Loaded";
                UILabel *label = [UILabel new], *subtitle = [UILabel new];
                label.accessibilityIdentifier = @"EncoreConsumerMobile.View.Granular.Title";
                label.text = title;
                subtitle.accessibilityIdentifier = @"RetrievalRowElementUI.Subtitle.Label";
                subtitle.text = @"Album • 2020";
                [row addSubview:label];
                [row addSubview:subtitle];
                [p.page addSubview:row];
            }
            [p.hero updateAppleArtwork:header name:@"Fixture Artist"];
            if (!appleDone) HARNESS_FAIL(@"source: Apple Music's photo was never asked for");
            // Apple Music's photo lands, and before its read is in the page is another artist's: back to Spotify's photo.
            appleDone(apple, nil, SGMotionArtistArtworkFinished);
            HARNESS_CHECK(pictureOf(p).image == apple);
            more.accessibilityIdentifier = @"Components.UI.ContextMenuButton-second";
            [p.hero updateAppleArtwork:header name:@"Another Artist"];
            HARNESS_CHECK(pictureOf(p).image == spotify);
            HARNESS_AWAIT(settled(p));
            for (UIColor *colour in shown) {
                if (sameColour(colour, appleColour)) HARNESS_FAIL(@"source change: Apple Music's photo's colour reached the page");
            }
            checkColour(p, spotify, @"source");
            // Spotify's photo read once though shown twice; Apple's read before the harness asked (its own read).
            if (visionPasses != passes + 1) HARNESS_FAIL(@"source: %lu Vision passes for Spotify's photo shown twice", (unsigned long)(visionPasses - passes));
            NSLog(@"[harness] PASS source change: Apple Music's photo replaced mid read by Spotify's; only Spotify's reached the page");
            return 0;
        }
#endif
        HARNESS_FAIL(@"unknown mode %@", mode);
    }
}
