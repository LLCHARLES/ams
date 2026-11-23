// Artist redesign: the header the playlist and album pages have. The photo runs full bleed across the top
// of the page and dissolves into the page's color; the name and the monthly listeners are centered on the
// bottom of that dissolve; and under them one row -- shuffle, a white Play capsule, and Follow.
//
// Tree (trees/clean/artist/01.txt:37-170). The header is TemplateKit's HeaderContainer, 568pt, the first view
// of the page's stack, holding an element view that holds the ImageHeaderView:
//
//     UIView 402x424 clips                    the photo (Components.Header.UI.ArtworkImage) and a gradient
//     UIView {16, 334}                        the name, Encore.AdaptiveTitle, 45pt
//     ImageHeaderView.VerifiedBadge           "Verified by Spotify"
//     Components.Header.UI.Metadata           "58,4M monthly listeners"
//     UIStackView {4, 456} 394x48             explore, Follow (Curation.FollowButtonElementKit.FollowButton,
//                                             a text button), more, Components.UI.ShuffleButton, and
//                                             header-play-button
//     UIStackView {0, 504} 402x64             Components.UI.ArtistHeadline, "Pre-save the upcoming album"
//     HeaderForegroundView                    the 100pt navigation bar with the name, shown collapsed
//
// Scrolled (02.txt:26-30), the container keeps its 568pt and scrolls away with the page, while the element
// view slides down inside it and the ImageHeaderView shrinks to the 100pt bar, pinned at the top of the
// screen. So the photo and the redesign's text are the container's, not the ImageHeaderView's: in the header
// view they would be pinned at the top with it. The bar stays Spotify's, drawing the name once the page is
// scrolled, with its gradient masked out as the album's is.
//
// Everything else of the ImageHeaderView is drawn by nothing (an empty mask) and takes no touches: the badge,
// Explore, and the headline go with it -- the headline's pre-save is also the list's own Release Countdown
// section. The Kit's SGRHeaderInfo reads the name and the listeners off Spotify's concealed labels and draws
// and fires Spotify's shuffle, play and Follow, Follow as a glyph from the collection (ArtistFollow.x). More stays in Spotify's row, where the row needs it (ArtistField.x), and the Kit's pinned ⋯
// (SGRPinnedMore) draws and fires it from the top trailing corner of the page, level with the back button.
#import "Redesigned/Kit/SGRMotionBudget.h"
#ifndef SG_ARTIST_HEADER_ARTWORK_TEST
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRCoverRead.h"
#import "Redesigned/Kit/SGRHeroVeil.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Redesigned/Album/Album.h"
#import "Artist.h"
#import "ArtistArtwork.h"
#import "ArtistShuffleHold.h"

// A picture shorter than this is one mid load.
static const CGFloat kMinHero = 120;
// The collapsed ImageHeaderView, Spotify's navigation bar; the text fades out over the last kFade before it.
static const CGFloat kBar = 100, kFade = 150;

static char kInfoKey, kHeroKey, kHeroHeightKey, kContainerHeightKey, kRowWatchedKey, kSizeKey;
static char kTitleKey, kMetaKey, kShuffleKey, kPlayKey, kFollowKey, kArtworkKey, kBarKey, kMoreKey, kMoreButtonKey;
static char kPageHeaderKey;

@interface SGRArtistHeaderReference : NSObject
@property (nonatomic, weak) UIView *header;
@end
@implementation SGRArtistHeaderReference @end

#pragma mark - Spotify's views

static void setFrame(UIView *view, CGRect frame) {
    if (view && !CGRectIsEmpty(frame) && !CGRectEqualToRect(view.frame, frame)) view.frame = frame;
}

static char kLogoNameKey;

// Apple Music's logo for the artist in place of the name, where Apple Music has one. Asked once per name;
// the catalog remembers the answer for the launch.
static void showLogo(SGRHeaderInfo *info, NSString *name) {
    if (!name.length || !SGEnabled(SGRKeyArtistLogo) || [objc_getAssociatedObject(info, &kLogoNameKey) isEqualToString:name]) return;
    objc_setAssociatedObject(info, &kLogoNameKey, name, OBJC_ASSOCIATION_COPY_NONATOMIC);
    __weak SGRHeaderInfo *weakInfo = info;
    CGFloat pixels = UIScreen.mainScreen.bounds.size.width * UIScreen.mainScreen.scale;
    SGMotionArtistLogo(name, pixels, ^(UIImage *logo) {
        SGRHeaderInfo *shown = weakInfo;
        if (!shown || ![objc_getAssociatedObject(shown, &kLogoNameKey) isEqualToString:name]) return;
        [shown showTitleImage:logo];
        if (logo) SGLog(@"redesign artist: Apple Music's logo for %@", name);
    });
}

// The TemplateKit container the header sits in, which scrolls with the page.
static UIView *containerOf(UIView *header) {
    for (UIView *v = header.superview; v; v = v.superview) {
        if ([NSStringFromClass(v.class) containsString:@"HeaderContainer"]) return v;
    }
    return nil;
}

#pragma mark - the photo, full bleed

// The rest-sized photo and motion share the stretching surface and its bottom mask.
@interface SGRArtistHero : SGRStretchHero
@property (nonatomic, readonly) UIImageView *picture;
@property (nonatomic, copy) UIColor *fieldColor;
// The photo in Spotify's artwork view, and every photo it puts there afterward: the hero keeps itself
// right, rather than being handed a picture on each of the header's passes and staying empty between them.
// The same view again only re-reads it.
- (void)followArtwork:(UIImageView *)source;
- (void)updateAppleArtwork:(UIView *)header name:(NSString *)name;
// The scroll veil over the photo (Kit/SGRHeroVeil.h); nil while it is off.
@property (nonatomic, readonly) SGRHeroVeil *veil;
@end

static BOOL roundPlay(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ on = SGFlag(SGRKeyArtistRoundPlay, NO); });
    return on;
}

#pragma mark - the picture-aware photo

// The picture-aware photo (SGRKeyArtistAdaptivePhoto): the photo shown is drawn as it always is, and read once
// (Kit/SGRCoverRead.h, SGRPhotoRead) for the page's colour, which goes to the page's field in place of the palette's
// (SGRPhotoPageColor, against the field's own palette colour for the same photo) once both are in. Off, nothing is read.
static BOOL adaptivePhotoOn(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ on = SGFlag(SGRKeyArtistAdaptivePhoto, NO); });
    return on;
}

// ArtistField.x: the colour picked for the page, in place of the palette's (nil gives the palette's back), and the
// palette's colour for the photo the field was last given, nil until it has been read.
extern void SGRArtistSetPhotoColor(UIView *view, UIColor *color);
extern UIColor *SGRArtistPaletteColor(UIView *view);
#endif

@implementation SGRArtistHero
#ifndef SG_ARTIST_HEADER_ARTWORK_TEST
{
    __weak UIImageView *_artwork;
    UIImage *_applePhoto;
    NSString *_artistIdentity;
    SGRArtistArtworkRequest *_request;
    SGRArtistMotionView *_motion;
    // The picture-aware photo, on with its setting only; neither is used otherwise.
    BOOL _adaptive;
    UIImage *_photoImage;              // the photo read, or being read
    SGRPhotoReading *_photoReading;    // its reading, nil until it is in
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    self.clipsToBounds = YES;

    _picture = [[UIImageView alloc] initWithFrame:self.bounds];
    _picture.contentMode = UIViewContentModeScaleAspectFill;
    _picture.clipsToBounds = YES;
    _picture.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.content addSubview:_picture];
    _request = [SGRArtistArtworkRequest new];
    _motion = [[SGRArtistMotionView alloc] initWithFrame:self.bounds];
    _motion.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.content addSubview:_motion];
    if (SGRHeroScrollVeilOn()) {
        _veil = [[SGRHeroVeil alloc] initWithHero:self];
        _veil.stretchesItself = YES;
        _veil.art = @[_picture.layer, _motion.layer];
    }
    _adaptive = adaptivePhotoOn();
    self.fieldColor = SGRNeutralField();
    // The color is read off the main thread, so it can land after the last layout pass of the page.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sgr_fieldColorDidChange)
                                               name:SGRFieldColorDidChangeNotification object:nil];
    // The picture-aware colour waits on the field's palette for the same photo, which can land after the read.
    if (_adaptive)
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sgr_showPhotoColor)
                                                   name:SGRFieldPaletteDidChangeNotification object:nil];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)sgr_fieldColorDidChange {
    if (self.superview) self.fieldColor = SGRArtistFieldColor(self);
}

- (void)setFieldColor:(UIColor *)color {
    if (!color || [_fieldColor isEqual:color]) return;
    _fieldColor = [color copy];
    _veil.color = color;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.restBounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    // The photo and the clip are resized with the hero, which happened with the veil's placement on them: laid out
    // again without.
    [_veil artWillLayOut];
    _picture.frame = bounds;
    _motion.frame = bounds;
    [_veil artDidLayOut];
    [CATransaction commit];
}

- (void)followArtwork:(UIImageView *)source {
    if (!source) return;
    if (_artwork == source) {
        [self takeArtwork:source late:NO];
        return;
    }
    _artwork = source;
    [self takeArtwork:source late:NO];
    __weak SGRArtistHero *weakSelf = self;
    SGRObserveImage(source, ^(UIImageView *view) { [weakSelf takeArtwork:view late:YES]; });
}

// `late` is a photo that arrived after the header had laid out -- the artist opened for the first time,
// whose picture is still being fetched while the page is already on screen (issue #52). The log line says
// once that the watch, and not one of the header's passes, is what filled the hero.
- (void)takeArtwork:(UIImageView *)source late:(BOOL)late {
    if (_artwork && source != _artwork) return;
    UIImage *image = _applePhoto ?: source.image;
    if (!image || _picture.image == image) return;
    [self sgr_showPhoto:image];
    static BOOL logged;
    if (late && !logged) {
        logged = YES;
        SGLog(@"redesign artist: the photo landed after the header had laid out; the hero took it");
    }
}

// The photo shown, the page's field taking its colour from it, and read while the photo is picture-aware.
- (void)sgr_showPhoto:(UIImage *)image {
    _picture.image = image;
    if (image) SGRArtistSetArtwork(self, image);
    if (_adaptive) [self sgr_readPhoto:image];
}

// The photo read; until its reading and the field's palette colour for it are both in, the field shows the palette's
// colour, as it does for a photo that cannot be read. The reading is taken only while the hero still shows its photo.
- (void)sgr_readPhoto:(UIImage *)image {
    if (image == _photoImage) return;
    _photoImage = image;
    _photoReading = nil;
    SGRArtistSetPhotoColor(self, nil);
    __weak SGRArtistHero *weakSelf = self;
    SGRPhotoRead(image, ^(SGRPhotoReading *read) {
        SGRArtistHero *hero = weakSelf;
        if (!hero || hero->_picture.image != image) return;
        hero->_photoReading = read;
        [hero sgr_showPhotoColor];
    });
}

- (void)sgr_showPhotoColor {
    UIColor *palette = SGRArtistPaletteColor(self);
    if (_photoReading && palette) SGRArtistSetPhotoColor(self, SGRPhotoPageColor(_photoReading, palette));
}

#endif
- (void)updateAppleArtwork:(UIView *)header name:(NSString *)name {
    BOOL photo = SGHidden(SGRKeyArtistApplePhoto);
    BOOL motion = SGEnabled(SGRKeyArtistMotion) && SGMotionAppleMusicOn();
    if (!photo && !motion) return;
    UIView *more = SGRFindByIdentifier(header, @"Components.UI.ContextMenuButton*", &kMoreKey);
    NSString *identity = more.accessibilityIdentifier;
    // A generic identifier is not a page identity.
    if (![identity hasPrefix:@"Components.UI.ContextMenuButton-"]) identity = nil;
    if (!identity) return; // a transient missing button must not erase displayed artwork
    if (![_artistIdentity isEqual:identity]) {
        _artistIdentity = [identity copy];
        _applePhoto = nil;
        [_motion showFile:nil];
        [self sgr_showPhoto:_artwork.image];
    }
    static NSMutableSet<NSString *> *logged;
    NSString *gateKey = [NSString stringWithFormat:@"%@-%@", name, identity ?: @"missing-identity"];
    if (SGLogFirst(&logged, gateKey))
        SGLog(@"artist artwork: %@: identity=%@ photoSetting=%d motionSetting=%d AppleMusicSource=%d LowPowerOrHeat=%d ReduceMotion=%d autoplay=%d LowDataDownloads=%@",
            name, identity ?: @"missing; refuse", SGHidden(SGRKeyArtistApplePhoto), SGEnabled(SGRKeyArtistMotion),
            SGMotionAppleMusicOn(), SGRMotionHeldForPowerOrHeat(), SGRReduceMotion(),
            UIAccessibilityIsVideoAutoplayEnabled(), SGFlag(SGKeyMotionLowData, NO) ? @"allowed" : @"blocked on constrained networks");
    __weak SGRArtistHero *weakSelf = self;
    void (^apply)(UIImage *, NSURL *) = ^(UIImage *photo, NSURL *file) {
        SGRArtistHero *hero = weakSelf;
        if (!hero) return;
        hero->_applePhoto = photo;
        [hero takeArtwork:hero->_artwork late:NO];
        [hero->_motion showFile:file];
    };
    [_request applyPendingResultForIdentity:identity apply:apply];
    if (![_request needsReleaseEvidenceForIdentity:identity]) return;
    UIView *page = SGRArtistPageOf(header);
    NSArray<NSString *> *titles = SGRArtistReleaseTitles(page);
    __weak UIView *weakHeader = header, *weakPage = page;
    [_request updateIdentity:identity name:name titles:titles photo:photo
        motion:motion currentIdentity:^NSString *{
            if (!weakHeader || SGRArtistPageOf(weakHeader) != weakPage) return nil;
            NSString *live = SGRFindByIdentifier(weakHeader, @"Components.UI.ContextMenuButton*", &kMoreKey).accessibilityIdentifier;
            return [live hasPrefix:@"Components.UI.ContextMenuButton-"] ? live : nil;
        } apply:apply];
}

@end

#ifndef SG_ARTIST_HEADER_ARTWORK_TEST
// The picture from the top of the container down to `bottom`, which comes from the container at rest and only
// ever grows, so it does not change size while the page loads or scrolls.
static void applyHero(UIView *container, UIView *artwork, CGFloat bottom, UIColor *fieldColor) {
    SGRArtistHero *hero = objc_getAssociatedObject(container, &kHeroKey);
    if (!hero) {
        hero = [[SGRArtistHero alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(container, &kHeroKey, hero, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (hero.superview != container) [container insertSubview:hero atIndex:0];
    else if (container.subviews.firstObject != hero) [container sendSubviewToBack:hero];

    CGFloat height = [objc_getAssociatedObject(hero, &kHeroHeightKey) doubleValue];
    if (bottom > height + 0.5) {
        height = round(bottom);
        objc_setAssociatedObject(hero, &kHeroHeightKey, @(height), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGLog(@"redesign artist: hero %.0fpt across the top of the page", height);
    }
    if (height < kMinHero) return;
    hero.restHeight = height;
    [hero sgr_place];
    hero.fieldColor = fieldColor;
    [hero followArtwork:SGRHeaderArtworkIn(artwork)];
}

#pragma mark - the header's pass

static void applyHeader(UIView *header, BOOL full);
static void applyContent(UIView *header, UIView *container, SGRHeaderInfo *info, NSString *name, UIView *listeners, UIColor *fieldColor);

// Spotify's navigation bar, the one part of the header kept: collapsed, it is where the name is. Its gradient
// is a flat dark band over the field, as the album's was (Album/AlbumHeader.x); the soft top edge every
// redesigned page has keeps the name legible instead.
static UIView *keepBar(UIView *header) {
    UIView *foreground = nil;
    for (UIView *sub in header.subviews) {
        if ([NSStringFromClass(sub.class) containsString:@"HeaderForegroundView"]) foreground = sub;
    }
    if (foreground && !objc_getAssociatedObject(header, &kBarKey)) {
        SGForEachView(foreground, ^(UIView *v) {
            if ([NSStringFromClass(v.class) containsString:@"GradientView"] && !v.layer.mask) v.layer.mask = [CALayer layer];
        });
        objc_setAssociatedObject(header, &kBarKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return foreground;
}

// `full` NO is the header's own pass: a step of the collapse (its height changed, its width did not) then only
// moves and fades, unless the name or the listeners changed; any other pass and the row's take everything again.
static void applyHeader(UIView *header, BOOL full) {
    CGSize size = header.bounds.size;
    NSValue *last = objc_getAssociatedObject(header, &kSizeKey);
    if (!full) full = !last || last.CGSizeValue.width != size.width || last.CGSizeValue.height == size.height;
    UIView *container = containerOf(header);
    UIView *artwork = SGRFindByIdentifier(header, @"Components.Header.UI.ArtworkImage", &kArtworkKey);
    if (!container || !artwork || !SGRArtistPageOf(container)) return;
    UIView *page = SGRArtistPageOf(container);
    SGRArtistHeaderReference *reference = objc_getAssociatedObject(page, &kPageHeaderKey);
    if (!reference) {
        reference = [SGRArtistHeaderReference new];
        objc_setAssociatedObject(page, &kPageHeaderKey, reference, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    reference.header = header;
    objc_setAssociatedObject(header, &kSizeKey, [NSValue valueWithCGSize:size], OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIView *bar = keepBar(header);
    for (UIView *sub in header.subviews) {
        if (sub != bar) SGRBlankView(sub);
    }

    SGRHeaderInfo *info = objc_getAssociatedObject(container, &kInfoKey);
    if (!info) {
        info = [[SGRHeaderInfo alloc] initWithFrame:CGRectZero];
        // Follow's only state is its title in the app's language, so the glyph takes it from the collection.
        __weak UIView *weakPage = SGRArtistPageOf(container);
        __weak SGRHeaderInfo *weakInfo = info;
        __weak UIView *weakHeader = header;
        info.trailingState = ^BOOL(BOOL *on) {
            UIView *more = SGRFindByIdentifier(weakHeader, @"Components.UI.ContextMenuButton*", &kMoreKey);
            return SGRArtistFollowing(weakPage, more.accessibilityIdentifier, on, ^{ [weakInfo trailingStateChanged]; });
        };
        info.trailingOffSymbol = @"person.badge.plus";
        info.trailingOnSymbol = @"person.fill.checkmark";
        info.roundPlay = roundPlay();
        // The Music app's artist name on iOS 26: large and centered, on the bottom of the photo.
        info.largeTitle = YES;
        objc_setAssociatedObject(container, &kInfoKey, info, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (info.superview != container) [container addSubview:info];
    setFrame(info, container.bounds);

    UIView *title = SGRFindByIdentifier(header, @"Encore.AdaptiveTitle", &kTitleKey);
    UIView *listeners = SGRArtistListenersInAbout() ? nil : SGRFindByIdentifier(header, @"Components.Header.UI.Metadata", &kMetaKey);
    NSString *name = SGRFirstLabelText(title) ?: SGRFirstLabelText(bar);
    full |= [info showTitle:name creator:nil length:SGRFirstLabelText(listeners) about:nil];
    // Play's glyph and word are drawn in the field's color, which lands whenever the photo's has been read.
    UIColor *fieldColor = SGRArtistFieldColor(container);
    full |= ![fieldColor isEqual:info.handedPlayColor];
    // Until the buttons' row is found and watched, every pass looks for it: it can arrive after the last full one.
    full |= !info.rowFound;
    if (full) {
        info.handedPlayColor = fieldColor;
        applyContent(header, container, info, name, listeners, fieldColor);
    }

    // Collapsing, the text would pass over Spotify's bar with the name in it: it goes over the last kFade of
    // the collapse, from the header's own height, which this pass runs on every step of. More stays: it is
    // outside the header and has nothing to pass over.
    CGFloat alpha = MAX(0, MIN(1, (header.bounds.size.height - kBar) / kFade));
    if (fabs(info.alpha - alpha) > 0.01) info.alpha = alpha;

    // The picture reaches to where the content's top is at rest, plus the name. The container keeps its
    // height as the header collapses, and only ever grows as the page loads.
    CGFloat rest = [objc_getAssociatedObject(container, &kContainerHeightKey) doubleValue];
    UIScrollView *list = SGRStretchHeroScrollAbove(container);
    if (!list || list.contentOffset.y + list.adjustedContentInset.top >= 0) {
        rest = MAX(rest, container.bounds.size.height);
        objc_setAssociatedObject(container, &kContainerHeightKey, @(rest), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat bottom = rest - SGRHeaderInfoBottom - [info contentHeightForWidth:container.bounds.size.width] + SGRHeaderInfoTitleRise;
    applyHero(container, artwork, bottom, fieldColor);
    SGRArtistHero *hero = objc_getAssociatedObject(container, &kHeroKey);
    // The container scrolls with the page's scroll view, the hero and the info with it.
    SGRHeroVeil *veil = hero.veil;
    if (veil) {
        [info clipUnderTopBarFollowing:list];
        [veil followScroll:list];
        [veil update];
    }
    [hero updateAppleArtwork:header name:name];
}

// What the header shows besides its text: the logo, the buttons, More, and the watch on the buttons' row.
static void applyContent(UIView *header, UIView *container, SGRHeaderInfo *info, NSString *name, UIView *listeners, UIColor *fieldColor) {
    showLogo(info, name);

    UIView *shuffle = SGRFindByIdentifier(header, @"Components.UI.ShuffleButton", &kShuffleKey);
    UIView *play = SGRFindByIdentifier(header, @"header-play-button", &kPlayKey);
    UIView *follow = SGRFindByIdentifier(header, @"Curation.FollowButtonElementKit.FollowButton", &kFollowKey);
    [info showShuffle:shuffle play:play trailing:follow trailingFallback:nil playColor:fieldColor];

    // More, in the top trailing corner of the page itself rather than of the container, which scrolls away
    // with the photo: pinned there it is the same button in the same place on the album and the playlist,
    // and the page keeps it however far down the list one is (issue #57).
    UIView *more = SGRFindByIdentifier(header, @"Components.UI.ContextMenuButton*", &kMoreKey);
    artistBindHold(info, header, play, shuffle, more.accessibilityIdentifier);
    SGRPinnedMore(SGRArtistPageOf(container), &kMoreButtonKey, more);

    // The buttons arrive after the header has laid out, in a row that keeps its size and so lays nothing out
    // again (Native/Artist/Artist.x): the row's own pass is watched, a plain UIStackView.
    UIView *row = shuffle ?: play ?: follow;
    while (row && row.superview != header) row = row.superview;
    if (row && [row class] == UIStackView.class && !objc_getAssociatedObject(row, &kRowWatchedKey)) {
        objc_setAssociatedObject(row, &kRowWatchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak UIView *weakHeader = header;
        SGRObserveLayout(row, ^(UIView *view) {
            if (weakHeader) applyHeader(weakHeader, YES);
        });
    }
    if (row && objc_getAssociatedObject(row, &kRowWatchedKey)) info.rowFound = YES;

    static BOOL logged;
    if (!logged && header.window && name) {
        logged = YES;
        SGLog(@"redesign artist: own block \"%@\", \"%@\"; shuffle %@, play %@, follow %@, more %@", name,
              SGRFirstLabelText(listeners) ?: @"no listeners", shuffle ? @"found" : @"missing", play ? @"found" : @"missing",
              follow ? @"found" : @"missing", more ? @"found" : @"missing");
    }
}

// Scrolled, Spotify fades UIKit's navigation bar in over the artist page with an opaque black background
// (SPNavigationBar's _UIBarBackground, 116pt), where the album's own bar lets the page's field show through
// (issue #28). The page's item gets the same bar with no background, again whenever Spotify sets its own.
static void clearNavigationBar(UIView *header) {
    static char kClearKey;
    UIResponder *responder = header;
    while (responder && !([responder isKindOfClass:UIViewController.class]
                          && [((UIViewController *)responder).parentViewController isKindOfClass:UINavigationController.class]))
        responder = responder.nextResponder;
    UIViewController *page = (UIViewController *)responder;
    if (!page) return;
    UINavigationItem *item = page.navigationItem;
    UINavigationBarAppearance *clear = objc_getAssociatedObject(page, &kClearKey);
    if (clear && item.standardAppearance == clear && item.scrollEdgeAppearance == clear) return;
    if (!clear) {
        clear = [page.navigationController.navigationBar.standardAppearance copy] ?: [UINavigationBarAppearance new];
        [clear configureWithTransparentBackground];
        objc_setAssociatedObject(page, &kClearKey, clear, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    item.standardAppearance = clear;
    item.scrollEdgeAppearance = clear;
    item.compactAppearance = clear;
    item.compactScrollEdgeAppearance = clear;
}

%hook _TtC35CreativeWorkPlatform_ImageHeaderKit15ImageHeaderView
- (void)layoutSubviews {
    %orig;
    applyHeader((UIView *)self, NO);
    clearNavigationBar((UIView *)self);
}
%end

// Release rows can land after the header's last pass. Read their evidence then,
// rather than a timer which either guesses too early or keeps a page alive.
%hook _TtC12Element_List18CollectionViewCell
- (void)layoutSubviews {
    %orig;
    UIView *page = SGRArtistPageOf((UIView *)self);
    SGRArtistHeaderReference *reference = objc_getAssociatedObject(page, &kPageHeaderKey);
    UIView *header = reference.header;
    if (!header) return;
    UIView *container = containerOf(header);
    UIView *title = SGRFindByIdentifier(header, @"Encore.AdaptiveTitle", &kTitleKey);
    [(SGRArtistHero *)objc_getAssociatedObject(container, &kHeroKey) updateAppleArtwork:header name:SGRFirstLabelText(title)];
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC35CreativeWorkPlatform_ImageHeaderKit15ImageHeaderView"]);
}
#endif
