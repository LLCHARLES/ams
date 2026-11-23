#import "../album-notes/catalog-boundary.h"
#import "motion-view-stubs.h"
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Artist/Artist.h"
#import "Redesigned/Artist/ArtistArtwork.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/AnimatedArtwork/SGMotionCatalog.h"

static BOOL photoOn = YES, motionOn = YES;
static NSUInteger scanVisits;
static NSMutableArray *pending, *requestedTitles;
static char kMoreKey;
BOOL SGHidden(NSString *key) { return photoOn; }
BOOL SGEnabled(NSString *key) { return motionOn; }
BOOL SGFlag(NSString *key, BOOL fallback) { return fallback; }
BOOL SGMotionAppleMusicOn(void) { return YES; }
CGFloat SGMotionPixels(void) { return 720; }
BOOL SGRReduceMotion(void) { return NO; }
void SGRArtistSetArtwork(UIView *view, UIImage *image) {}
UIView *SGRArtistPageOf(UIView *view) {
    while (view.superview) view = view.superview;
    return view;
}
void SGForEachView(UIView *view, void (^visit)(UIView *)) {
    if (!view) return;
    scanVisits++;
    visit(view);
    for (UIView *child in view.subviews) SGForEachView(child, visit);
}
UIView *SGRFindByIdentifier(UIView *view, NSString *identifier, const void *key) {
    BOOL match = [identifier hasSuffix:@"*"] ?
        [view.accessibilityIdentifier hasPrefix:[identifier substringToIndex:identifier.length - 1]] :
        [view.accessibilityIdentifier isEqual:identifier];
    if (match) return view;
    for (UIView *child in view.subviews) {
        UIView *found = SGRFindByIdentifier(child, identifier, NULL);
        if (found) return found;
    }
    return nil;
}
NSString *SGRFirstLabelText(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) return ((UILabel *)view).text;
    for (UIView *child in view.subviews) {
        NSString *text = SGRFirstLabelText(child);
        if (text.length) return text;
    }
    return nil;
}
void SGMotionArtistArtwork(NSString *name, NSArray *titles, CGFloat pixels, BOOL photo, BOOL motion,
                          void (^done)(UIImage *, NSURL *, SGMotionArtistArtworkOutcome)) {
    [pending addObject:[done copy]];
    [requestedTitles addObject:[titles copy]];
}
@interface HeaderMotionBoundary : NSObject
@property (nonatomic, strong) NSURL *file;
- (void)showFile:(NSURL *)file;
@end
@implementation HeaderMotionBoundary
- (void)showFile:(NSURL *)file { self.file = file; }
@end
@interface SGRArtistHero : UIView {
@public
    UIImageView *_picture, *_artwork;
    UIImage *_applePhoto;
    NSString *_artistIdentity;
    SGRArtistArtworkRequest *_request;
    HeaderMotionBoundary *_motion;
}
- (void)updateAppleArtwork:(UIView *)header name:(NSString *)name;
@end
@interface SGRArtistHero (ImageBoundary)
- (void)takeArtwork:(UIImageView *)source late:(BOOL)late;
- (void)sgr_showPhoto:(UIImage *)image;
@end

// Compile the production orchestration method, not a second implementation of
// its identity/settings/request gates. Only image rendering is a test boundary.
#define SG_ARTIST_HEADER_ARTWORK_TEST 1
#import "../../tweak/Sources/Redesigned/Artist/ArtistHeader.x"

@implementation SGRArtistHero (ImageBoundary)
- (void)takeArtwork:(UIImageView *)source late:(BOOL)late { _picture.image = _applePhoto ?: source.image; }
- (void)sgr_showPhoto:(UIImage *)image { _picture.image = image; }
@end

static void release(UIView *page, NSString *title) {
    UIView *row = [UIView new];
    row.accessibilityIdentifier = @"Components.UI.RetrievalRowElementUI_Loaded";
    [page addSubview:row];
    UILabel *name = [UILabel new], *subtitle = [UILabel new];
    name.accessibilityIdentifier = @"EncoreConsumerMobile.View.Granular.Title";
    name.text = title;
    subtitle.accessibilityIdentifier = @"RetrievalRowElementUI.Subtitle.Label";
    subtitle.text = @"앨범 • 2020";
    [row addSubview:name];
    [row addSubview:subtitle];
}
static UIImage *picture(UIColor *color) {
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(1, 1)]
        imageWithActions:^(UIGraphicsImageRendererContext *context) { [color setFill]; UIRectFill(CGRectMake(0, 0, 1, 1)); }];
}
int main(void) {
    @autoreleasepool {
        pending = [NSMutableArray array];
        requestedTitles = [NSMutableArray array];
        UIView *page = [UIView new], *header = [UIView new], *more = [UIView new];
        [page addSubview:header]; [header addSubview:more];
        NSString *identity = @"Components.UI.ContextMenuButton-first";
        more.accessibilityIdentifier = identity;
        SGRArtistHero *hero = [SGRArtistHero new];
        hero->_request = [SGRArtistArtworkRequest new];
        hero->_picture = [UIImageView new];
        hero->_artwork = [UIImageView new];
        hero->_artwork.image = picture(UIColor.greenColor);
        hero->_motion = [HeaderMotionBoundary new];
        release(page, @"After Hours");
        [hero updateAppleArtwork:header name:@"The Weeknd"];
        CHECK(scanVisits > 0 && pending.count == 0);
        release(page, @"Starboy");
        [hero updateAppleArtwork:header name:@"The Weeknd"];
        CHECK(pending.count == 1);
        scanVisits = 0;
        UIImage *apple = picture(UIColor.redColor);
        NSURL *clip = [NSURL fileURLWithPath:@"/fixture/header.mp4"];
        more.accessibilityIdentifier = @"Components.UI.ContextMenuButton";
        [hero updateAppleArtwork:header name:@"The Weeknd"];
        ((void (^)(UIImage *, NSURL *, SGMotionArtistArtworkOutcome))pending[0])(apple, clip, SGMotionArtistArtworkFinished);
        CHECK(hero->_picture.image == hero->_artwork.image && hero->_motion.file == nil);
        more.accessibilityIdentifier = identity;
        [hero updateAppleArtwork:header name:@"The Weeknd"];
        CHECK(hero->_picture.image == apple && [hero->_motion.file isEqual:clip]);
        for (NSUInteger layout = 0; layout < 100; layout++) [hero updateAppleArtwork:header name:@"The Weeknd"];
        CHECK(scanVisits == 0 && pending.count == 1);

        photoOn = motionOn = NO;
        more.accessibilityIdentifier = @"Components.UI.ContextMenuButton-second";
        for (NSUInteger layout = 0; layout < 100; layout++) [hero updateAppleArtwork:header name:@"Another Artist"];
        CHECK(scanVisits == 0 && pending.count == 1);
        photoOn = motionOn = YES;
        [hero updateAppleArtwork:header name:@"Another Artist"];
        CHECK(scanVisits > 0 && pending.count == 2);
        CHECK(hero->_picture.image == hero->_artwork.image && hero->_motion.file == nil);
        release(page, @"Dawn FM");
        [hero updateAppleArtwork:header name:@"Another Artist"];
        CHECK(pending.count == 2); // evidence collected without a parallel request
        ((void (^)(UIImage *, NSURL *, SGMotionArtistArtworkOutcome))pending[1])(nil, nil, SGMotionArtistArtworkNeedsEvidence);
        // No further layout: NeedsEvidence must immediately use the rows which
        // arrived in flight, rather than waiting for another scroll.
        CHECK(pending.count == 3);
        CHECK([requestedTitles[2] containsObject:@"Dawn FM"]);
        ((void (^)(UIImage *, NSURL *, SGMotionArtistArtworkOutcome))pending[2])(nil, nil, SGMotionArtistArtworkFinished);
        scanVisits = 0;
        for (NSUInteger layout = 0; layout < 100; layout++) [hero updateAppleArtwork:header name:@"Another Artist"];
        CHECK(scanVisits == 0 && pending.count == 3);
        more.accessibilityIdentifier = @"Components.UI.ContextMenuButton-third";
        [hero updateAppleArtwork:header name:@"Third Artist"];
        more.accessibilityIdentifier = @"Components.UI.ContextMenuButton";
        ((void (^)(UIImage *, NSURL *, SGMotionArtistArtworkOutcome))pending[3])(apple, clip, SGMotionArtistArtworkFinished);
        more.accessibilityIdentifier = @"Components.UI.ContextMenuButton-fourth";
        [hero updateAppleArtwork:header name:@"Fourth Artist"];
        CHECK(hero->_picture.image == hero->_artwork.image && hero->_motion.file == nil);
        CHECK(pending.count == 5); // retained third-artist art must not land on the fourth page
        puts("artist header: result during missing identity delivered on restore without a new request or scan");
        puts("artist header: rows collected in flight trigger NeedsEvidence retry without another layout; off and finished do zero release traversal");
    }
    return 0;
}
