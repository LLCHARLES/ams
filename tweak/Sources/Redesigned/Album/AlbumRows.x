// Album redesign: the track rows on the field, the way the Music app has them -- no surface of their own
// and a hairline from the text's edge between one row and the next.
//
// Tree (trees/clean/album/03.txt:524-575): every row of the page is an Element_List.CollectionViewCell
// holding an Encore.ListRow, id=Components.UI.RetrievalRowElementUI, with the title
// (EncoreConsumerMobile.View.Granular.Title), the artists under it (…Granular.Subtitle) and, at the
// trailing edge, Components.UI.ContextMenuButton. A loaded 9.1.90 row carries neither Granular identifier: its
// title and artists are RetrievalRowKit's TitleView and SubtitleView (titleOf, subtitleOf). An album row carries no artwork -- every track on the
// page shares the cover the header is already showing -- so the hairline runs from the page's own margin,
// where the text starts.
//
// The row's paint is cleared here rather than left to the Kit's repaint hook, which only hears about a
// color when Spotify sets it and not when a reused cell already carries one.
//
// Spotify's type and its spacing are left alone: the row is 56pt for a title of 13pt, and a larger font of
// the Kit's would be cut off by the box the element framework measured for it.
//
// **The artist line, where it only repeats the album's.** The Music app shows a track's title alone on a
// standard album, so the line goes where AlbumCredits.m finds it says nothing the header does not. It goes by
// alpha on the Subtitle wrapper: Encore sets its inner label's alpha again later, `hidden` inside its stacks
// crashes, and the row keeps the height Spotify measured for it. The title is moved down to the middle of the
// row by a translation. The explicit badge is a sibling of the line, not inside it, so it is drawn again as a
// picture after the title's text, 4pt on, and the badge itself goes by alpha; the title is narrowed by the
// badge's room so a long one cannot run under it or under ⋯. Right to left, all of it the other way round.
// The row's own accessibility label still names the artists and says explicit; the picture is not an element.
//
// **Play counts.** A track played in Listening stats says how many times, "12 plays", in the secondary color on
// the row's middle just before ⋯ (before the green check Spotify puts there on a liked track), as small as the row's
// own type allows; none for a track never played. The
// count is the album's title and the row's title matched in the log (AlbumPlays.m), so the rows are laid out
// again when the header's title arrives and when the counts change. The title and the artist line are narrowed
// so neither runs under it. This is done before the artist line's change, which then measures the narrowed
// title, and put back after it. That is the In the row place of the Albums page's Play counts; In menu the row shows
// none, and its ⋯ tells AlbumPlaysMenu.x which track the sheet it opens is for.
//
// Everything changed is put back at the start of the cell's next pass and when the cell is prepared for reuse,
// which also asks for a pass: Spotify can show a cached row again at the same size without one, and the last
// row's state would stay on it.
//
// **⋯ in the page's colour.** The row's ⋯ (Components.UI.ContextMenuButton, its glyph the image view inside it) is drawn
// in a soft tint of the page's colour: OKLab lightness 0.80 (0.88 with Increase Contrast), the page's hue, chroma held
// to 0.08 and to what sRGB holds there. A template glyph takes it as its tint. Spotify also ships the glyph with its colour baked into the picture,
// which a tint does not reach: then a layer of the colour lies over the glyph in its superlayer, masked by the glyph's
// own picture at its scale and gravity, and an empty mask of this file's hides the glyph's own paint -- only where the
// glyph has no mask already; one someone else put there leaves the glyph alone. Unlike the rest this is kept from pass
// to pass, each property set only when it differs, and taken off (the tint and the mask put back only where they are
// still this file's) when the picture is replaced or gone, the row is laid out anywhere but an album's page, or a pass
// runs while the app is not active. The button, its action, its menu and what VoiceOver reads are Spotify's.
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRCoverRead.h"
#import "Album.h"
#import "AlbumSpotifyCounts.h"

// The existing Shared/AlbumQueue Swift identity reader; no title or navigation-stack guessing.
@interface SGAlbumQueuePage : NSObject
+ (NSString *)albumURI:(id)controller;
@end

// Under the text rather than the whole row, as the Music app draws it; the trailing end clears the page
// margin.
static const CGFloat kHairline = 0.5;
// Between the end of the title's text and the badge drawn after it.
static const CGFloat kBadgeGap = 4;
// Between the play count and the box of ⋯ or of the liked check before it, whose glyph is inset in it already, and
// between the text and the count.
static const CGFloat kCountGap = 2, kCountTextGap = 8;

static char kRowKey, kSubtitleKey, kLineKey, kTitleKey, kBadgeKey, kArtistKey, kChangeKey;
static char kAlbumKey, kMenuKey, kCountKey, kCountChangeKey;
static NSMutableSet<NSString *> *sg_loggedMenus;

static void clearSurface(UIView *view) {
    UIColor *color = view.backgroundColor;
    if (color && SGIsBaseSurface(color.CGColor)) view.backgroundColor = UIColor.clearColor;
}

static void applyHairline(UIView *row) {
    CALayer *line = objc_getAssociatedObject(row, &kLineKey);
    if (!line) {
        line = [CALayer layer];
        line.zPosition = 1;
        objc_setAssociatedObject(row, &kLineKey, line, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    line.backgroundColor = SGRHairline().CGColor;
    if (line.superlayer != row.layer) [row.layer addSublayer:line];
    CGRect bounds = row.bounds;
    CGRect frame = CGRectMake(SGRSideMargin, bounds.size.height - kHairline,
                              MAX(0, bounds.size.width - 2 * SGRSideMargin), kHairline);
    if (CGRectEqualToRect(line.frame, frame)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    line.frame = frame;
    [CATransaction commit];
}

#pragma mark - the artist line

// What a row's credit change touched, and what each was before, to be put back.
@interface SGRCreditChange : NSObject
@property (nonatomic, weak) UIView *subtitle, *badge;
@property (nonatomic, weak) UILabel *title;
@property (nonatomic) CGFloat subtitleAlpha, badgeAlpha;
@property (nonatomic) CGRect titleFrame, narrowFrame;
@property (nonatomic) CGAffineTransform shift;
@property (nonatomic, strong) UIImageView *drawnBadge;
@end

@implementation SGRCreditChange
@end

// The badge picture a row keeps from one pass to the next, with how the source badge looked when it was drawn.
@interface SGRDrawnBadge : NSObject
@property (nonatomic, strong) UIImageView *view;
@property (nonatomic, weak) UIView *source;
@property (nonatomic) CGSize size;
@property (nonatomic) CGFloat alpha;
@property (nonatomic, strong) UITraitCollection *traits;
@property (nonatomic, strong) UIColor *tint, *fill;
// Hide explicit badge swaps this for a transparent one (Kit/SGRExplicitBadge.x), which the picture takes with it.
@property (nonatomic, strong) CALayer *mask;
@end

@implementation SGRDrawnBadge
@end

static BOOL hidesCredits(void) {
    static NSInteger on = -1;
    if (on < 0) on = SGEnabled(SGRKeyAlbumHideTrackArtists);
    return on;
}

// The one label under `view`, itself included, with text in it; nil for none or for more than one.
static UILabel *onlyLabel(UIView *view) {
    __block UILabel *found = nil;
    __block NSUInteger count = 0;
    SGForEachView(view, ^(UIView *v) {
        if (![v isKindOfClass:UILabel.class]) return;
        NSString *text = [((UILabel *)v).text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!text.length) return;
        found = (UILabel *)v;
        count++;
    });
    return count == 1 ? found : nil;
}

static char kLoadedTitleKey, kLoadedSubtitleKey;

// A loading row names its title Granular.Title; a loaded 9.1.90 row has no such identifier and draws it in
// RetrievalRowKit's TitleView instead (AlbumNotes.m reads both the same way).
static UILabel *titleOf(UIView *row) {
    static Class loaded;
    if (!loaded) loaded = NSClassFromString(@"_TtCC36CreativeWorkPlatform_RetrievalRowKit21RetrievalRowElementUI9TitleView");
    UIView *title = SGRFindByIdentifier(row, @"EncoreConsumerMobile.View.Granular.Title", &kTitleKey)
        ?: SGFindRemembered(row, &kLoadedTitleKey, ^BOOL(UIView *v) { return loaded && [v isKindOfClass:loaded]; });
    return onlyLabel(title);
}

// The artist line the same way: Granular.Subtitle, or a loaded 9.1.90 row's SubtitleView. Only the count keeps clear
// of it; the artist line's change needs the Granular wrapper, whose sibling the explicit badge is.
static UIView *subtitleOf(UIView *row) {
    static Class loaded;
    if (!loaded) loaded = NSClassFromString(@"_TtCC36CreativeWorkPlatform_RetrievalRowKit21RetrievalRowElementUI12SubtitleView");
    return SGRFindByIdentifier(row, @"EncoreConsumerMobile.View.Granular.Subtitle", &kSubtitleKey)
        ?: SGFindRemembered(row, &kLoadedSubtitleKey, ^BOOL(UIView *v) { return loaded && [v isKindOfClass:loaded]; });
}

// The badge as it draws, rendered the moment before it goes: an unplayable row's is grayed, so it is not cached.
static UIImage *pictureOf(UIView *badge) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat formatForTraitCollection:badge.traitCollection];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:badge.bounds.size format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [badge.layer renderInContext:context.CGContext];
    }];
}

static BOOL sameColor(UIColor *a, UIColor *b) {
    return a == b || [a isEqual:b];
}

static char kDrawnKey;

static void dropDrawnBadge(UIView *cell) {
    SGRDrawnBadge *kept = objc_getAssociatedObject(cell, &kDrawnKey);
    if (!kept) return;
    [kept.view removeFromSuperview];
    objc_setAssociatedObject(cell, &kDrawnKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// The row's picture of `badge`: the one it already has while the badge is the same view and looks the same (size,
// traits, tint, fill, alpha and mask), else a new one drawn now.
static UIImageView *drawnBadgeFor(UIView *cell, UIView *badge) {
    SGRDrawnBadge *kept = objc_getAssociatedObject(cell, &kDrawnKey);
    if (kept && kept.source == badge && CGSizeEqualToSize(kept.size, badge.bounds.size) && kept.alpha == badge.alpha
        && [kept.traits isEqual:badge.traitCollection] && sameColor(kept.tint, badge.tintColor)
        && sameColor(kept.fill, badge.backgroundColor) && kept.mask == badge.layer.mask) return kept.view;
    dropDrawnBadge(cell);
    kept = [SGRDrawnBadge new];
    kept.view = [[UIImageView alloc] initWithImage:pictureOf(badge)];
    kept.view.userInteractionEnabled = NO;
    kept.view.isAccessibilityElement = NO;
    kept.source = badge;
    kept.size = badge.bounds.size;
    kept.alpha = badge.alpha;
    kept.traits = badge.traitCollection;
    kept.tint = badge.tintColor;
    kept.fill = badge.backgroundColor;
    kept.mask = badge.layer.mask;
    objc_setAssociatedObject(cell, &kDrawnKey, kept, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return kept.view;
}

// Puts back what the last change took, except the drawn badge, which the pass that follows keeps or drops. YES when
// there was one.
static BOOL restoreCredit(UIView *cell) {
    SGRCreditChange *change = objc_getAssociatedObject(cell, &kChangeKey);
    if (!change) return NO;
    objc_setAssociatedObject(cell, &kChangeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // The transform before the frame, which is meaningless under one. Each only where it is still this change's:
    // a pass of Spotify's since may have put its own there.
    UILabel *title = change.title;
    if (title && CGAffineTransformEqualToTransform(title.transform, change.shift)) title.transform = CGAffineTransformIdentity;
    if (title && !CGRectIsNull(change.narrowFrame) && CGRectEqualToRect(title.frame, change.narrowFrame)) title.frame = change.titleFrame;
    if (change.subtitle.alpha == 0) change.subtitle.alpha = change.subtitleAlpha;
    if (change.badge.alpha == 0) change.badge.alpha = change.badgeAlpha;
    return YES;
}

// The rows on screen were laid out against what the header said before; the rest are laid out as they come.
static void layOutRowsAgain(UIView *page) {
    SGForEachView(page, ^(UIView *v) {
        if ([v isKindOfClass:%c(_TtC12Element_List18CollectionViewCell)]) [v setNeedsLayout];
    });
}

static char kMotionRowKey, kMotionBatchDepth, kMotionPageKey, kMotionOwnerKey;
static const NSUInteger kMotionPagePairs = 8;

@interface SGRAlbumMotionLifetime : NSObject
@property (nonatomic, copy) NSString *album, *releaseID;
@property (nonatomic) BOOL headerOnly;
@property (nonatomic, strong) NSMutableSet *pairs;
@end
@implementation SGRAlbumMotionLifetime
@end

static void observeRelease(SGRAlbumMotionLifetime *state, NSString *album, NSString *releaseID) {
    if ((state.album && album && ![state.album isEqual:album]) ||
        (state.releaseID && releaseID && ![state.releaseID isEqual:releaseID])) state.headerOnly = YES;
    if (!state.album && album) state.album = album;
    if (!state.releaseID && releaseID) state.releaseID = releaseID;
}

// A replaced hero must not forget the page's album, nor may a reparented list
// bring rows from its previous owner. The state holds no view or callback.
static SGRAlbumMotionLifetime *bindMotionOwner(UIView *page, UIView *owner) {
    SGRAlbumMotionLifetime *state = objc_getAssociatedObject(page, &kMotionPageKey);
    if (!state) {
        state = [SGRAlbumMotionLifetime new];
        objc_setAssociatedObject(page, &kMotionPageKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    SGRAlbumMotionLifetime *prior = objc_getAssociatedObject(owner, &kMotionOwnerKey);
    if (state != prior) {
        observeRelease(state, prior.album, prior.releaseID);
        if (prior.headerOnly) state.headerOnly = YES;
        objc_setAssociatedObject(owner, &kMotionOwnerKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}

void SGRAlbumMotionHeader(UIView *page, UIView *hero, NSString *albumKey, NSString *releaseID) {
    if (!page) return;
    SGRAlbumMotionLifetime *state = bindMotionOwner(page, hero);
    observeRelease(state, albumKey, releaseID);
    if (state.headerOnly) objc_setAssociatedObject(page, &kMotionRowKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

BOOL SGRAlbumMotionRowsAllowed(UIView *page) {
    SGRAlbumMotionLifetime *state = objc_getAssociatedObject(page, &kMotionPageKey);
    return state.album != nil && !state.headerOnly;
}

void SGRAlbumWaitForMotionRow(UIView *page, BOOL evaluating, BOOL (^use)(NSString *, NSString *)) {
    if (!page) return;
    SGRAlbumMotionLifetime *state = objc_getAssociatedObject(page, &kMotionPageKey);
    if (!use || !SGRAlbumMotionRowsAllowed(page) || state.pairs.count >= kMotionPagePairs) {
        objc_setAssociatedObject(page, &kMotionRowKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
        return;
    }
    if (evaluating && !state.pairs) state.pairs = [NSMutableSet set];
    BOOL (^offer)(NSArray *) = ^BOOL(NSArray *pair) {
        if (!evaluating) return use(pair[0], pair[1]);
        if ([state.pairs containsObject:pair]) return NO;
        [state.pairs addObject:pair];
        return use(pair[0], pair[1]) || state.pairs.count >= kMotionPagePairs;
    };
    objc_setAssociatedObject(page, &kMotionRowKey, offer, OBJC_ASSOCIATION_COPY_NONATOMIC);
    layOutRowsAgain(page); // existing rows may have laid out while the header search was pending
}

static NSArray *motionEvidence(UIView *row) {
    NSString *song = titleOf(row).text, *credit = onlyLabel(subtitleOf(row)).text;
    if (!song.length || !credit.length) return nil;
    return @[[credit stringByReplacingOccurrencesOfString:@" 및 " withString:@", "], song];
}

static void offerMotionRow(UICollectionViewCell *cell, UIView *row, UIView *page) {
    NSString *kind = row.accessibilityIdentifier;
    if (![kind isEqual:@"Components.UI.RetrievalRowElementUI_Loaded"] && ![kind isEqual:@"Components.UI.RetrievalRowElementUI"]) return;
    // The device tree's track cell belongs directly to the template's list, not a carousel
    // or a header's nested collection. Recheck the live ancestry, not a recycled cell's cached place.
    UICollectionView *list = (id)cell.superview;
    if (![list isKindOfClass:UICollectionView.class] ||
        ![list.superview isKindOfClass:%c(_TtC32CreativeWorkPlatform_TemplateKit28CreativeWorkTemplateListView)] ||
        SGRAlbumPageOf(list.superview) != page) return;
    if (bindMotionOwner(page, list).headerOnly) {
        objc_setAssociatedObject(page, &kMotionRowKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
        return;
    }
    BOOL (^use)(NSArray *) = objc_getAssociatedObject(page, &kMotionRowKey);
    if (!use || cell.hidden || [objc_getAssociatedObject(list, &kMotionBatchDepth) unsignedIntegerValue] ||
        ![list indexPathForCell:cell]) return;
    NSArray *pair = motionEvidence(row);
    if (!pair) return;
    if (use(pair) && objc_getAssociatedObject(page, &kMotionRowKey) == use)
        objc_setAssociatedObject(page, &kMotionRowKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

void SGRAlbumSetArtist(UIView *view, NSString *artist) {
    UIView *page = SGRAlbumPageOf(view);
    NSString *known = objc_getAssociatedObject(page, &kArtistKey);
    if (!page || known == artist || [known isEqualToString:artist]) return;
    objc_setAssociatedObject(page, &kArtistKey, artist, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (hidesCredits()) layOutRowsAgain(page);
}

static void applyCredit(UIView *cell, UIView *row, UIView *page) {
    NSString *album = objc_getAssociatedObject(page, &kArtistKey);
    if (!album) return;
    UIView *subtitle = SGRFindByIdentifier(row, @"EncoreConsumerMobile.View.Granular.Subtitle", &kSubtitleKey);
    UILabel *title = onlyLabel(SGRFindByIdentifier(row, @"EncoreConsumerMobile.View.Granular.Title", &kTitleKey));
    UILabel *artist = onlyLabel(subtitle);
    if (!title || !artist || !SGRCreditRepeatsAlbum(album, artist.text, title.text)) return;
    // Mid animation the title's frame is not where it is going.
    if (!CGAffineTransformIsIdentity(title.transform) || title.layer.animationKeys.count) return;

    UIView *badge = SGRFindByIdentifier(row, @"Components.UI.ExplicitIcon", &kBadgeKey);
    if (badge && (badge.hidden || badge.alpha < 0.01 || CGRectIsEmpty(badge.bounds))) badge = nil;
    CGRect frame = title.frame;
    CGFloat room = badge ? badge.bounds.size.width + kBadgeGap : 0;
    if (frame.size.width - room < title.font.lineHeight) return;
    NSTextAlignment alignment = title.textAlignment;
    BOOL rtl = title.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    BOOL textAtRight = alignment == NSTextAlignmentRight || (alignment == NSTextAlignmentNatural && rtl);
    CGFloat narrowWidth = frame.size.width - room;
    CGSize text = [title textRectForBounds:CGRectMake(0, 0, narrowWidth, CGFLOAT_MAX) limitedToNumberOfLines:title.numberOfLines].size;
    // ponytail: one line only. A wrapped title's last line ends somewhere this does not measure, so its badge
    // would be placed against the widest line; such a row keeps its artist line instead.
    if (badge && (alignment == NSTextAlignmentCenter || text.height > title.font.lineHeight * 1.5)) return;

    SGRCreditChange *change = [SGRCreditChange new];
    change.subtitle = subtitle;
    change.subtitleAlpha = subtitle.alpha;
    change.title = title;
    change.titleFrame = frame;
    change.narrowFrame = CGRectNull;
    subtitle.alpha = 0;
    if (badge) {
        CGRect narrow = frame;
        narrow.size.width = narrowWidth;
        if (rtl) narrow.origin.x += room;
        title.frame = narrow;
        change.narrowFrame = narrow;
    }
    CGFloat scale = row.window.screen.scale ?: UIScreen.mainScreen.scale;
    CGPoint centre = [title.superview convertPoint:title.center toView:row];
    CGFloat dy = round((CGRectGetMidY(row.bounds) - centre.y) * scale) / scale;
    change.shift = CGAffineTransformMakeTranslation(0, dy);
    title.transform = change.shift;

    if (badge) {
        UIImageView *drawn = drawnBadgeFor(cell, badge);
        CGSize size = badge.bounds.size;
        CGFloat textWidth = MIN(ceil(text.width), narrowWidth);
        CGFloat x = textAtRight ? narrowWidth - textWidth - kBadgeGap - size.width : textWidth + kBadgeGap;
        CGRect inTitle = CGRectMake(x, (title.bounds.size.height - size.height) / 2, size.width, size.height);
        // Through the title, whose transform the conversion takes along.
        drawn.frame = [title convertRect:inTitle toView:row];
        if (drawn.superview != row) [row addSubview:drawn];
        change.drawnBadge = drawn;
        change.badge = badge;
        change.badgeAlpha = badge.alpha;
        badge.alpha = 0;
    }
    objc_setAssociatedObject(cell, &kChangeKey, change, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    static BOOL logged;
    if (!logged) {
        logged = YES;
        SGLog(@"redesign album: a track's artist line hidden as the album's, badge %@", badge ? @"moved up" : @"none");
    }
}

#pragma mark - play counts

static SGRAlbumPlayCountsPlace countsPlace(void) {
    static NSInteger place = -1;
    if (place < 0) place = SGRAlbumPlayCountsWhere();
    return (SGRAlbumPlayCountsPlace)place;
}

// The album pages that have had a title, to lay out again when the counts change.
static NSHashTable<UIView *> *countedPages(void) {
    static NSHashTable<UIView *> *pages;
    if (!pages) pages = [NSHashTable weakObjectsHashTable];
    return pages;
}

static NSString *pageAlbumURI(UIView *page) {
    NSString *uri;
    for (UIResponder *r = page.nextResponder; r; r = r.nextResponder) {
        if (![r isKindOfClass:UIViewController.class]) continue;
        uri = [NSClassFromString(@"SGAlbumQueuePage") albumURI:r];
        if (uri) break;
    }
    return uri;
}

static SGRAlbumCountPage *spotifyCountsForPage(UIView *page) {
    static char key;
    SGRAlbumCountPage *counts = objc_getAssociatedObject(page, &key);
    if (!counts) {
        counts = [[SGRAlbumCountPage alloc] initWithStore:SGRAlbumSpotifyCountsStore()];
        objc_setAssociatedObject(page, &key, counts, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSString *uri = pageAlbumURI(page);
    __weak UIView *weakPage = page;
    [counts followAlbum:uri changed:^{
        UIView *page = weakPage;
        if (page) layOutRowsAgain(page);
        [NSNotificationCenter.defaultCenter postNotificationName:SGRAlbumPlayCountsDidChangeNotification object:nil];
    }];
    return counts;
}

static BOOL sg_trackNumbers;
static char kIndexAlbum, kTrackIndex;
static void followTrackIndex(UIView *page) {
    NSString *uri = pageAlbumURI(page);
    NSString *previous = objc_getAssociatedObject(page, &kIndexAlbum);
    if (previous == uri || [previous isEqual:uri]) return;
    objc_setAssociatedObject(page, &kIndexAlbum, uri, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(page, &kTrackIndex, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    layOutRowsAgain(page);
    if (!uri) return;
    __weak UIView *weakPage = page;
    [SGRAlbumSpotifyCountsStore() loadTrackIndex:uri completion:^(SGRAlbumTrackIndex *index) {
        UIView *page = weakPage;
        if (![objc_getAssociatedObject(page, &kIndexAlbum) isEqual:uri]) return;
        objc_setAssociatedObject(page, &kTrackIndex, index, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (index) layOutRowsAgain(page);
    }];
}

void SGRAlbumSetTitle(UIView *view, NSString *title) {
    UIView *page = SGRAlbumPageOf(view);
    if (sg_trackNumbers && page) followTrackIndex(page);
    if (page && countsPlace() != SGRAlbumPlayCountsOff && SGRAlbumUsesSpotifyCounts()) {
        spotifyCountsForPage(page);
        return;
    }
    NSString *known = objc_getAssociatedObject(page, &kAlbumKey);
    if (!page || countsPlace() == SGRAlbumPlayCountsOff || known == title || [known isEqualToString:title]) return;
    objc_setAssociatedObject(page, &kAlbumKey, title, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (countsPlace() == SGRAlbumPlayCountsInMenu) {
        // No row asks for a count before a ⋯ is touched; the first ask starts reading the log, so it is read by then.
        SGRAlbumPlayCount(title, nil);
        return;
    }
    [countedPages() addObject:page];
    layOutRowsAgain(page);
}

// In menu: a row's ⋯ says which track the sheet it opens is for (AlbumPlaysMenu.x) as it sends its action, before
// Spotify's runs: a finger's tap, VoiceOver's activation, Full Keyboard Access and Switch Control all go through
// UIControl's sendAction, where a touch-down target would miss every one but the finger. A row's pass flags its ⋯
// as watched, so every other control pays one associated-object read. The cell holds the ⋯ it flagged and takes the
// flag back as it is prepared for reuse or laid out as anything but an album's track row; and the action checks the
// row again, so a ⋯ that is no longer an album track's leaves whatever mark there is alone.
static char kWatchedKey, kWatchedMenuKey;

static void unwatch(UIView *cell) {
    UIView *menu = objc_getAssociatedObject(cell, &kWatchedMenuKey);
    if (!menu) return;
    objc_setAssociatedObject(menu, &kWatchedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(cell, &kWatchedMenuKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static UIView *cellOf(UIView *view) {
    Class cellClass = %c(_TtC12Element_List18CollectionViewCell);
    for (UIView *v = view; v; v = v.superview) {
        if ([v isKindOfClass:cellClass]) return v;
    }
    return nil;
}

static void markIfWatched(UIControl *control) {
    if (!objc_getAssociatedObject(control, &kWatchedKey)) return;
    UICollectionViewCell *cell = (UICollectionViewCell *)cellOf(control);
    UIView *page = cell ? SGRAlbumPageOf(cell) : nil;
    NSString *album = page ? objc_getAssociatedObject(page, &kAlbumKey) : nil;
    UIView *row = control.superview;
    while (row && ![row.accessibilityIdentifier hasPrefix:@"Components.UI.RetrievalRow"]) row = row.superview;
    UILabel *title = titleOf(row);
    BOOL eligible = cell && objc_getAssociatedObject(cell, &kWatchedMenuKey) == control
        && SGRIsTrackContent(cell.contentView.subviews.firstObject) && (SGRAlbumUsesSpotifyCounts() || album.length) && title.text.length
        && [control.accessibilityIdentifier hasPrefix:@"Components.UI.ContextMenuButton"] && [row isDescendantOfView:cell];
    if (!eligible) {
        objc_setAssociatedObject(control, &kWatchedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (cell && objc_getAssociatedObject(cell, &kWatchedMenuKey) == control) unwatch(cell);
        return;
    }
    if (SGRAlbumUsesSpotifyCounts()) {
        SGRAlbumPlaysMarkSpotifyMenu(SGRAlbumTrackURIFromMenuIdentifier(control.accessibilityIdentifier), spotifyCountsForPage(page));
    } else SGRAlbumPlaysMarkMenu(album, title.text);
}

%group SGRAlbumMenuActions
%hook UIControl
- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    markIfWatched(self);
    %orig;
}

- (void)sendAction:(UIAction *)action {
    markIfWatched(self);
    %orig;
}
%end
%end

static void watchMenu(UIView *cell, UIView *row) {
    UIView *menu = SGRFindByIdentifier(row, @"Components.UI.ContextMenuButton*", &kMenuKey);
    if (!menu) return;
    if (![menu isKindOfClass:UIControl.class]) {
        SGLogOnce(&sg_loggedMenus, NSStringFromClass(menu.class), @"redesign album: a track's ⋯ is a %@, not a control: its plays stay off its sheet");
        return;
    }
    // The cell holds its own descendant: no cycle.
    objc_setAssociatedObject(menu, &kWatchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(cell, &kWatchedMenuKey, menu, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// What a row's count narrowed, each label's frame before and after, to be put back.
@interface SGRCountChange : NSObject
@property (nonatomic, strong) UILabel *count;
@property (nonatomic, strong) NSMapTable<UILabel *, NSArray<NSValue *> *> *frames;
@end

@implementation SGRCountChange
@end

static BOOL restoreCount(UIView *cell) {
    SGRCountChange *change = objc_getAssociatedObject(cell, &kCountChangeKey);
    if (!change) return NO;
    objc_setAssociatedObject(cell, &kCountChangeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [change.count removeFromSuperview];
    // Only where the frame is still this change's: a pass of Spotify's since may have put its own there.
    for (UILabel *label in change.frames) {
        NSArray<NSValue *> *frames = [change.frames objectForKey:label];
        if (CGRectEqualToRect(label.frame, frames[1].CGRectValue)) label.frame = frames[0].CGRectValue;
    }
    return YES;
}

// Whether `view` draws, as far as its own and its ancestors' hidden and alpha say, up to `top`.
static BOOL shownUnder(UIView *view, UIView *top) {
    for (UIView *v = view; v && v != top; v = v.superview) {
        if (v.hidden || v.alpha < 0.01) return NO;
    }
    return YES;
}

// The box, in the row, of what trails its text: ⋯ and every control shown in the stack it sits in, each by its box as ⋯
// is. On a liked track that is the green check before ⋯ (Components.UI.AddToButton, in an element view of its own that
// Spotify hides on a track not liked), which the count was drawn over (issue #41).
static CGRect trailingFrameOf(UIView *menu, UIView *row) {
    __block CGRect frame = [menu.superview convertRect:menu.frame toView:row];
    UIView *stack = menu.superview;
    while (stack && stack != row && ![stack.accessibilityIdentifier isEqualToString:@"Encore.StackView"]) stack = stack.superview;
    if (!stack || stack == row) return frame;
    SGForEachView(stack, ^(UIView *v) {
        if (![v isKindOfClass:UIControl.class] || CGRectIsEmpty(v.bounds) || !shownUnder(v, stack)) return;
        frame = CGRectUnion(frame, [v.superview convertRect:v.frame toView:row]);
    });
    return frame;
}

static void applyCount(UIView *cell, UIView *row, UIView *page) {
    NSString *album = objc_getAssociatedObject(page, &kAlbumKey);
    BOOL spotify = SGRAlbumUsesSpotifyCounts();
    if (!album && !spotify) return;
    UILabel *title = titleOf(row);
    if (!title) return;
    UIView *menu = SGRFindByIdentifier(row, @"Components.UI.ContextMenuButton*", &kMenuKey);
    if (!menu || menu.alpha < 0.01 || CGRectIsEmpty(menu.bounds)) return;
    NSString *text;
    if (spotify) {
        SGRAlbumCountPage *state = spotifyCountsForPage(page);
        NSString *uri = SGRAlbumTrackURIFromMenuIdentifier(menu.accessibilityIdentifier);
        text = SGRAlbumSpotifyPlaysText(uri ? state.counts[uri] : nil);
    } else text = SGRAlbumPlaysText(SGRAlbumPlayCount(album, title.text));
    if (!text) return;
    if (!CGAffineTransformIsIdentity(title.transform) || title.layer.animationKeys.count) return;

    UILabel *count = objc_getAssociatedObject(cell, &kCountKey);
    if (!count) {
        count = [UILabel new];
        count.userInteractionEnabled = NO;
        count.isAccessibilityElement = NO;
        objc_setAssociatedObject(cell, &kCountKey, count, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // The row is measured for Spotify's fixed type, so the count grows with Dynamic Type only up to Large.
    count.font = SGMonospacedDigitsFont(SGCategoryCappedFont(UIFontTextStyleCaption1, UIFontWeightRegular, UIContentSizeCategoryLarge));
    count.textColor = SGRSecondary();
    count.text = text;
    CGSize size = [count sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
    size = CGSizeMake(ceil(size.width), ceil(size.height));

    BOOL rtl = row.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGRect trailing = trailingFrameOf(menu, row);
    CGFloat x = rtl ? CGRectGetMaxX(trailing) + kCountGap : CGRectGetMinX(trailing) - kCountGap - size.width;
    CGFloat scale = row.window.screen.scale ?: UIScreen.mainScreen.scale;
    CGFloat y = round((CGRectGetMidY(row.bounds) - size.height / 2) * scale) / scale;
    CGRect frame = CGRectMake(x, y, size.width, size.height);
    CGFloat limit = rtl ? CGRectGetMaxX(frame) + kCountTextGap : CGRectGetMinX(frame) - kCountTextGap;

    // The title and every label of the artist line kept clear of the count; a row with no room for the title
    // goes without it.
    NSMutableArray<UILabel *> *labels = [NSMutableArray arrayWithObject:title];
    SGForEachView(subtitleOf(row), ^(UIView *v) {
        if ([v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) [labels addObject:(UILabel *)v];
    });
    NSMapTable<UILabel *, NSArray<NSValue *> *> *frames = [NSMapTable weakToStrongObjectsMapTable];
    for (UILabel *label in labels) {
        CGRect inRow = [label.superview convertRect:label.frame toView:row];
        CGFloat over = rtl ? limit - CGRectGetMinX(inRow) : CGRectGetMaxX(inRow) - limit;
        if (over <= 0) continue;
        CGRect narrow = label.frame;
        narrow.size.width -= over;
        if (rtl) narrow.origin.x += over;
        if (label == title && narrow.size.width < title.font.lineHeight * 3) return;
        [frames setObject:@[[NSValue valueWithCGRect:label.frame], [NSValue valueWithCGRect:narrow]] forKey:label];
    }

    SGRCountChange *change = [SGRCountChange new];
    change.count = count;
    change.frames = frames;
    for (UILabel *label in frames) label.frame = [frames objectForKey:label][1].CGRectValue;
    count.frame = frame;
    [row addSubview:count];
    objc_setAssociatedObject(cell, &kCountChangeKey, change, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    static BOOL logged;
    if (!logged) {
        logged = YES;
        SGLog(@"redesign album: a track's plays shown, %@, %lu label(s) narrowed", text, (unsigned long)frames.count);
    }
}

#pragma mark - the ⋯

// The ⋯'s tint in OKLab: its lightness, with Increase Contrast too, and the most chroma it takes from the page.
static const CGFloat kMoreLightness = 0.80, kMoreLightnessContrast = 0.88, kMoreMaxChroma = 0.08;

static char kMoreKey, kMoreColourKey, kMoreWatchedKey;

// The pages whose rows have drawn a ⋯, laid out again when what it is drawn in changes (the %ctor).
static NSHashTable<UIView *> *morePages(void) {
    static NSHashTable<UIView *> *pages;
    if (!pages) pages = [NSHashTable weakObjectsHashTable];
    return pages;
}

// A page's ⋯ tint, with the field colour and the contrast it was made for.
@interface SGRMoreColour : NSObject
@property (nonatomic, strong) UIColor *field, *tint;
@property (nonatomic) BOOL contrast;
@end

@implementation SGRMoreColour
@end

static UIColor *moreColourOf(UIView *page) {
    UIColor *field = SGRAlbumFieldColor(page);
    BOOL contrast = SGRIncreaseContrast();
    SGRMoreColour *kept = objc_getAssociatedObject(page, &kMoreColourKey);
    if (kept && kept.contrast == contrast && [kept.field isEqual:field]) return kept.tint;
    kept = [SGRMoreColour new];
    kept.field = field;
    kept.contrast = contrast;
    CGFloat red, green, blue, alpha;
    if ([field getRed:&red green:&green blue:&blue alpha:&alpha]) {
        SGRLab lab = SGRLabFromRGB(red, green, blue);
        CGFloat chroma = MIN(hypot(lab.a, lab.b), kMoreMaxChroma), hue = atan2(lab.b, lab.a);
        // Brought into sRGB by its chroma alone: a light tint of a saturated page is past sRGB's edge, and clamping it
        // there lightened it.
        SGRLabToRGB(SGRLabInSRGB(contrast ? kMoreLightnessContrast : kMoreLightness, chroma, hue), &red, &green, &blue);
        kept.tint = [UIColor colorWithRed:red green:green blue:blue alpha:1];
    } else kept.tint = SGRSecondary();
    objc_setAssociatedObject(page, &kMoreColourKey, kept, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return kept.tint;
}

// What a row's ⋯ was given, for the picture it was given it for: a template glyph's tint (and Spotify's before it), or
// the colour over a baked one and the empty mask hiding the glyph's own paint.
@interface SGRMoreTint : NSObject
@property (nonatomic, weak) UIImageView *glyph;
@property (nonatomic, strong) UIImage *image;
// The tint set, and what the glyph read back right after (UIKit raises a tint itself for Increase Contrast).
@property (nonatomic, strong) UIColor *tint, *shownTint, *spotifyTint;
@property (nonatomic, strong) CALayer *overlay, *hider;
@end

@implementation SGRMoreTint
@end

static void restoreMore(UIView *cell) {
    SGRMoreTint *kept = objc_getAssociatedObject(cell, &kMoreKey);
    if (!kept) return;
    objc_setAssociatedObject(cell, &kMoreKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIImageView *glyph = kept.glyph;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [kept.overlay removeFromSuperlayer];
    if (kept.hider && glyph.layer.mask == kept.hider) glyph.layer.mask = nil;
    if (kept.shownTint && [glyph.tintColor isEqual:kept.shownTint]) glyph.tintColor = kept.spotifyTint;
    [CATransaction commit];
}

static UIImageView *glyphOf(UIView *menu) {
    __block UIImageView *glyph = nil;
    SGForEachView(menu, ^(UIView *v) {
        if (!glyph && [v isKindOfClass:UIImageView.class]) glyph = (UIImageView *)v;
    });
    return glyph;
}

// A symbol picture left to the image view draws in its tint, as one made a template does.
static BOOL isTemplate(UIImage *image) {
    return image.renderingMode == UIImageRenderingModeAlwaysTemplate
        || (image.renderingMode == UIImageRenderingModeAutomatic && image.isSymbolImage);
}

static void applyMore(UIView *cell, UIView *row, UIView *page) {
    [morePages() addObject:page];
    UIView *menu = SGRFindByIdentifier(row, @"Components.UI.ContextMenuButton*", &kMenuKey);
    [menu layoutIfNeeded];
    UIImageView *glyph = menu ? glyphOf(menu) : nil;
    UIImage *image = glyph.image;
    SGRMoreTint *kept = objc_getAssociatedObject(cell, &kMoreKey);
    if (kept && (kept.glyph != glyph || kept.image != image)) {
        restoreMore(cell);
        kept = nil;
    }
    if (!glyph) return;
    // A picture that lands, or replaces the one drawn over, without a pass of the row's.
    if (objc_getAssociatedObject(cell, &kMoreWatchedKey) != glyph) {
        objc_setAssociatedObject(cell, &kMoreWatchedKey, glyph, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak UIView *weakCell = cell;
        SGRObserveImage(glyph, ^(UIImageView *view) { [weakCell setNeedsLayout]; });
    }
    BOOL template = isTemplate(image);
    BOOL foreignMask = glyph.layer.mask && glyph.layer.mask != kept.hider;
    if (!image || glyph.hidden || UIApplication.sharedApplication.applicationState != UIApplicationStateActive
        || (!template && (!image.CGImage || foreignMask))) {
        restoreMore(cell);
        return;
    }
    if (!kept) {
        kept = [SGRMoreTint new];
        kept.glyph = glyph;
        kept.image = image;
        objc_setAssociatedObject(cell, &kMoreKey, kept, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIColor *tint = moreColourOf(page);
    if (template) {
        BOOL ours = kept.shownTint && [glyph.tintColor isEqual:kept.shownTint];
        if (ours && [kept.tint isEqual:tint]) return;
        // Spotify's own tint, kept to be put back; one it set since this file's is the one now.
        if (!ours) kept.spotifyTint = glyph.tintColor;
        kept.tint = tint;
        glyph.tintColor = tint;
        kept.shownTint = glyph.tintColor;
        return;
    }
    CALayer *source = glyph.layer, *overlay = kept.overlay;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (!overlay) {
        overlay = kept.overlay = [CALayer layer];
        overlay.mask = [CALayer layer];
        kept.hider = [CALayer layer];
    }
    CALayer *shape = overlay.mask;
    if (shape.contents != (__bridge id)image.CGImage) shape.contents = (__bridge id)image.CGImage;
    if (shape.contentsScale != image.scale) shape.contentsScale = image.scale;
    if (![shape.contentsGravity isEqualToString:source.contentsGravity]) shape.contentsGravity = source.contentsGravity;
    if (!CGRectEqualToRect(overlay.bounds, source.bounds)) overlay.bounds = shape.frame = source.bounds;
    if (!CGPointEqualToPoint(overlay.anchorPoint, source.anchorPoint)) overlay.anchorPoint = source.anchorPoint;
    if (!CGPointEqualToPoint(overlay.position, source.position)) overlay.position = source.position;
    if (!CATransform3DEqualToTransform(overlay.transform, source.transform)) overlay.transform = source.transform;
    if (overlay.opacity != source.opacity) overlay.opacity = source.opacity;
    if (!CGColorEqualToColor(overlay.backgroundColor, tint.CGColor)) overlay.backgroundColor = tint.CGColor;
    if (overlay.superlayer != source.superlayer) [source.superlayer insertSublayer:overlay above:source];
    if (source.mask != kept.hider) source.mask = kept.hider;
    [CATransaction commit];
}

#pragma mark - the rows

// Layout coordinates, independent of the vertical transform that belongs to the credit change.
typedef struct { CGPoint center; CGRect bounds; } SGRTitleGeometry;

static SGRTitleGeometry titleGeometry(UILabel *title) {
    return (SGRTitleGeometry){title.center, title.bounds};
}

static BOOL hasTitleGeometry(UILabel *title, SGRTitleGeometry geometry) {
    return CGPointEqualToPoint(title.center, geometry.center) && CGRectEqualToRect(title.bounds, geometry.bounds);
}

static void setTitleGeometry(UILabel *title, SGRTitleGeometry geometry) {
    title.bounds = geometry.bounds;
    title.center = geometry.center;
}

@interface SGROrdinal : UILabel
@property (nonatomic, weak) UILabel *titleLabel;
@property (nonatomic, weak) UIView *observedOwner;
@property (nonatomic) SGRTitleGeometry original, inset, settled;
@property (nonatomic) CGSize ownerSize;
@end
@implementation SGROrdinal
@end

static char kOrdinal;
static void restoreOrdinal(UIView *cell) {
    SGROrdinal *number = objc_getAssociatedObject(cell, &kOrdinal);
    if (!number.superview) return;
    if (hasTitleGeometry(number.titleLabel, number.inset))
        setTitleGeometry(number.titleLabel, number.original);
    number.titleLabel = nil;
    [number removeFromSuperview];
}

static SGROrdinal *applyOrdinal(UIView *cell, UIView *row, UIView *page) {
    SGRAlbumTrackIndex *index = objc_getAssociatedObject(page, &kTrackIndex);
    if (!index) return nil;
    UILabel *title = titleOf(row);
    if (!title.text.length || !CGAffineTransformIsIdentity(title.transform)) return nil;
    UIView *menu = SGRFindByIdentifier(row, @"Components.UI.ContextMenuButton*", &kMenuKey);
    NSString *uri = SGRAlbumTrackURIFromMenuIdentifier(menu.accessibilityIdentifier);
    NSNumber *position = [index numberForURI:uri title:title.text];
    if (!position) return nil;
    SGROrdinal *number = objc_getAssociatedObject(cell, &kOrdinal);
    if (!number) {
        number = [SGROrdinal new];
        number.userInteractionEnabled = number.isAccessibilityElement = NO;
        objc_setAssociatedObject(cell, &kOrdinal, number, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    number.text = position.stringValue;
    number.font = SGMonospacedDigitsFont(title.font);
    number.textColor = title.textColor;
    number.alpha = title.alpha;
    CGFloat width = ceil(number.intrinsicContentSize.width), lead = width + 6;
    CGRect frame = title.frame;
    if (frame.size.width <= lead) return nil;
    BOOL rtl = row.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    number.original = titleGeometry(title);
    CGRect inRow = [title.superview convertRect:frame toView:row];
    number.frame = CGRectMake(rtl ? CGRectGetMaxX(inRow) - width : CGRectGetMinX(inRow), inRow.origin.y, width, inRow.size.height);
    frame.size.width -= lead;
    if (!rtl) frame.origin.x += lead;
    title.frame = frame; // Identity transform here, before applyCredit.
    number.inset = titleGeometry(title);
    [row addSubview:number];
    number.titleLabel = title;
    return number;
}

static void applyRow(UIView *cell, UIView *page) {
    clearSurface(cell);
    UIView *row = SGRFindByIdentifier(cell, @"Components.UI.RetrievalRow*", &kRowKey);
    if (!row) {
        restoreMore(cell);
        return;
    }
    // The row, and every box the element framework wraps it in on the way back up to the cell.
    for (UIView *v = row; v; v = v.superview) {
        clearSurface(v);
        if (v == cell) break;
    }

    UIView *subtitle = SGRFindByIdentifier(row, @"EncoreConsumerMobile.View.Granular.Subtitle", &kSubtitleKey);
    SGForEachView(subtitle, ^(UIView *v) {
        if (![v isKindOfClass:UILabel.class]) return;
        UILabel *label = (UILabel *)v;
        if (![label.textColor isEqual:SGRSecondary()]) label.textColor = SGRSecondary();
    });

    applyHairline(row);
    offerMotionRow((UICollectionViewCell *)cell, row, page);
    // Settle Spotify's text constraints once, before any decorator measures or insets the title.
    if (sg_trackNumbers || hidesCredits() || countsPlace() == SGRAlbumPlayCountsInRow)
        [((UICollectionViewCell *)cell).contentView layoutIfNeeded];
    if (countsPlace() == SGRAlbumPlayCountsInRow) applyCount(cell, row, page);
    else if (countsPlace() == SGRAlbumPlayCountsInMenu) watchMenu(cell, row);
    SGROrdinal *number = sg_trackNumbers ? applyOrdinal(cell, row, page) : nil;
    if (hidesCredits()) applyCredit(cell, row, page);
    if (number) {
        UILabel *title = number.titleLabel;
        number.center = CGPointMake(number.center.x, CGRectGetMidY([title convertRect:title.bounds toView:row]));
        // The Encore label wrapper lays its UILabel out again independently of the cell.
        // Keep the final box (including credit/badge and count geometry), not another
        // incremental inset. Reuse clears titleLabel before the next row takes ownership.
        number.settled = titleGeometry(title);
        number.ownerSize = title.superview.bounds.size;
        if (number.observedOwner != title.superview) {
            __weak SGROrdinal *weakNumber = number;
            __weak UIView *weakCell = cell;
            if (SGRObserveLayout(title.superview, ^(UIView *owner) {
                SGROrdinal *active = weakNumber;
                UILabel *label = active.titleLabel;
                if (label.superview != owner) return;
                if (!CGSizeEqualToSize(owner.bounds.size, active.ownerSize)) {
                    [weakCell setNeedsLayout];
                } else if (!hasTitleGeometry(label, active.settled))
                    setTitleGeometry(label, active.settled);
            })) number.observedOwner = title.superview;
        }
    }
    applyMore(cell, row, page);
}

#pragma mark - the cells

// As for album notes, a valid index path during a reload/batch can still name the
// previous snapshot. Track the album list itself, including when editorial notes are off.
static void motionBatch(UICollectionView *list, NSInteger delta) {
    NSInteger depth = [objc_getAssociatedObject(list, &kMotionBatchDepth) integerValue] + delta;
    objc_setAssociatedObject(list, &kMotionBatchDepth, depth ? @(depth) : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!depth && objc_getAssociatedObject(SGRAlbumPageOf(list), &kMotionRowKey))
        for (UICollectionViewCell *cell in list.visibleCells) [cell setNeedsLayout];
}

%group SGRAlbumCollectionHooks
%hook SGRAlbumCollection
- (void)layoutSubviews {
    UICollectionView *list = (id)self;
    UIView *page = SGRAlbumPageOf(list.superview);
    if (page) bindMotionOwner(page, list);
    %orig;
}
- (void)reloadData {
    motionBatch((id)self, 1);
    %orig;
    motionBatch((id)self, -1);
}
- (void)performBatchUpdates:(void (^)(void))updates completion:(void (^)(BOOL))completion {
    UICollectionView *list = (id)self;
    motionBatch(list, 1);
    %orig(updates, ^(BOOL finished) { motionBatch(list, -1); if (completion) completion(finished); });
}
%end
%end

%hook _TtC12Element_List18CollectionViewCell
- (void)layoutSubviews {
    // In the reverse of the order they were made: the artist line's change measured the narrowed title.
    restoreCredit((UIView *)self);
    if (sg_trackNumbers) restoreOrdinal((UIView *)self);
    restoreCount((UIView *)self);
    // Flagged again below while it is still an album's track row.
    unwatch((UIView *)self);
    %orig;
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    UIView *page = SGRIsTrackContent(cell.contentView.subviews.firstObject) ? SGRAlbumPageOf(cell) : nil;
    if (page) applyRow(cell, page);
    else restoreMore(cell);
    // A pass that draws no badge drops the picture the last one kept.
    if (!((SGRCreditChange *)objc_getAssociatedObject(cell, &kChangeKey)).drawnBadge) dropDrawnBadge(cell);
}

- (void)prepareForReuse {
    %orig;
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    unwatch(cell);
    dropDrawnBadge(cell);
    BOOL changed = restoreCredit(cell);
    if (sg_trackNumbers) restoreOrdinal(cell);
    changed = restoreCount(cell) || changed;
    if (changed || SGRIsTrackContent(cell.contentView.subviews.firstObject)) [cell setNeedsLayout];
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    sg_trackNumbers = SGFlag(SGRKeyAlbumTrackNumbers, NO);
    %init;
    Class list = SGFileprivateViewClass("_TtC32CreativeWorkPlatform_TemplateKitP33_5F894CA2C02A3F3767683E90D6AA015014CollectionView", UICollectionView.class);
    if (list) %init(SGRAlbumCollectionHooks, SGRAlbumCollection = list);
    if (countsPlace() == SGRAlbumPlayCountsInMenu) %init(SGRAlbumMenuActions);
    if (countsPlace() == SGRAlbumPlayCountsInRow) {
        // Posted on the main thread (AlbumPlays.m).
        [NSNotificationCenter.defaultCenter addObserverForName:SGRAlbumPlayCountsDidChangeNotification object:nil
                                                         queue:nil usingBlock:^(NSNotification *note) {
            for (UIView *page in countedPages().allObjects) layOutRowsAgain(page);
        }];
    }
    // What the ⋯ is drawn in: the page's colour, read after its rows have laid out, and Increase Contrast; and a pass
    // while the app was not active, which drew Spotify's own. All three are posted on the main thread.
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:SGRFieldColorDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        UIView *page = SGRAlbumPageOf(note.object);
        if ([morePages() containsObject:page]) layOutRowsAgain(page);
    }];
    for (NSNotificationName name in @[UIAccessibilityDarkerSystemColorsStatusDidChangeNotification, UIApplicationDidBecomeActiveNotification]) {
        [center addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            for (UIView *page in morePages().allObjects) layOutRowsAgain(page);
        }];
    }
    SGRequireClasses(@[@"_TtC12Element_List18CollectionViewCell"]);
}
