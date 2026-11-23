// Album: hides parts of the album page, one switch each in Mod Settings > Home & Library > Album,
// and puts the blurred cover behind its header.
//
// Trees (trees/continuous/*.txt): the page is a CreativeWorkTemplateView with that identifier (the
// artist page is TemplateKit's TemplateView instead). Its first child is the header's background,
// a HeaderView holding Spotify's GradientView; the header itself scrolls with the list, its buttons
// one UIStackView of element views, each holding a button with an accessibility identifier.
//
// Below the tracks every row is an Element_List cell, sectioned the way Artist/Artist.x describes: a
// heading cell (SectionHeadingHome), the carousel or card, a 16pt spacer. The copyright closes the
// page right after the last section, so it counts as a heading of its own and stays.
// More by, Merch and You might also like have confirmed Korean headings too.
#import "Core/SGCore.h"
#import "Album.h"
#import "Native/Declutter/Declutter.h"
#import "Native/Appearance/HeaderBackdrop.h"

static NSString *const kTemplate = @"CreativeWorkPlatform.CreativeWorkTemplateView";

static UIView *albumPageOf(UIView *view) {
    for (UIView *v = view.superview; v; v = v.superview) {
        if ([v.accessibilityIdentifier isEqualToString:kTemplate]) return v;
    }
    return nil;
}

#pragma mark - header buttons

static const struct { __unsafe_unretained NSString *ident, *key; } buttons[] = {
    {@"Components.UI.WatchFeedEntityExplorerButton", SGHideAlbumExplore},
    {@"Components.UI.AddToButton", SGHideAlbumAddTo},
    {@"DownloadButton.Granular", SGHideAlbumDownload},
    {@"Components.UI.ContextMenuButton", SGHideAlbumMore},
};

static NSString *keyFor(UIView *action) {
    NSString *ident = action.subviews.firstObject.accessibilityIdentifier;
    for (size_t i = 0; ident && i < sizeof(buttons) / sizeof(buttons[0]); i++) {
        if ([ident hasPrefix:buttons[i].ident]) return buttons[i].key;
    }
    return nil;
}

static BOOL buttonHidden(UIView *action) {
    NSString *key = keyFor(action);
    return key && SGHidden(key);
}

// The buttons arrive after the page has laid out, and a row that keeps its size lays nothing else out.
%hook UIStackView
- (void)layoutSubviews {
    %orig;
    BOOL any = NO;
    for (UIView *action in self.subviews) {
        if ((any = buttonHidden(action))) break;
    }
    if (!any || !albumPageOf(self)) return;
    for (UIView *action in self.subviews) {
        if (buttonHidden(action)) action.hidden = YES;
    }
}
%end

#pragma mark - the cover behind the header

static char kBackdropKey, kSourceKey, kArtworkKey;

static void applyBackdrop(UIView *page) {
    if (!SGFlag(SGKeyAlbumBackdrop, NO)) return;
    __block UIImage *image = nil;
    SGForEachView(SGFindIdentifier(page, @"CreativeWorkPlatform.Components.UI.ArtWorkElement.WithCoverArt", &kArtworkKey), ^(UIView *v) {
        if (!image && [v isKindOfClass:UIImageView.class]) image = ((UIImageView *)v).image;
    });
    UIView *header = page.subviews.firstObject;
    if (!image || !SGClassNamed(header.class, @"HeaderView")) return;

    SGNativeHeaderBackdrop(header, image, &kBackdropKey, &kSourceKey);
}

%hook _TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView
- (void)layoutSubviews {
    %orig;
    applyBackdrop((UIView *)self);
}
%end

// The cover loads after the page is laid out, and a new image lays nothing out. Only the 248pt
// cover is wide enough to be worth walking up from.
%hook UIImageView
- (void)setImage:(UIImage *)image {
    %orig;
    if (!image || self.bounds.size.width < 200 || !SGFlag(SGKeyAlbumBackdrop, NO)) return;
    UIView *page = albumPageOf(self);
    if (page) applyBackdrop(page);
}
%end

#pragma mark - sections

static const SGNativeSectionRule sections[] = {
    {@"More by ", SGHideAlbumMoreBy, YES},
    {@"Related Music Videos", SGHideAlbumVideos, NO},
    {@"Concerts", SGHideAlbumConcerts, NO},
    {@"Merch", SGHideAlbumMerch, NO},
    {@"You might also like", SGHideAlbumYouMightLike, NO},
    {@"의 곡 더 보기", SGHideAlbumMoreBy, NO, YES},
    {@"콘서트", SGHideAlbumConcerts, NO},
    {@"굿즈", SGHideAlbumMerch, NO},
    {@"이건 어떠세요", SGHideAlbumYouMightLike, NO},
};

enum { kSections = sizeof(sections) / sizeof(sections[0]) };

// The heading's title, the copyright's identifier, or @"" for any other cell.
static NSString *headingIn(UIView *cell) {
    __block NSString *title = nil;
    SGForEachView(cell, ^(UIView *v) {
        if (title) return;
        if ([v.accessibilityIdentifier isEqualToString:@"Album.Copyright"]) title = v.accessibilityIdentifier;
        else if (SGClassNamed(v.class, @"SectionHeadingHome") && v.accessibilityLabel.length) title = v.accessibilityLabel;
    });
    return title ?: @"";
}

static BOOL collapsed(UICollectionViewCell *cell, NSIndexPath *path) {
    if (!path || !SGNativeAnySectionHidden(sections, kSections)) return NO;
    UICollectionView *list = nil;
    for (UIView *v = cell.superview; v; v = v.superview) {
        if ([v isKindOfClass:cell.class]) return NO;   // a card inside a carousel: its row decides
        if (!list && [v isKindOfClass:UICollectionView.class]) list = (UICollectionView *)v;
    }
    if (!list || !albumPageOf(list)) return NO;
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
    return result;
}
%end

%ctor {
    if (!SGNativeUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView",
        @"_TtC12Element_List18CollectionViewCell",
    ]);
}
