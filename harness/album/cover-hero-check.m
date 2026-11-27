// The album's hero (Redesigned/Album/AlbumHeader.x) on a page with its field (AlbumField.x), drawing covers from
// cover-fixtures.h. The first argument says what is checked:
//
//   on    (-spotifyglass.redesign.album.adaptiveCover YES) each cover drawn picture-aware: the page's field in the
//         cover's read colour, the cover itself shown down to where the spec lets it stop being sharp and drawn over
//         from there, the drawing's first row the cover's own, no jump from row to row below, the colour the page shows
//         under the hero along the bottom and no seam where the two meet (the field painted under the redesign's AMOLED
//         rule, SGRAmoled.x, as on the phone: a dark portrait's low grey goes black), and the title's area no lighter
//         than L 0.58 over 90% of it, scrim and all
//   dark-portrait  (the same) the last of those alone: Adele's 21 as the phone showed it (cover-check.sh's field-asked
//         mutant runs it)
//   swap  (the same) a cover replaced by another while it is read: the first one's colour never reaches the page and
//         its picture is never drawn
//   off   <png> the setting off: no drawn picture, and the hero as drawn written to <png> for cover-check.sh to compare
//         with an earlier revision's
//
// Logs PASS or FAIL lines and exits 1 on the first failure (../harness-fail.h).
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CommonCrypto/CommonDigest.h>
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "cover-seams.h"
#import "Redesigned/Kit/SGRField.h"
#import "Redesigned/Kit/SGRHeaderInfo.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "../harness-fail.h"
#import "cover-fixtures.h"

// All catalog answers and downloaded files belong to this run, not the Mac's Retrine cache.
NSURL *SGDataRoot(NSSearchPathDirectory directory) {
    return [NSURL fileURLWithPath:NSProcessInfo.processInfo.environment[@"SGR_COVER_ROOT"] isDirectory:YES];
}
#if __has_include("Redesigned/Kit/SGRCoverRead.h")
#import "Redesigned/Kit/SGRCoverRead.h"
#endif

@interface _TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView : UIView @end
@implementation _TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView @end
@interface _TtC32CreativeWorkPlatform_TemplateKit28CreativeWorkTemplateListView : UIView @end
@implementation _TtC32CreativeWorkPlatform_TemplateKit28CreativeWorkTemplateListView @end
@interface _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView : UIView @end
@implementation _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView @end
@interface _TtC12Element_List18CollectionViewCell : UICollectionViewCell @end
@implementation _TtC12Element_List18CollectionViewCell @end

static const CGFloat kWidth = 402, kHeroHeight = 430;

@interface UIView (SGRAlbumHero)
- (void)followCover:(UIImageView *)source;
- (void)playMotionForArtist:(NSString *)artist album:(NSString *)album;
@end

#import "../harness-wait.h"

typedef struct {
    UIView *page, *hero;
    UIImageView *source;
} Page;

// A page with its field, and the hero over its top following an image view the way the header's pass has it follow
// Spotify's cover.
static Page makePage(UIImage *cover) {
    Page p;
    p.page = [[_TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView alloc] initWithFrame:CGRectMake(0, 0, kWidth, 874)];
    p.page.accessibilityIdentifier = @"CreativeWorkPlatform.CreativeWorkTemplateView";
    [p.page layoutIfNeeded];
    HARNESS_CHECK([p.page.subviews.firstObject isKindOfClass:SGRArtworkField.class]);
    p.hero = [[NSClassFromString(@"SGRAlbumHero") alloc] initWithFrame:CGRectMake(0, 0, kWidth, kHeroHeight)];
    HARNESS_CHECK(p.hero);
    [p.page addSubview:p.hero];
    p.source = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 248, 248)];
    p.source.image = cover;
    [p.hero followCover:p.source];
    [p.hero layoutIfNeeded];
    return p;
}

static SGRArtworkField *fieldOf(Page p) {
    return (SGRArtworkField *)p.page.subviews.firstObject;
}

static CALayer *renderOf(UIView *hero) {
    UIView *content = [hero valueForKey:@"content"];
    for (CALayer *layer in content.layer.sublayers) {
        if ([layer.name isEqualToString:@"SGRAlbumHero.render"]) return layer;
    }
    return nil;
}

static CGColorSpaceRef sRGB(void) {
    static CGColorSpaceRef space;
    if (!space) space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    return space;
}

// RGBA8 rows from the top, `wide` x `high`, drawn by `draw` in points from the top left at `scale`.
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

static NSMutableData *pixelsOfImage(CGImageRef image) {
    size_t wide = CGImageGetWidth(image), high = CGImageGetHeight(image);
    NSMutableData *data = [NSMutableData dataWithLength:wide * high * 4];
    CGContextRef c = CGBitmapContextCreate(data.mutableBytes, wide, high, 8, wide * 4, sRGB(), (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(c, CGRectMake(0, 0, wide, high), image);
    CGContextRelease(c);
    return data;
}

// The most any channel of row `row` differs between the two.
static int rowDifference(NSData *one, NSData *other, size_t wide, size_t row) {
    const uint8_t *a = (const uint8_t *)one.bytes + row * wide * 4, *b = (const uint8_t *)other.bytes + row * wide * 4;
    int most = 0;
    for (size_t i = 0; i < wide * 4; i++) {
        if (i % 4 == 3) continue;
        most = MAX(most, abs((int)a[i] - (int)b[i]));
    }
    return most;
}

// The mean channel difference between two rows of the same picture.
static double rowStep(NSData *data, size_t wide, size_t row) {
    const uint8_t *a = (const uint8_t *)data.bytes + (row - 1) * wide * 4, *b = (const uint8_t *)data.bytes + row * wide * 4;
    double sum = 0;
    for (size_t i = 0; i < wide * 4; i++) {
        if (i % 4 != 3) sum += abs((int)a[i] - (int)b[i]);
    }
    return sum / (wide * 3);
}

// Linear sRGB luminance, independent of the renderer's OKLab implementation.
static double luminance(const uint8_t *rgb) {
    double c[3];
    for (int i = 0; i < 3; i++) {
        double v = rgb[i] / 255.0;
        c[i] = v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4);
    }
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}

static double luminanceStep(NSData *data, size_t wide, size_t row) {
    const uint8_t *a = (const uint8_t *)data.bytes + (row - 1) * wide * 4, *b = a + wide * 4;
    double step = 0;
    for (size_t x = 0; x < wide; x++) step += fabs(luminance(a + x * 4) - luminance(b + x * 4));
    return step / wide;
}

static UIColor *fieldColorOf(Page p) {
    return fieldOf(p).fieldColor;
}

// `colour` as a layer paints it here, the redesign's paint rules (SGRAmoled.x) applied as it is set.
static UIColor *paintedColour(UIColor *colour) {
    CALayer *layer = [CALayer layer];
    layer.backgroundColor = colour.CGColor;
    return [UIColor colorWithCGColor:layer.backgroundColor];
}

// A top-to-bottom gradient layer over the pixels, its colours between its stops straight, blended in sRGB.
static void compositeGradient(CAGradientLayer *layer, NSMutableData *data, size_t wide, size_t high, CGFloat scale) {
    NSArray *colors = layer.colors;
    NSArray<NSNumber *> *stops = layer.locations;
    if (!stops) {
        NSMutableArray *even = [NSMutableArray array];
        for (NSUInteger i = 0; i < colors.count; i++) [even addObject:@((CGFloat)i / MAX(1, colors.count - 1))];
        stops = even;
    }
    HARNESS_CHECK(colors.count >= 2 && stops.count == colors.count && layer.opacity == 1);
    CGRect frame = layer.frame;
    uint8_t *bytes = data.mutableBytes;
    for (size_t row = 0; row < high; row++) {
        CGFloat y = (row + 0.5) / scale;
        if (y < CGRectGetMinY(frame) || y >= CGRectGetMaxY(frame)) continue;
        CGFloat at = (y - CGRectGetMinY(frame)) / frame.size.height;
        NSUInteger next = 1;
        while (next < stops.count - 1 && stops[next].doubleValue < at) next++;
        CGFloat from = stops[next - 1].doubleValue, to = stops[next].doubleValue;
        CGFloat t = to > from ? MIN(MAX((at - from) / (to - from), 0), 1) : 1;
        const CGFloat *a = CGColorGetComponents((__bridge CGColorRef)colors[next - 1]), *b = CGColorGetComponents((__bridge CGColorRef)colors[next]);
        CGFloat colour[4];
        for (int c = 0; c < 4; c++) colour[c] = a[c] + (b[c] - a[c]) * t;
        uint8_t *pixel = bytes + row * wide * 4;
        for (size_t x = 0; x < wide; x++, pixel += 4) {
            for (int c = 0; c < 3; c++) pixel[c] = (uint8_t)lround(pixel[c] * (1 - colour[3]) + colour[c] * 255 * colour[3]);
        }
    }
}

#if __has_include("Redesigned/Kit/SGRCoverRead.h")
static SGRCoverReading *readingOf(UIImage *cover) {
    __block SGRCoverReading *final = nil;
    SGRCoverRead(cover, ^(SGRCoverReading *reading) {
        if (reading.final) final = reading;
    });
    HARNESS_AWAIT(final != nil);
    return final;
}

// Only the still test controls these boundaries. Normal hero checks continue through the real providers.
static BOOL stillTest(void) {
    return [NSProcessInfo.processInfo.arguments containsObject:@"still-swap"];
}
static NSMutableArray *posters, *stillReplies;
static BOOL holdStillReading;
static NSURL *clipFile;
static UIImage *redPoster;
static SGRCoverReading *redReading;
static NSMutableArray *headerRequests, *rowRequests;
static void (^headerResult)(NSURL *);
static void (^rowResult)(NSURL *);
#if !SGR_COVER_BASELINE
static void (^identifierResult)(NSURL *, SGMotionIdentifierOutcome);
static BOOL holdPageIdentifiers;
#endif
static NSURL *stillEditionFile;
static NSString *const fixtureURI = @"spotify:album:0000000000000000000021";

@interface SGAlbumQueuePage : NSObject @end
@implementation SGAlbumQueuePage
+ (NSString *)albumURI:(UIViewController *)controller { return controller.restorationIdentifier; }
@end

void SGRAlbumTestStillEditionCover(NSString *uri, NSString *artist, NSString *album, CGFloat pixels, void (^done)(NSURL *)) {
    HARNESS_CHECK([uri isEqual:fixtureURI] && [artist isEqual:@"Artist"] && [album isEqual:@"Fixture Album"]);
    done(stillEditionFile);
}

#if !SGR_COVER_BASELINE
void SGRAlbumTestIdentifierCover(NSString *uri, NSString *artist, NSString *album, CGFloat pixels, void (^done)(NSURL *, SGMotionIdentifierOutcome)) {
    HARNESS_CHECK([uri isEqual:fixtureURI] && [album isEqual:@"Fixture Album"]);
    if (!holdPageIdentifiers && [NSProcessInfo.processInfo.arguments containsObject:@"motion-verified"]) {
        SGMotionPageIdentifierCover(uri, artist, album, pixels, done);
        return;
    }
    identifierResult = [done copy];
}
#endif

@interface CoverReadyPlayerLayer : AVPlayerLayer @end
@implementation CoverReadyPlayerLayer
- (BOOL)isReadyForDisplay { return YES; }
@end

#if __has_include("Redesigned/Kit/SGRHeaderClip.h")
#import "Redesigned/Kit/SGRHeaderClip.h"
// This headless check owns adaptive colour delivery, not AVFoundation or a
// window. Deliver the clip's appearance event as if its first frame landed.
@interface CoverReadyClip : SGRHeaderClip
@property (nonatomic, copy) void (^ready)(BOOL, BOOL);
@end
@implementation CoverReadyClip
- (instancetype)initWithFile:(NSURL *)file appearance:(void (^)(BOOL, BOOL))appearance {
    if ((self = [super initWithFile:file appearance:appearance])) self.ready = appearance;
    return self;
}
- (void)updateVisible:(BOOL)visible active:(BOOL)active mayPlay:(BOOL)mayPlay {
    if (self.layer.opacity == 1) return;
    self.layer.opacity = 1;
    self.ready(YES, YES);
}
@end
Class SGRAlbumTestClipClass(void) { return stillTest() ? CoverReadyClip.class : SGRHeaderClip.class; }
#endif

AVPlayerLayer *SGRAlbumTestPlayerLayer(AVPlayer *player) {
    if (!stillTest()) return [AVPlayerLayer playerLayerWithPlayer:player];
    CoverReadyPlayerLayer *layer = [CoverReadyPlayerLayer layer];
    layer.player = player;
    return layer;
}

void SGRAlbumTestAlbumCover(NSString *artist, NSString *album, CGFloat pixels, void (^done)(NSURL *)) {
    if (headerRequests) { [headerRequests addObject:album]; headerResult = [done copy]; return; }
    if (!stillTest()) { SGMotionAlbumCover(artist, album, pixels, done); return; }
    HARNESS_CHECK([album isEqualToString:@"A"] || [album isEqualToString:@"B"]);
    done([album isEqualToString:@"A"] ? clipFile : nil);
}

static NSUInteger rowSearches;
void SGRAlbumTestPageCover(NSString *artist, NSString *album, NSString *uri, CGFloat pixels, void (^done)(NSURL *, BOOL)) {
#if !SGR_COVER_BASELINE
    if ([NSProcessInfo.processInfo.arguments containsObject:@"motion-verified"]) {
        SGMotionPageAlbumCover(artist, album, uri, pixels, done);
        return;
    }
#endif
    SGRAlbumTestAlbumCover(artist, album, pixels, ^(NSURL *file) { done(file, file != nil || [album isEqual:@"Known Still"]); });
}
void SGRAlbumTestRowMatcher(NSString *albumArtist, NSString *album, NSString *uri, CGFloat pixels, void (^ready)(BOOL (^)(NSString *, NSString *)), void (^done)(NSURL *)) {
    HARNESS_CHECK(rowRequests);
    rowSearches++;
    ready(^BOOL(NSString *artist, NSString *song) {
        [rowRequests addObject:@[artist, album, song]];
        if ([artist isEqual:@"현지화된 이름"] || [artist hasPrefix:@"Outgoing "]) return NO;
        rowResult = [done copy];
        return YES;
    });
}

@interface FixtureRetrievalListStructuredData : UIView @end
@implementation FixtureRetrievalListStructuredData @end
@interface _TtC32CreativeWorkPlatform_TemplateKitP33_5F894CA2C02A3F3767683E90D6AA015014CollectionView : UICollectionView @end
@implementation _TtC32CreativeWorkPlatform_TemplateKitP33_5F894CA2C02A3F3767683E90D6AA015014CollectionView @end
@interface _TtCC36CreativeWorkPlatform_RetrievalRowKit21RetrievalRowElementUI9TitleView : UIView @end
@implementation _TtCC36CreativeWorkPlatform_RetrievalRowKit21RetrievalRowElementUI9TitleView @end
@interface _TtCC36CreativeWorkPlatform_RetrievalRowKit21RetrievalRowElementUI12SubtitleView : UIView @end
@implementation _TtCC36CreativeWorkPlatform_RetrievalRowKit21RetrievalRowElementUI12SubtitleView @end
@interface MotionRows : NSObject <UICollectionViewDataSource> @end
@implementation MotionRows
- (NSInteger)collectionView:(UICollectionView *)list numberOfItemsInSection:(NSInteger)section { return 1; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)list cellForItemAtIndexPath:(NSIndexPath *)path {
    UICollectionViewCell *cell = [list dequeueReusableCellWithReuseIdentifier:@"track" forIndexPath:path];
    UIView *content = [FixtureRetrievalListStructuredData new], *row = [UIView new];
    [cell.contentView addSubview:content]; [content addSubview:row];
    row.accessibilityIdentifier = @"Components.UI.RetrievalRowElementUI_Loaded";
    for (NSArray *part in @[@[_TtCC36CreativeWorkPlatform_RetrievalRowKit21RetrievalRowElementUI9TitleView.class, @"Lose My Mind (feat. Doja Cat)"],
                            @[_TtCC36CreativeWorkPlatform_RetrievalRowKit21RetrievalRowElementUI12SubtitleView.class, @"Don Toliver 및 Doja Cat"]]) {
        UIView *wrapper = [part[0] new]; [row addSubview:wrapper];
        UILabel *label = [UILabel new]; label.text = part[1]; [wrapper addSubview:label];
    }
    return cell;
}
@end

static UICollectionViewCell *mountTrack(Page p, MotionRows *rows) {
    UIView *wrapper = [[_TtC32CreativeWorkPlatform_TemplateKit28CreativeWorkTemplateListView alloc] initWithFrame:p.page.bounds];
    [p.page addSubview:wrapper];
    UICollectionView *list = [[_TtC32CreativeWorkPlatform_TemplateKitP33_5F894CA2C02A3F3767683E90D6AA015014CollectionView alloc]
        initWithFrame:wrapper.bounds collectionViewLayout:[UICollectionViewFlowLayout new]];
    [wrapper addSubview:list];
    [list registerClass:_TtC12Element_List18CollectionViewCell.class forCellWithReuseIdentifier:@"track"];
    list.dataSource = rows;
    [list layoutIfNeeded];
    UICollectionViewCell *cell = list.visibleCells.firstObject;
    HARNESS_CHECK(cell);
    return cell;
}

#if !SGR_COVER_BASELINE
static void checkVerifiedEdition(void) {
    NSURL *folder = [SGDataRoot(NSCachesDirectory) URLByAppendingPathComponent:@"Motion"];
    HARNESS_CHECK([NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil]);
    NSString *address = @"https://fixture.invalid/edition-b.mp4";
    NSDictionary *answers = @{[@"album\nverified4\n" stringByAppendingString:fixtureURI]: @{@"url":address, @"at":NSDate.date},
                              @"album\n5\nartist\nfixture album": @{@"url":@"", @"identified":@YES, @"at":NSDate.date}};
    HARNESS_CHECK([answers writeToURL:[folder URLByAppendingPathComponent:@"album answers.plist"] atomically:YES]);
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    NSData *bytes = [address dataUsingEncoding:NSUTF8StringEncoding];
    CC_SHA1(bytes.bytes, (CC_LONG)bytes.length, digest);
    NSMutableString *name = [NSMutableString string];
    for (size_t i = 0; i < sizeof digest; i++) [name appendFormat:@"%02x", digest[i]];
    NSURL *local = [folder URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"mp4"]];
    HARNESS_CHECK([bytes writeToURL:local atomically:YES]);
    Page waiting = makePage(solidDarkCover());
    __attribute__((objc_precise_lifetime)) UIViewController *first = [UIViewController new];
    first.restorationIdentifier = fixtureURI;
    first.view = waiting.page;
    holdPageIdentifiers = YES;
    [waiting.hero playMotionForArtist:@"Artist" album:@"Fixture Album"];
    HARNESS_CHECK(identifierResult);
    holdPageIdentifiers = NO;
    Page p = makePage(solidDarkCover());
    __attribute__((objc_precise_lifetime)) UIViewController *owner = [UIViewController new];
    owner.restorationIdentifier = fixtureURI;
    owner.view = p.page;
    [p.hero playMotionForArtist:@"Artist" album:@"Fixture Album"];
    HARNESS_AWAIT([[p.hero valueForKeyPath:@"clip.file"] isEqual:local]);
    // Even a delayed miss from the first page cannot replace the now-known URI with a title.
    identifierResult(nil, SGMotionIdentifierMiss);
    HARNESS_AWAIT([[waiting.hero valueForKeyPath:@"clip.file"] isEqual:local]);
    puts("album motion: both the direct lookup and the delayed title fallback open verified edition B");
}

static void checkMotionIdentifiers(SGMotionIdentifierOutcome outcome, BOOL moves) {
    headerRequests = [NSMutableArray array]; rowRequests = [NSMutableArray array];
    identifierResult = nil; rowResult = nil; headerResult = nil;
    Page p = makePage(solidDarkCover());
    __attribute__((objc_precise_lifetime)) UIViewController *owner = [UIViewController new];
    owner.restorationIdentifier = fixtureURI;
    owner.view = p.page;
    __attribute__((objc_precise_lifetime)) MotionRows *rows = [MotionRows new];
    UICollectionViewCell *cell = mountTrack(p, rows);
    NSString *credit = moves ? @"IU" : @"현지화된 이름";
    UIView *row = cell.contentView.subviews.firstObject.subviews.firstObject;
    ((UILabel *)row.subviews.lastObject.subviews.firstObject).text = credit;
    [p.hero playMotionForArtist:@"Artist" album:@"Fixture Album"];
    // The identifiers are asked first; naming no release, they leave the album to the title and the rows.
    if (!identifierResult) HARNESS_FAIL(@"No identifier lookup before the title search");
    void (^firstIdentifiers)(NSURL *, SGMotionIdentifierOutcome) = identifierResult;
    identifierResult = nil;
    HARNESS_CHECK(!headerResult);
    NSURL *clip = [NSURL fileURLWithPath:@"/fixture-identifiers.mov"];
    stillEditionFile = moves ? clip : nil;
    firstIdentifiers(outcome == SGMotionIdentifierClip ? clip : nil, outcome);
    if (outcome != SGMotionIdentifierMiss) {
        NSURL *selected = [p.hero valueForKeyPath:@"clip.file"];
        HARNESS_CHECK(!headerResult && (moves ? [clip isEqual:selected] : !selected));
        NSLog(@"[harness] PASS identifier outcome %ld, motion %d", (long)outcome, moves);
        return;
    }
    HARNESS_CHECK(headerResult);
    headerResult(nil);
    [cell layoutSubviews]; [cell layoutIfNeeded];
    HARNESS_CHECK([rowRequests.lastObject[0] isEqual:credit] && (rowResult != nil) == moves);
    if (moves) rowResult(clip);
    NSURL *selected = [p.hero valueForKeyPath:@"clip.file"];
    HARNESS_CHECK(moves ? [clip isEqual:selected] : !selected);
}
#endif

static void checkMotionRow(void) {
    headerRequests = [NSMutableArray array]; rowRequests = [NSMutableArray array];
    __attribute__((objc_precise_lifetime)) MotionRows *rows = [MotionRows new];
    Page p = makePage(solidDarkCover()), other = makePage(solidDarkCover());
    NSString *f1 = @"F1 The Album";
    NSURL *file = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"fixture.mov"]];
    [p.hero playMotionForArtist:f1 album:f1];
    headerResult(nil);
    UICollectionViewCell *foreign = mountTrack(other, rows);
    [foreign layoutSubviews];
    HARNESS_CHECK(!rowRequests.count);
    UICollectionViewCell *cell = mountTrack(p, rows);
    [cell layoutSubviews];
    [cell layoutIfNeeded];
    HARNESS_CHECK(([rowRequests isEqual:@[@[@"Don Toliver, Doja Cat", f1, @"Lose My Mind (feat. Doja Cat)"]]]));
    rowResult(file);
    [p.hero playMotionForArtist:f1 album:f1]; [cell layoutSubviews];
    HARNESS_CHECK([[p.hero valueForKeyPath:@"clip.file"] isEqual:file] && rowRequests.count == 1);
    // A separate page whose list (including its one and only cell) settled before the header.
    Page first = makePage(solidDarkCover());
    cell = mountTrack(first, rows);
    UICollectionView *list = (id)cell.superview;
    UILabel *creditLabel = nil;
    UIView *row = cell.contentView.subviews.firstObject.subviews.firstObject;
    creditLabel = (id)row.subviews.lastObject.subviews.firstObject;
    __block BOOL committed = NO;
    [list performBatchUpdates:^{
        [first.hero playMotionForArtist:f1 album:f1]; headerResult(nil);
        [cell layoutSubviews]; // the index path is valid but this is still the prior batch's content
        HARNESS_CHECK(rowRequests.count == 1);
        creditLabel.text = @"현지화된 이름";
        [cell layoutSubviews];
        HARNESS_CHECK(rowRequests.count == 1);
    } completion:^(BOOL finished) { committed = YES; }];
    HARNESS_AWAIT(committed);
    [cell layoutSubviews]; [cell layoutIfNeeded];
    HARNESS_CHECK([rowRequests.lastObject[0] isEqual:@"현지화된 이름"]);
    creditLabel.text = @"Ed Sheeran";
    ((UILabel *)row.subviews.firstObject.subviews.firstObject).text = @"Drive";
    [cell layoutSubviews]; [cell layoutIfNeeded];
    HARNESS_CHECK(([rowRequests.lastObject isEqual:@[@"Ed Sheeran", f1, @"Drive"]]));
    HARNESS_CHECK(rowSearches == 2); // one for each missed header, not one per row
    [first.hero playMotionForArtist:@"Singer" album:@"Last"]; headerResult(nil);
    rowResult(file); // the F1 reply is now stale
    HARNESS_CHECK(![first.hero valueForKeyPath:@"clip.file"]);

    Page hits = makePage(solidDarkCover());
    cell = mountTrack(hits, rows);
    [hits.hero playMotionForArtist:@"A" album:@"Greatest Hits"]; headerResult(file);
    [cell layoutSubviews]; // A's header hit; its track list still belongs to this page
    NSUInteger searches = rowSearches;
    [hits.hero playMotionForArtist:@"B" album:@"Greatest Hits"]; headerResult(nil);
    [cell layoutSubviews]; [cell layoutIfNeeded];
    if (rowSearches != searches) rowResult(file); // the outgoing row would select A
    HARNESS_CHECK(![hits.hero valueForKeyPath:@"clip.file"] && rowSearches == searches);

    Page moved = makePage(solidDarkCover());
    [moved.page addSubview:cell.superview.superview]; // a new header with the outgoing track collection
    [moved.hero playMotionForArtist:f1 album:f1]; headerResult(nil);
    [cell layoutSubviews]; [cell layoutIfNeeded];
    HARNESS_CHECK(rowSearches == searches && ![moved.hero valueForKeyPath:@"clip.file"]);

    Page listFirst = makePage(solidDarkCover());
    cell = mountTrack(listFirst, rows);
    [cell layoutSubviews];
    [listFirst.hero playMotionForArtist:f1 album:f1]; headerResult(nil);
    [cell layoutSubviews]; [cell layoutIfNeeded]; rowResult(file);
    HARNESS_CHECK([[listFirst.hero valueForKeyPath:@"clip.file"] isEqual:file]);

    Page limit = makePage(solidDarkCover());
    cell = mountTrack(limit, rows);
    creditLabel = (id)cell.contentView.subviews.firstObject.subviews.firstObject.subviews.lastObject.subviews.firstObject;
    NSUInteger before = rowRequests.count;
    [limit.hero playMotionForArtist:f1 album:f1]; headerResult(nil);
    for (NSUInteger i = 0; i < 8; i++) {
        creditLabel.text = [NSString stringWithFormat:@"Outgoing %lu", (unsigned long)i];
        [cell layoutSubviews]; [cell layoutIfNeeded]; [cell layoutSubviews];
    }
    creditLabel.text = @"Ed Sheeran"; [cell layoutSubviews]; [cell layoutIfNeeded];
    HARNESS_CHECK(rowRequests.count == before + 8 && ![limit.hero valueForKeyPath:@"clip.file"]);
    searches = rowSearches;
    Page still = makePage(solidDarkCover());
    [still.hero playMotionForArtist:@"Artist" album:@"Known Still"]; headerResult(nil);
    cell = mountTrack(still, rows);
    [cell layoutSubviews]; [cell layoutIfNeeded];
    HARNESS_CHECK(![still.hero valueForKeyPath:@"clip.file"] && rowSearches == searches);
    puts("album motion: header hit, one owned row after miss, both arrival orders and stale reply passed");
}

void SGRAlbumTestPoster(NSURL *file, void (^done)(UIImage *)) {
    // Each real showMotion: asks for its clip's poster when adaptive cover is on.
    if (!stillTest()) { SGMotionPoster(file, done); return; }
    [posters addObject:[done copy]];
}

BOOL SGRAlbumTestStillRead(UIImage *image, void (^done)(SGRCoverReading *)) {
    if (!stillTest()) return SGRCoverRead(image, done);
    // A real reading of the red fixture, delivered now or held across an album change.
    SGRCoverReading *reading = redReading;
    void (^reply)(void) = ^{ done(reading); };
    if (holdStillReading) [stillReplies addObject:[reply copy]];
    else reply();
    return YES;
}

// Model address reuse without relying on malloc: discard only the address prefix, keep every other draw-key input.
@interface CoverReusedAddressCache : NSCache @end
@implementation CoverReusedAddressCache
- (id)reusedKey:(NSString *)key {
    if (![NSProcessInfo.processInfo.arguments containsObject:@"cache-reuse"]) return key;
    NSRange space = [key rangeOfString:@" "];
    HARNESS_CHECK(space.location != NSNotFound);
    return [key substringFromIndex:space.location];
}
- (id)objectForKey:(id)key { return [super objectForKey:[self reusedKey:key]]; }
- (void)setObject:(id)object forKey:(id)key cost:(NSUInteger)cost {
    [super setObject:object forKey:[self reusedKey:key] cost:cost];
}
@end

static NSCache *installedCache;
NSCache *SGRAlbumTestRenderCache(void) { return installedCache = [CoverReusedAddressCache new]; }

static BOOL fieldIsBlue(Page p) {
    CGFloat r, g, b, a;
    [fieldColorOf(p) getRed:&r green:&g blue:&b alpha:&a];
    return b > r + 0.15 && b > g + 0.15;
}

static BOOL fieldIsRed(Page p) {
    CGFloat r, g, b, a;
    [fieldColorOf(p) getRed:&r green:&g blue:&b alpha:&a];
    return r > b + 0.15 && r > g + 0.15;
}

static void startAlbumA(Page p) {
    [p.hero playMotionForArtist:@"Fixture" album:@"A"];
    HARNESS_CHECK(HarnessRunUntil(^BOOL {
        return ((CALayer *)[p.hero valueForKeyPath:@"clip.layer"]).opacity == 1;
    }));
}

static void startAlbumB(Page p) {
    p.source.image = flatSleeve(0.10, 0.20, 0.85, 0.6);
    [p.hero playMotionForArtist:@"Fixture" album:@"B"];
    if (!HarnessRunUntil(^BOOL { return fieldIsBlue(p); }))
        HARNESS_FAIL(@"still ownership: B without a clip did not receive its blue cover colour");
}

static id takeReply(NSMutableArray *pending) {
    HARNESS_CHECK(pending.count > 0);
    id reply = pending.firstObject;
    [pending removeObjectAtIndex:0];
    return reply;
}

static void checkStillOwnership(void) {
    clipFile = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"album-cover-test-A.mov"]];
    redPoster = solidRedCover();
    redReading = readingOf(redPoster);
    posters = [NSMutableArray new];
    stillReplies = [NSMutableArray new];
    // Already-installed A still must stop colouring the page when B has no replacement clip.
    Page p = makePage(solidDarkCover());
    startAlbumA(p);
    void (^poster)(UIImage *) = takeReply(posters);
    poster(redPoster);
    HARNESS_AWAIT(fieldIsRed(p));
    startAlbumB(p);

    // Each async boundary, first A -> B (no clip), then A -> B -> A with the very same URL object.
    // The latter distinguishes album ownership from URL identity.
    for (NSNumber *readStage in @[@NO, @YES]) {
        for (NSNumber *returnToA in @[@NO, @YES]) {
            [posters removeAllObjects];
            [stillReplies removeAllObjects];
            holdStillReading = readStage.boolValue;
            p = makePage(solidDarkCover());
            startAlbumA(p);
            poster = takeReply(posters);
            void (^oldReply)(void);
            if (holdStillReading) {
                poster(redPoster);
                oldReply = takeReply(stillReplies);
            } else {
                oldReply = ^{ poster(redPoster); };
            }
            startAlbumB(p);
            if (returnToA.boolValue) startAlbumA(p);
            oldReply();
            if (!fieldIsBlue(p))
                HARNESS_FAIL(@"still ownership: late %@ from A recoloured %@ red",
                             readStage.boolValue ? @"reading" : @"poster", returnToA.boolValue ? @"a later A lifetime" : @"B without a clip");
            if (returnToA.boolValue) {
                // The current request is still accepted; rejecting all stills would not pass.
                holdStillReading = NO;
                void (^current)(UIImage *) = takeReply(posters);
                current(redPoster);
                HARNESS_AWAIT(fieldIsRed(p));
            }
        }
    }
    NSLog(@"[harness] PASS still ownership: installed and late A stills cannot colour B without a clip; both async stages reject a prior A lifetime and accept the current one");
}

static void checkRenderCacheReuse(void) {
    UIImage *second = fixture(^(CGContextRef c, CGFloat side) {
        CGContextTranslateCTM(c, side, 0);
        CGContextScaleCTM(c, -1, 1);
        [colourfulCover() drawInRect:CGRectMake(0, 0, side, side)];
    });
    __weak UIImage *expired;
    Page p;
    @autoreleasepool {
        UIImage *first = colourfulCover();
        expired = first;
        p = makePage(first);
        (void)readingOf(first);
        HARNESS_AWAIT(renderOf(p.hero).contents != nil);
        // Same dimensions, page colour and geometry, different pixels at the sharp boundary.
        HARNESS_CHECK([readingOf(first).pageColor isEqual:readingOf(second).pageColor]);
        p.source.image = second;
    }
    (void)readingOf(second);
    HARNESS_AWAIT(!expired && renderOf(p.hero).contents != nil);
    NSData *drawn = pixelsOfImage((__bridge CGImageRef)renderOf(p.hero).contents);
    const uint8_t *corner = drawn.bytes;
    // The mirrored fixture starts blue (0.15, 0.20, 0.85), not the expired fixture's magenta.
    if (corner[0] > 80 || corner[1] > 80 || corner[2] < 180)
        HARNESS_FAIL(@"render cache reuse: new cover received expired magenta pixels %d,%d,%d", corner[0], corner[1], corner[2]);
    NSLog(@"[harness] PASS render cache reuse: expired source address and identical draw inputs cannot return its transition to a different cover");
}

// The hero's picture checked against the cover drawn where the hero lays it out, the top square of the hero.
static void checkCover(NSString *name, UIImage *cover, CGFloat sharpFrom, CGFloat sharpTo, CGFloat edgeFraction) {
    Page p = makePage(cover);
    SGRCoverReading *reading = readingOf(cover);
    // The field asked for the read colour; what it paints for it is measured off the page below.
    UIColor *page = reading.pageColor;
    if (!HarnessRunUntil(^BOOL { return renderOf(p.hero).contents && [fieldOf(p).overrideColor isEqual:page]; }))
        HARNESS_FAIL(@"%@: no picture drawn (%@) or the field not given the read colour (%@, read %@)", name,
                     renderOf(p.hero).contents ? @"drawn" : @"none", fieldOf(p).overrideColor, page);
    // The last of the pixel reading's and the final reading's pictures.
    HARNESS_AWAIT([(SGRCoverReading *)[p.hero valueForKey:@"coverReading"] final] &&
        [[installedCache objectForKey:[p.hero valueForKey:@"renderKey"]] valueForKey:@"image"] != nil &&
        renderOf(p.hero).contents == (__bridge id)[(UIImage *)[[installedCache objectForKey:[p.hero valueForKey:@"renderKey"]] valueForKey:@"image"] CGImage]);
    CALayer *render = renderOf(p.hero);
    CGImageRef drawn = (__bridge CGImageRef)render.contents;
    size_t wide = CGImageGetWidth(drawn);
    CGFloat scale = wide / kWidth, top = CGRectGetMinY(render.frame), side = MIN(kWidth, kHeroHeight);
    size_t high = (size_t)lround(kHeroHeight * scale), topRow = (size_t)lround(top * scale);
    if (fabs(CGRectGetMaxY(render.frame) - kHeroHeight) > 0.01 || CGImageGetHeight(drawn) != high - topRow)
        HARNESS_FAIL(@"%@: drawn %zux%zu over %@ of a %.0fx%.0f hero", name, wide, CGImageGetHeight(drawn), NSStringFromCGRect(render.frame), kWidth, kHeroHeight);
    // Above the drawing the hero shows the cover itself: the drawing begins where the spec lets the cover stop being sharp.
    if (top < sharpFrom * side - 0.5 || top > sharpTo * side + 0.5)
        HARNESS_FAIL(@"%@: the cover is drawn over from %.1fpt, not from %.1f to %.1f", name, top, sharpFrom * side, sharpTo * side);
    // The hero as it shows, from the top: the cover where the hero lays it out, the top square, then the drawing.
    NSMutableData *source = pixels(wide, high, scale, ^(CGContextRef c) {
        CGContextClipToRect(c, CGRectMake(0, 0, kWidth, side));
        [cover drawInRect:CGRectMake(0, 0, side, side)];
    });
    NSMutableData *shown = [source mutableCopy];
    NSData *drawing = pixelsOfImage(drawn);
    memcpy((uint8_t *)shown.mutableBytes + topRow * wide * 4, drawing.bytes, drawing.length);
    // At the drawing's top the cover's own pixels, and below no step from row to row of more than 10 levels on average,
    // and the page's colour along the bottom.
    if (rowDifference(shown, source, wide, topRow) > 2) HARNESS_FAIL(@"%@: the drawing's first row is not the cover's", name);
    double steepest = 0;
    for (size_t row = MAX(topRow, 1); row < high; row++) steepest = MAX(steepest, rowStep(shown, wide, row));
    // Opaque everywhere, so nothing under it (the system's extension of the cover, the field) shows through a gap, and
    // across the cover's bottom edge, kEdgeSpan either side of it, no step over kEdgeStep: no line where it ends.
    const uint8_t *drawnPixels = drawing.bytes;
    for (size_t i = 3; i < drawing.length; i += 4)
        if (drawnPixels[i] != 255) HARNESS_FAIL(@"%@: the drawing is not opaque at row %zu", name, topRow + i / 4 / wide);
    static const CGFloat kEdgeSpan = 24, kEdgeStep = 0.02;
    size_t edgeRow = (size_t)lround(side * scale), edgeFrom = MAX(topRow + 1, (size_t)lround((side - kEdgeSpan) * scale));
    double edgeSteepest = 0;
    for (size_t row = edgeFrom; row < MIN(high, edgeRow + (size_t)lround(kEdgeSpan * scale)); row++)
        edgeSteepest = MAX(edgeSteepest, luminanceStep(shown, wide, row));
    if (edgeSteepest > kEdgeStep) HARNESS_FAIL(@"%@: luminance step %.4f across the cover's bottom edge (limit 0.02)", name, edgeSteepest);
    // Measure the actual layer composition around the fixture's edge through the square's extension.
    // The scanned sleeve's hard edge is at 94%, not at the square's bottom; include its blurred lead-in too.
    // Other fixtures test the square bottom. The earlier title scrim is not a cover-edge discontinuity.
    NSData *composite = pixels(wide, high, scale, ^(CGContextRef c) { [p.hero.layer renderInContext:c]; });
    double compositeStep = 0;
    for (size_t row = MAX(topRow + 1, (size_t)lround((side * edgeFraction - kEdgeSpan) * scale)); row < high; row++)
        compositeStep = MAX(compositeStep, luminanceStep(composite, wide, row));
    if (compositeStep > kEdgeStep) HARNESS_FAIL(@"%@: composited edge luminance step %.4f (limit 0.02)", name, compositeStep);
    if (steepest > 10) HARNESS_FAIL(@"%@: a step of %.1f levels between rows under the sharp end", name, steepest);
    // The page under the hero's foot, its field painted as the redesign paints it: the drawing's bottom row is the colour
    // the field shows just under the hero, and the hero with its gradients over it meets that with no seam (on the phone
    // Adele's 21 ended in #0D0D0D on a #000000 page). The field alone is rendered: on the Mac a rendered gradient's
    // colours go through another colour space, so the hero's are composited below as Core Animation blends them.
    static const CGFloat kUnderHero = 4, kSeamLevels = 2;
    size_t under = (size_t)lround(kUnderHero * scale);
    NSData *onPage = pixels(wide, high + under, scale, ^(CGContextRef c) { [fieldOf(p).layer renderInContext:c]; });
    const uint8_t *field = (const uint8_t *)onPage.bytes + (high + under - 1) * wide * 4;
    const uint8_t *bottom = (const uint8_t *)shown.bytes + (high - 1) * wide * 4;
    for (size_t x = 0; x < wide; x += 7) {
        for (int c = 0; c < 3; c++) {
            if (abs(bottom[x * 4 + c] - field[x * 4 + c]) > kSeamLevels)
                HARNESS_FAIL(@"%@: the bottom row at %zu is %d,%d,%d, not the page's colour %d,%d,%d under it", name, x, bottom[x * 4],
                             bottom[x * 4 + 1], bottom[x * 4 + 2], field[x * 4], field[x * 4 + 1], field[x * 4 + 2]);
        }
    }
    // The title's area as the hero draws it: the picture with every gradient over it composited in sRGB as Core
    // Animation blends a layer's alpha (a snapshot on the Mac draws a gradient's colours through another colour space).
    size_t titleRow = (size_t)lround((kHeroHeight - SGRHeaderInfoTitleRise) * scale), count = 0, light = 0;
    for (CALayer *layer in p.hero.layer.sublayers) {
        if (![layer isKindOfClass:CAGradientLayer.class] || layer.hidden || layer.zPosition < renderOf(p.hero).zPosition) continue;
        compositeGradient((CAGradientLayer *)layer, shown, wide, high, scale);
    }
    double seam = 0;
    for (size_t x = 0; x < wide; x++) {
        for (int c = 0; c < 3; c++) seam += abs(bottom[x * 4 + c] - field[x * 4 + c]);
    }
    seam /= wide * 3;
    if (seam > kSeamLevels)
        HARNESS_FAIL(@"%@: a seam of %.1f levels where the hero meets the page under it (%d,%d,%d over %d,%d,%d mid-row)", name, seam,
                     bottom[wide / 2 * 4], bottom[wide / 2 * 4 + 1], bottom[wide / 2 * 4 + 2], field[wide / 2 * 4], field[wide / 2 * 4 + 1],
                     field[wide / 2 * 4 + 2]);
    for (size_t row = titleRow; row < high; row++) {
        const uint8_t *pixel = (const uint8_t *)shown.bytes + row * wide * 4;
        for (size_t x = 0; x < wide; x++, pixel += 4, count++) light += SGRLabFromRGB8(pixel).L > 0.58;
    }
    if (light > count / 10) HARNESS_FAIL(@"%@: %.0f%% of the title's area over L 0.58", name, 100.0 * light / count);
    NSLog(@"[harness] %@: sharp to %.1fpt (%.0f%%), row step %.1f/255; edge luminance step %.4f, composited %.4f (limit 0.02); "
          @"%.1f%% of title over L 0.58; page %d,%d,%d under the hero, seam %.1f/255",
          name, top, 100 * top / side, steepest, edgeSteepest, compositeStep, 100.0 * light / count, field[0], field[1], field[2], seam);
}

// Adele's 21 on the phone: a black-and-white portrait whose page colour, a low grey, the AMOLED rule paints black. The
// fixture is that case only if it reads such a grey and a layer shows it black.
static void checkDarkPortrait(void) {
    UIImage *portrait = darkPortraitCover();
    UIColor *read = readingOf(portrait).pageColor;
    CGFloat r, g, b, a;
    [read getRed:&r green:&g blue:&b alpha:&a];
    if (r <= 0.01 || r > 0.10 || fabs(r - g) > 0.01 || fabs(g - b) > 0.01)
        HARNESS_FAIL(@"dark portrait: read %.3f %.3f %.3f, not a low grey like Adele's 21 (#0D0C0C)", r, g, b);
    if (CGColorGetComponents(paintedColour(read).CGColor)[0] != 0)
        HARNESS_FAIL(@"dark portrait: a layer keeps the low grey; the AMOLED rule (SGRAmoled.x) is not in the build");
    checkCover(@"dark portrait", portrait, 0.60, 0.90, 1);
}
#endif

// Spotify's header rebuilt, through the page's own header pass (AlbumHeader.x's applyHeader): the cover element gone for
// one pass, then back with a replacement artwork view still under the lookup's 80pt on that pass. A picture landing in
// the retired view after either is not the hero's; the replacement's is once it has its size and its picture, on passes
// of its own that reach neither the header nor the page.
static void checkRebuiltUndersized(void) {
    UIView *page = [[_TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView alloc] initWithFrame:CGRectMake(0, 0, kWidth, 874)];
    page.accessibilityIdentifier = @"CreativeWorkPlatform.CreativeWorkTemplateView";
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kWidth, 486)];
    header.accessibilityIdentifier = @"CreativeWorkPlatform.Components.UI.CreativeWorkHeader";
    [page addSubview:header];
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 334, 300, 25)];
    title.text = @"Hurry Up Tomorrow";
    title.accessibilityIdentifier = @"CreativeWorkPlatform.Components.UI.TitleRow";
    [header addSubview:title];
    UIView *element = [[UIView alloc] initWithFrame:CGRectMake((kWidth - 248) / 2, 78, 248, 248)];
    element.accessibilityIdentifier = @"CreativeWorkPlatform.Components.UI.ArtWorkElement.WithCoverArt";
    [header addSubview:element];
    UIImageView *retired = [[UIImageView alloc] initWithFrame:element.bounds];
    retired.image = solidDarkCover();
    [element addSubview:retired];
    [page layoutIfNeeded];
    UIView *hero = nil;
    for (UIView *sub in header.subviews) {
        if ([NSStringFromClass(sub.class) isEqualToString:@"SGRAlbumHero"]) hero = sub;
    }
    HARNESS_CHECK(hero);
    UIImageView *picture = [hero valueForKey:@"picture"];
    HARNESS_CHECK(picture.image == retired.image);

    // The element gone for one of the header's passes.
    [element removeFromSuperview];
    [page setNeedsLayout];
    [page layoutIfNeeded];
    UIImage *shown = picture.image;
    retired.image = solidLightCover();
    if (picture.image != shown) HARNESS_FAIL(@"a picture landing in the artwork view of a cover element gone for a pass replaced the hero's");

    // Back, rebuilt, its artwork view undersized on the header's pass.
    [retired removeFromSuperview];
    [header addSubview:element];
    UIImageView *replacement = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 40, 40)];
    [element addSubview:replacement];
    [page setNeedsLayout];
    [page layoutIfNeeded];
    retired.image = solidRedCover();
    if (picture.image != shown) HARNESS_FAIL(@"a picture landing in the retired artwork view replaced the hero's");

    // Sized and filled on its own passes.
    replacement.frame = element.bounds;
    [replacement layoutIfNeeded];
    replacement.image = colourfulCover();
    if (picture.image != replacement.image)
        HARNESS_FAIL(@"the replacement artwork view, sized and filled after the header's pass, did not reach the hero");
    replacement.image = flatSleeve(0.10, 0.20, 0.85, 0.6);
    HARNESS_CHECK(picture.image == replacement.image);
    [page setNeedsLayout];
    [page layoutIfNeeded];
    HARNESS_CHECK(picture.image == replacement.image);
    NSLog(@"[harness] PASS rebuilt header: the retired artwork view's late pictures ignored, with the cover element gone for a "
          "pass and back undersized; the replacement followed once sized and filled on its own passes");
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSString *mode = argc > 1 ? @(argv[1]) : @"";
        if ([mode isEqual:@"rebuilt"]) {
            Page p = makePage(solidDarkCover());
            UIImageView *current = [[UIImageView alloc] initWithFrame:p.source.frame];
            current.image = colourfulCover();
            [p.hero followCover:current];
            UIImageView *picture = [p.hero valueForKey:@"picture"];
            HARNESS_CHECK(picture.image == current.image);
            current.image = solidRedCover();
            HARNESS_CHECK(picture.image == current.image);
            p.source.image = solidLightCover();
            if (picture.image != current.image) HARNESS_FAIL(@"Retired header cover replaced the hero");
            checkRebuiltUndersized();
            return 0;
        }
        if ([mode isEqualToString:@"off"]) {
            HARNESS_CHECK(argc > 2);
            Page p = makePage(colourfulCover());
            // The field's palette, and nothing else, landing.
            HARNESS_AWAIT(![fieldColorOf(p) isEqual:SGRNeutralField()]);
            HARNESS_CHECK(!renderOf(p.hero));
            size_t wide = (size_t)(kWidth * 2), high = (size_t)(kHeroHeight * 2);
            NSMutableData *hero = pixels(wide, high, 2, ^(CGContextRef c) { [p.hero.layer renderInContext:c]; });
            CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)hero);
            CGImageRef image = CGImageCreate(wide, high, 8, 32, wide * 4, sRGB(), (CGBitmapInfo)kCGImageAlphaPremultipliedLast, provider, NULL, NO,
                                             kCGRenderingIntentDefault);
            CGDataProviderRelease(provider);
            HARNESS_CHECK([UIImagePNGRepresentation([UIImage imageWithCGImage:image]) writeToFile:@(argv[2]) atomically:YES]);
            CGImageRelease(image);
            NSLog(@"[harness] PASS setting off: no picture drawn over the cover; the hero, in %@, written to %s", fieldColorOf(p), argv[2]);
            return 0;
        }
#if __has_include("Redesigned/Kit/SGRCoverRead.h")
        if ([mode isEqualToString:@"still-swap"]) { checkStillOwnership(); return 0; }
        if ([mode isEqualToString:@"motion-row"]) { checkMotionRow(); return 0; }
#if !SGR_COVER_BASELINE
        if ([mode isEqual:@"motion-verified"]) { checkVerifiedEdition(); return 0; }
        if ([mode isEqual:@"motion-identifiers"]) {
            checkMotionIdentifiers(SGMotionIdentifierMiss, NO);
            checkMotionIdentifiers(SGMotionIdentifierMiss, YES);
            checkMotionIdentifiers(SGMotionIdentifierClip, YES);
            checkMotionIdentifiers(SGMotionIdentifierUnavailable, NO);
            checkMotionIdentifiers(SGMotionIdentifierStill, NO);
            checkMotionIdentifiers(SGMotionIdentifierStill, YES);
            return 0;
        }
#endif
        if ([mode isEqualToString:@"cache-reuse"]) { checkRenderCacheReuse(); return 0; }
        if ([mode isEqualToString:@"on"]) {
            // Sharp from and to, as shares of the cover's side: any picture that is not solid between 60% and 90%; a
            // solid one from its art's bottom (80%) to 86%, and a solid dark one, mixed into its own colour, over the
            // last 120pt at most.
            checkCover(@"colourful", colourfulCover(), 0.60, 0.90, 1);
            checkCover(@"dark accent", darkAccentCover(), 0.60, 0.90, 1);
            // A hard pale edge 6% above the cover's bottom, under the sharp end where the blur has hardly begun.
            checkCover(@"scanned sleeve", scannedSleeveCover(), 0.60, 0.90, 0.94);
            checkCover(@"drawn face", faceCover(), 0.60, 0.90, 1);
            checkCover(@"solid light", solidLightCover(), 0.80, 0.86, 1);
            checkCover(@"solid red", solidRedCover(), 0.80, 0.86, 1);
            checkCover(@"solid dark", solidDarkCover(), 0.80, 0.86, 1);
            checkDarkPortrait();
            NSLog(@"[harness] PASS picture-aware hero: colourful, dark accent, a scanned sleeve, a drawn face, solid light, red and dark, "
                  @"a dark portrait");
            return 0;
        }
        if ([mode isEqualToString:@"dark-portrait"]) {
            checkDarkPortrait();
            NSLog(@"[harness] PASS picture-aware hero: a dark portrait");
            return 0;
        }
        if ([mode isEqualToString:@"swap"]) {
            UIImage *first = colourfulCover(), *second = solidRedCover();
            NSMutableArray<UIColor *> *shown = [NSMutableArray array];
            [NSNotificationCenter.defaultCenter addObserverForName:SGRFieldColorDidChangeNotification object:nil queue:nil
                                                        usingBlock:^(NSNotification *note) { [shown addObject:note.userInfo[@"color"]]; }];
            Page p = makePage(first);
            // Replaced before its read is back: the album changed.
            p.source.image = second;
            UIColor *secondColor = readingOf(second).pageColor;
            HARNESS_AWAIT(renderOf(p.hero).contents && [fieldOf(p).overrideColor isEqual:secondColor]);
            // Every read of the first cover back by now, pixel and final.
            UIColor *firstColor = readingOf(first).pageColor;
            for (UIColor *color in shown) {
                if ([color isEqual:firstColor]) HARNESS_FAIL(@"the replaced cover's colour %@ reached the page", firstColor);
            }
            // The picture drawn is the second cover's: its red border at the top left.
            NSMutableData *drawn = pixelsOfImage((__bridge CGImageRef)renderOf(p.hero).contents);
            const uint8_t *corner = drawn.bytes;
            if (corner[0] < 150 || corner[1] > 60 || corner[2] > 60) HARNESS_FAIL(@"the picture drawn is not the second cover's: %d,%d,%d", corner[0], corner[1], corner[2]);
            NSLog(@"[harness] PASS cover swapped mid read: %lu colours reached the page, none the replaced cover's; the picture is the new cover's",
                  (unsigned long)shown.count);
            return 0;
        }
#endif
        HARNESS_FAIL(@"no such check: %@", mode);
    }
}

// Before every %ctor, so the redesign's gate reads on.
__attribute__((constructor(101))) static void harnessDefaults(void) {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"spotifyglass.redesign"];
    // The picture-aware cover is the Full screen layout's, which an album no longer has unset.
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"spotifyglass.redesign.album.fullCover"];
}
