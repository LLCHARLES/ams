// Artist: hides parts of the artist page, one switch each in Mod Settings > Home & Library > Artist.
//
// Trees (trees/continuous/*.txt): the page is a CreativeWorkPlatform TemplateView with the
// identifier creator-page. Its header is an ImageHeaderView whose badge, listeners and buttons carry
// accessibility identifiers. Below the Music/Video tabs every row is an Element_List cell: a titled
// section is one cell for its heading (SectionHeadingHome), then its tracks, carousel or card, then
// a 16pt spacer, each a cell of its own.
//
// Only the heading names the section, so the list remembers the heading above every cell it sizes
// and a hidden section's cells all answer height 0, down to the next heading. The headings are
// told apart by their English titles.
#import <objc/runtime.h>
#import "Core/SGImageContext.h"
#import "Core/SGCore.h"
#import "Artist.h"
#import "Native/Declutter/Declutter.h"

static BOOL onArtistPage(UIView *view) {
    for (UIView *v = view.superview; v; v = v.superview) {
        if ([v.accessibilityIdentifier isEqualToString:@"creator-page"]) return YES;
    }
    return NO;
}

#pragma mark - header

static const struct { __unsafe_unretained NSString *ident, *key; } buttons[] = {
    {@"Components.UI.WatchFeedEntityExplorerButton", SGHideArtistExplore},
    {@"Curation.FollowButtonElementKit.FollowButton", SGHideArtistFollow},
    {@"Components.UI.ContextMenuButton", SGHideArtistMore},
    {@"Components.UI.ShuffleButton", SGHideArtistShuffle},
};
enum { kButtons = sizeof(buttons) / sizeof(buttons[0]) };

// The header's parts, each remembered on the header once found (Core/SGViewTree.h).
static char kBadgeKey, kMetadataKey, kTitleKey, kArtworkKey, kButtonKeys[kButtons];
static NSString *const kBadge = @"ImageHeaderView.VerifiedBadge", *const kMetadata = @"Components.Header.UI.Metadata";

// The identifier sits on the button; the action is the view the button row arranges around it.
static UIView *actionHolding(UIView *button, UIView *header) {
    for (UIView *v = button; v.superview && v.superview != header; v = v.superview) {
        if (v.superview.superview == header) return v;
        if (SGClassNamed(v.superview.class, @"OverflowStackView")) return v;
    }
    return nil;
}

static void applyHeader(UIView *header) {
    if (SGHidden(SGHideArtistVerified)) SGFindIdentifier(header, kBadge, &kBadgeKey).hidden = YES;
    // Its AutoLayoutStackView traps like OverflowStackView below once the label goes hidden.
    if (SGHidden(SGHideArtistListeners)) SGFindIdentifier(header, kMetadata, &kMetadataKey).alpha = 0;

    for (size_t i = 0; i < kButtons; i++) {
        if (!SGHidden(buttons[i].key)) continue;
        UIView *action = actionHolding(SGFindIdentifier(header, buttons[i].ident, &kButtonKeys[i]), header);
        if (!action) continue;
        // OverflowStackView traps in updateConstraints once its views go hidden (crash 2026-09-15),
        // so those only turn invisible and keep their place.
        if (SGClassNamed(action.superview.class, @"OverflowStackView")) {
            action.alpha = 0;
            action.userInteractionEnabled = NO;
        } else {
            action.hidden = YES;
        }
    }
}

static CGFloat bottomOf(UIView *v) {
    return v.center.y + CGRectGetHeight(v.bounds) / 2;
}

static UIView *childOfHeader(UIView *view, UIView *header) {
    for (UIView *v = view; v; v = v.superview) {
        if (v.superview == header) return v;
    }
    return nil;
}

// The header keeps Spotify's height, so the room the hidden badge and listeners leave is given to
// the photo: the title block slides down to sit where the lowest of them sat. Transforms, because
// the header's stack views crash on anything that changes their layout.
static void closeUpTitle(UIView *header) {
    // The badge first: an artist without one is left alone before anything else is looked for.
    UIView *badge = SGFindIdentifier(header, kBadge, &kBadgeKey);
    if (!badge || badge.superview != header) return;
    UIView *title = childOfHeader(SGFindIdentifier(header, @"Encore.AdaptiveTitle", &kTitleKey), header);
    UIView *listeners = SGFindIdentifier(header, kMetadata, &kMetadataKey);
    UIView *metadata = childOfHeader(listeners, header);
    if (!title || !metadata) return;

    // Walks up from the listeners' line: each shown line lands on the bottom edge the line under it
    // left free, keeping its own gap to the line above.
    CGFloat edge = listeners.alpha > 0 ? bottomOf(badge) : bottomOf(metadata);
    CGFloat move = 0;
    if (!badge.hidden) {
        move = edge - bottomOf(badge);
        badge.transform = CGAffineTransformMakeTranslation(0, move);
        edge = bottomOf(title) + move;
    }
    title.transform = CGAffineTransformMakeTranslation(0, MAX(0, edge - bottomOf(title)));
}

#pragma mark - photo fade

// The photo sits in a clipping view shorter than the header, and Spotify's gradient over it is cut by
// the same clip, so the picture ends in a straight line well above the buttons. With the switch on,
// the photo's lower part dissolves into a blurred copy of itself that reaches the header's bottom
// and fades out there.
//
// The blur's sigma is a share of the photo's width, so all the copy keeps is a few samples per sigma: the photo
// is drawn down to kBlurSamplesPerSigma of them before blurring. Spotify's 640 px photo is blurred at 288 px,
// and shown at the header's size it differs from the whole photo blurred by at most 2 of 255 away from the
// edges and 5 at them.
static const CGFloat kBlurSigmaPerWidth = 1.0 / 18, kBlurLeastSigmaPixels = 6, kBlurSamplesPerSigma = 16;

static UIImage *blurred(UIImage *image) {
    CGImageRef source = image.CGImage;
    size_t width = CGImageGetWidth(source), height = CGImageGetHeight(source);
    if (!width || !height) return nil;
    CGFloat sigma = MAX(width * kBlurSigmaPerWidth, kBlurLeastSigmaPixels), scale = MIN(1, kBlurSamplesPerSigma / sigma);
    size_t smallWidth = MAX(1, (size_t)lround(width * scale)), smallHeight = MAX(1, (size_t)lround(height * scale));
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef bitmap = CGBitmapContextCreate(NULL, smallWidth, smallHeight, 8, 0, space,
                                                kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    if (!bitmap) return nil;
    CGContextSetInterpolationQuality(bitmap, kCGInterpolationHigh);
    CGContextDrawImage(bitmap, CGRectMake(0, 0, smallWidth, smallHeight), source);
    CGImageRef small = CGBitmapContextCreateImage(bitmap);
    CGContextRelease(bitmap);
    CIImage *input = small ? [CIImage imageWithCGImage:small] : nil;
    CGImageRelease(small);
    if (!input) return nil;
    CIImage *output = [[input imageByClampingToExtent] imageByApplyingGaussianBlurWithSigma:sigma * smallWidth / width];
    CGImageRef cg = [SGOneOffImageContext() createCGImage:[output imageByCroppingToRect:input.extent] fromRect:input.extent];
    UIImage *result = cg ? [UIImage imageWithCGImage:cg] : nil;
    CGImageRelease(cg);
    return result;
}

static CAGradientLayer *fadeMask(CALayer *host, NSArray<NSNumber *> *locations) {
    CAGradientLayer *mask = [host.mask isKindOfClass:CAGradientLayer.class] ? (CAGradientLayer *)host.mask : nil;
    if (!mask) {
        mask = [CAGradientLayer layer];
        mask.colors = @[(id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.clearColor.CGColor];
        host.mask = mask;
    }
    mask.locations = locations;
    mask.frame = host.bounds;
    return mask;
}

static void applyPhotoFade(UIView *header) {
    if (!SGFlag(SGKeyArtistPhotoFade, NO)) return;
    UIView *artwork = SGFindIdentifier(header, @"Components.Header.UI.ArtworkImage", &kArtworkKey);
    UIView *clip = childOfHeader(artwork, header);
    if (!artwork || !clip || clip == artwork) return;
    __block UIImageView *source = nil;
    SGForEachView(artwork, ^(UIView *v) {
        if (!source && [v isKindOfClass:UIImageView.class] && ((UIImageView *)v).image) source = (UIImageView *)v;
    });

    static char backdropKey, sourceKey;
    UIImageView *backdrop = objc_getAssociatedObject(header, &backdropKey);
    if (!backdrop) {
        backdrop = [[UIImageView alloc] init];
        backdrop.contentMode = UIViewContentModeScaleAspectFill;
        backdrop.clipsToBounds = YES;
        backdrop.userInteractionEnabled = NO;
        UIView *shade = [[UIView alloc] init];
        shade.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
        shade.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [backdrop addSubview:shade];
        objc_setAssociatedObject(header, &backdropKey, backdrop, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (header.subviews.firstObject != backdrop) [header insertSubview:backdrop atIndex:0];
    if (source.image && objc_getAssociatedObject(header, &sourceKey) != source.image) {
        UIImage *soft = blurred(source.image);
        if (soft) {
            objc_setAssociatedObject(header, &sourceKey, source.image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            backdrop.image = soft;
        }
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGRect photo = [artwork convertRect:artwork.bounds toView:header];
    CGFloat side = MAX(CGRectGetWidth(photo), CGRectGetHeight(header.bounds));
    backdrop.frame = CGRectMake(CGRectGetMidX(photo) - side / 2, 0, side, CGRectGetHeight(header.bounds));
    backdrop.subviews.firstObject.frame = backdrop.bounds;
    backdrop.alpha = MIN(1, MAX(0, artwork.alpha));
    fadeMask(backdrop.layer, @[@0, @0.7, @1]);
    fadeMask(clip.layer, @[@0, @0.55, @1]);
    [CATransaction commit];
}

%hook _TtC35CreativeWorkPlatform_ImageHeaderKit15ImageHeaderView
- (void)layoutSubviews {
    %orig;
    applyHeader((UIView *)self);
    closeUpTitle((UIView *)self);
    applyPhotoFade((UIView *)self);
}
%end

// The buttons arrive after the header has laid out, and a row that keeps its size never lays the
// header out again.
%hook UIStackView
- (void)layoutSubviews {
    %orig;
    UIView *header = self.superview;
    if (!SGClassNamed(header.class, @"ImageHeaderKit")) return;
    applyHeader(header);
    closeUpTitle(header);
}
%end

#pragma mark - tab bar

// Trees (trees/continuous/1.txt): the strip (Components.UI.TabsSectionHeading) sits above a paging
// scroll view holding one list per tab. The strip lives in a LegacyUI AutoLayoutStackView, so it
// goes invisible rather than hidden; the pages move up into its place and stop swiping, which
// leaves the Music list.
static void hideTabBar(UIView *strip) {
    strip.alpha = 0;
    strip.userInteractionEnabled = NO;
    for (UIView *v in strip.superview.subviews) {
        if (![v isKindOfClass:UIScrollView.class]) continue;
        ((UIScrollView *)v).scrollEnabled = NO;
        v.transform = CGAffineTransformMakeTranslation(0, -CGRectGetHeight(strip.bounds));
    }
}

%hook _TtCOOOE16PodcastUI_ECMKitO19LegacyUI_ECMCoreKit10Components18TabsSectionHeading2UI7Private9TabButton
- (void)layoutSubviews {
    %orig;
    if (!SGHidden(SGHideArtistTabBar)) return;
    for (UIView *v = ((UIView *)self).superview; v; v = v.superview) {
        if (![v.accessibilityIdentifier isEqualToString:@"Components.UI.TabsSectionHeading"]) continue;
        if (onArtistPage(v)) hideTabBar(v);
        return;
    }
}
%end

#pragma mark - sections

static const SGNativeSectionRule sections[] = {
    {@"Popular", SGHideArtistPopular, NO},
    {@"Artist pick", SGHideArtistPick, NO},
    {@"Popular releases", SGHideArtistReleases, NO},
    {@"Featuring ", SGHideArtistFeaturing, YES},
    {@"Music videos", SGHideArtistVideos, NO},
    {@"Watch more from ", SGHideArtistVideos, YES},
    {@"About", SGHideArtistAbout, NO},
    {@"Artist playlists", SGHideArtistPlaylists, NO},
    {@"Fans also like", SGHideArtistFansAlsoLike, NO},
    {@"Appears on", SGHideArtistAppearsOn, NO},
    {@"Discovered on", SGHideArtistDiscoveredOn, NO},
};

enum { kSections = sizeof(sections) / sizeof(sections[0]) };

// The heading's title, or @"" for a cell that is not a heading.
static NSString *headingIn(UIView *cell) {
    __block NSString *title = nil;
    SGForEachView(cell, ^(UIView *v) {
        if (!title && SGClassNamed(v.class, @"SectionHeadingHome") && v.accessibilityLabel.length) {
            title = v.accessibilityLabel;
        }
    });
    return title ?: @"";
}

static UICollectionView *listOf(UIView *cell) {
    for (UIView *v = cell.superview; v; v = v.superview) {
        if ([v isKindOfClass:UICollectionView.class]) return (UICollectionView *)v;
    }
    return nil;
}

static BOOL collapsed(UICollectionViewCell *cell, NSIndexPath *path) {
    BOOL hideLiked = SGHidden(SGHideArtistLikedSongs), anySection = SGNativeAnySectionHidden(sections, kSections);
    if (!hideLiked && !anySection) return NO;
    for (UIView *v = cell.superview; v; v = v.superview) {
        if ([v isKindOfClass:cell.class]) return NO;   // a card inside a carousel: its row decides
    }
    if (!onArtistPage(cell)) return NO;
    static char likedKey;
    if (hideLiked && SGFindIdentifier(cell, @"Components.UI.LikedSongs.Row", &likedKey)) return YES;
    if (!anySection || !path) return NO;

    UICollectionView *list = listOf(cell);
    if (!list) return NO;
    static char headingsKey;
    NSMutableDictionary *headings = SGNativeHeadings(list, &headingsKey);
    headings[path] = headingIn(cell);
    NSString *section = SGNativeSectionAt(path, headings);
    return section && SGNativeSectionHidden(section, sections, kSections);
}

%hook _TtC12Element_List18CollectionViewCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewLayoutAttributes *result = %orig;
    if (!collapsed((UICollectionViewCell *)self, attributes.indexPath)) return result;
    result.size = CGSizeMake(result.size.width, 0);
    ((UIView *)self).clipsToBounds = YES;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"artist page: collapsed the first row"); });
    return result;
}
%end

%ctor {
    if (!SGNativeUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC35CreativeWorkPlatform_ImageHeaderKit15ImageHeaderView",
        @"_TtC12Element_List18CollectionViewCell",
        @"_TtCOOOE16PodcastUI_ECMKitO19LegacyUI_ECMCoreKit10Components18TabsSectionHeading2UI7Private9TabButton",
    ]);
}
