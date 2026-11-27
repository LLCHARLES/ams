// The header's text and controls, the redesign's own. Laid out top down from where the content has to start
// for its bottom to sit SGRHeaderInfoBottom above the view's.
#import "Core/SGCore.h"
#import "SGRHeaderInfo.h"
#import "SGRActionRow.h"
#import "SGRRestyle.h"
#import "SGRTokens.h"
#import "Redesigned/Album/SGRCoverBeside.h"

const CGFloat SGRHeaderInfoBottom = 14;
const CGFloat SGRHeaderInfoTitleRise = 56;

BOOL SGRPageFullCover(NSString *key) {
    NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
    id legacy = [prefs objectForKey:SGRKeyFullBleedCovers];
    if (![prefs boolForKey:SGRKeyFullCoverMigrated]) {
        if (legacy) {
            for (NSString *destination in @[SGRKeyAlbumFullCover, SGRKeyPlaylistFullCover]) {
                if (![prefs objectForKey:destination]) [prefs setObject:legacy forKey:destination];
            }
        }
        // Older builds still own this key. Keep it unchanged for rollback, but never consult it again.
        [prefs setBool:YES forKey:SGRKeyFullCoverMigrated];
        SGPrefsChanged();
    }
    // Unset, an album's static cover is the Music app's centred card (its animated cover fills the hero either way);
    // a playlist's picture is full screen.
    return SGFlag(key, ![key isEqualToString:SGRKeyAlbumFullCover]);
}

static BOOL playInPageColour(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ on = SGEnabled(SGRKeyPlayInPageColour); });
    return on;
}

static BOOL cutOutPlay(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ on = SGFlag(SGRKeyArtistCutOutPlay, NO); });
    return on;
}

static BOOL accentPlay(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ on = SGFlag(SGRKeyAccentPlay, NO); });
    return on;
}

// The text kSide in from the edges; Play at least kPlayWidth wide, the Music app's; the gaps between.
static const CGFloat kSide = 20, kPlayWidth = 148, kRowSpacing = 16, kRowAbove = 16, kAboutAbove = 14;
// Round Play: the row as tall as the circle, and the round buttons either side this far off it.
static const CGFloat kRoundRow = 64, kRoundSpacing = 20;
// The pinned top bar under the top safe area, how far past its line the content goes before it is clipped, and how
// far under the line the clip fades in, clear at the line and opaque from there.
static const CGFloat kTopBar = 44, kUnderBar = 0.5, kBarFade = 14;
static void *kClipScrollContext = &kClipScrollContext;

// The title, the creator, the length and the description, in the Music app's sizes (iOS 26.4): the title Title2 bold,
// the creator about the title's size (Title3) regular, the metadata Caption1 semibold, the description Footnote.
typedef NS_ENUM(NSUInteger, SGRInfoLine) { SGRInfoTitle, SGRInfoCreator, SGRInfoLength, SGRInfoAbout };
static UIFontTextStyle infoStyle(SGRInfoLine line) {
    return @[UIFontTextStyleTitle2, UIFontTextStyleTitle3, UIFontTextStyleCaption1, UIFontTextStyleFootnote][line];
}
static UIFontWeight infoWeight(SGRInfoLine line) {
    return line == SGRInfoTitle ? UIFontWeightBold : line == SGRInfoLength ? UIFontWeightSemibold : UIFontWeightRegular;
}
static UIFont *infoFont(SGRInfoLine line) {
    return SGCategoryCappedFont(infoStyle(line), infoWeight(line), UIContentSizeCategoryExtraLarge);
}

static UILabel *infoLabel(UIView *parent, UIFont *font, UIColor *color, NSInteger lines, NSTextAlignment alignment) {
    UILabel *label = [UILabel new];
    label.font = font;
    label.textColor = color;
    label.numberOfLines = lines;
    label.textAlignment = alignment;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.hidden = YES;
    [parent addSubview:label];
    return label;
}

static BOOL setText(UILabel *label, NSString *text) {
    if ([label.text ?: @"" isEqualToString:text ?: @""]) return NO;
    label.text = text;
    label.hidden = text.length == 0;
    return YES;
}

// The most a title picture takes: a share of the text's width, and a height near three lines of the title.
static const CGFloat kLogoWidthShare = 0.8, kLogoMaxHeight = 64;
// Between the creator's picture and the name.
static const CGFloat kPictureGap = 8;

// A face is at least this wide, and square give or take a point.
static const CGFloat kMinFace = 16;
// The creator's faces (-showCreatorFaces:from:): how many at most, the most a circle is across, how far on each next one
// starts as a share of that, and the clear ring cut around the one before out of it.
static const NSUInteger kMaxFaces = 3;
static const CGFloat kMaxFaceSide = 22, kFaceStep = 0.85, kFaceRing = 1.5;

static BOOL squareFace(UIView *v) {
    CGSize size = v.bounds.size;
    return size.width >= kMinFace && fabs(size.width - size.height) <= 1;
}

static BOOL faceSized(UIView *v) {
    return [v isKindOfClass:UIImageView.class] && squareFace(v);
}

// The avatar an image view on Spotify's creator line draws a face in: the outermost of the square views running up from
// it, short of `root`. Spotify's avatar is a square that clips the picture (which may be wider than it, a portrait
// filled across it) and holds the artist's initial under it; the image view counts as its own avatar only when it is
// square itself. nil when neither it nor the view it sits in is a face's square.
static UIView *avatarOf(UIImageView *image, UIView *root) {
    UIView *avatar = squareFace(image) ? image : nil;
    for (UIView *up = image.superview; up && up != root && squareFace(up); up = up.superview) avatar = up;
    return avatar;
}

// Where `v` starts in `root`, on the side a line in its direction starts from.
static CGFloat leadingEdge(UIView *v, UIView *root, BOOL rtl) {
    return [v convertPoint:CGPointMake(rtl ? v.bounds.size.width : 0, 0) toView:root].x;
}

UIImageView *SGRCreatorPicture(UIView *root) {
    if (!root) return nil;
    // The faces of a facepile overlap, the leading one first to the eye.
    BOOL rtl = root.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    __block UIImageView *found = nil;
    __block CGFloat edge = 0;
    SGForEachView(root, ^(UIView *v) {
        if (!faceSized(v)) return;
        CGFloat x = leadingEdge(v, root, rtl);
        if (!found || (rtl ? x > edge : x < edge)) found = (UIImageView *)v, edge = x;
    });
    return found;
}

static BOOL shownIn(UIView *v, UIView *root) {
    for (UIView *up = v; up; up = up.superview) {
        if (up.hidden || up.alpha < 0.01) return NO;
        if (up == root) return YES;
    }
    return NO;
}

NSArray<UIImageView *> *SGRCreatorFaces(UIView *root) {
    if (!root) return @[];
    BOOL rtl = root.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    // Every avatar, its picture shown or not, so its initial is never the name; and each one with a shown image view,
    // the first of them, its face.
    NSHashTable<UIView *> *avatars = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    NSMapTable<UIView *, UIImageView *> *shownFaces = [NSMapTable strongToStrongObjectsMapTable];
    NSMutableArray<UIView *> *found = [NSMutableArray array];
    SGForEachView(root, ^(UIView *v) {
        if (![v isKindOfClass:UIImageView.class]) return;
        UIView *avatar = avatarOf((UIImageView *)v, root);
        if (!avatar) return;
        [avatars addObject:avatar];
        if (!shownIn(v, root) || [shownFaces objectForKey:avatar]) return;
        [shownFaces setObject:(UIImageView *)v forKey:avatar];
        [found addObject:avatar];
    });
    // The name: the first label shown with text that is not an avatar's initial.
    __block UILabel *name = nil;
    SGForEachView(root, ^(UIView *v) {
        if (name || ![v isKindOfClass:UILabel.class] || !shownIn(v, root)) return;
        for (UIView *up = v.superview; up && up != root; up = up.superview) {
            if ([avatars containsObject:up]) return;
        }
        if ([((UILabel *)v).text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) name = (UILabel *)v;
    });
    // With no name shown there is nothing to tell a face from a badge after it by: none.
    if (!name) return @[];
    CGFloat nameEdge = leadingEdge(name, root, rtl);
    NSMutableArray<UIImageView *> *faces = [NSMutableArray array];
    NSMapTable<UIView *, NSNumber *> *edges = [NSMapTable strongToStrongObjectsMapTable];
    for (UIView *avatar in found) {
        CGFloat x = leadingEdge(avatar, root, rtl);
        if (rtl ? x <= nameEdge : x >= nameEdge) continue;
        UIImageView *face = [shownFaces objectForKey:avatar];
        [faces addObject:face];
        [edges setObject:@(x) forKey:face];
    }
    return [faces sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(UIView *one, UIView *other) {
        NSComparisonResult order = [[edges objectForKey:one] compare:[edges objectForKey:other]];
        return rtl ? -order : order;
    }];
}

@implementation SGRHeaderInfo {
    UILabel *_title, *_creator, *_length, *_about;
    UIImageView *_logo;
    UIImageView *_picture;   // the creator's, round, before the name
    __weak UIImageView *_pictureSource;
    // The creator's faces (-showCreatorFaces:from:), made with the first of them: the circles in a view of their own
    // before the name, Spotify's image views they are read from (weakly), the line and the name they belong to, and the
    // pictures they show. A rebuild is pending while facesPending is set.
    UIView *_faces;
    NSPointerArray *_faceSources;
    __weak UIView *_faceParent;
    NSString *_faceName;
    NSArray<UIImage *> *_faceImages;
    BOOL _facesPending;
    // What the faces' circles and cut rings were last made for (-sgr_placeFaces:rtl:).
    CGFloat _placedSide, _placedStep;
    BOOL _placedRTL;
    NSUInteger _placedCount;
    UIImage *_titleImage;   // what the title's place is laid out for; the logo keeps its picture while it fades out
    SGRMirrorButton *_shuffle, *_trailing;
    SGRPlayCapsule *_play;
    __weak UIView *_creatorLink;
    // The lines measured at each text width a pass asks at (-sgr_linesAt:). Emptied when what they are measured from
    // changes: the text, the fonts, the title picture, the creator's picture or faces.
    NSMutableDictionary<NSNumber *, NSArray<NSValue *> *> *_lines;
    // Where the content starts, as last laid out; and the mask that clips it under the top bar (-clipUnderTopBar).
    CGFloat _contentTop;
    CAGradientLayer *_barClip;
    BOOL _clipsUnderBar;
    __weak UIScrollView *_clipScroll;
    BOOL _beside, _besideFonts;
    // Laid out once at a size: until then every pass runs outside any animation (-layoutSubviews).
    BOOL _laidOut;
    __weak UIView *_besideMore, *_besideDownload;
    __weak UIView *_morePage, *_downloadPage;
    dispatch_block_t _besideRefresh;
    id _besideDefaultsObserver, _besideTextObserver;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _lines = [NSMutableDictionary dictionary];
    _title = infoLabel(self, infoFont(SGRInfoTitle), SGRPrimary(), 2, NSTextAlignmentCenter);
    _title.accessibilityTraits = UIAccessibilityTraitHeader;
    _creator = infoLabel(self, infoFont(SGRInfoCreator), SGRSecondary(), 1, NSTextAlignmentCenter);
    _length = infoLabel(self, infoFont(SGRInfoLength), SGRSecondary(), 1, NSTextAlignmentCenter);
    _about = infoLabel(self, infoFont(SGRInfoAbout), SGRSecondary(), 2, NSTextAlignmentNatural);
    _picture = [UIImageView new];
    _picture.contentMode = UIViewContentModeScaleAspectFill;
    _picture.clipsToBounds = YES;
    _picture.hidden = YES;
    [self addSubview:_picture];

    _shuffle = [[SGRMirrorButton alloc] initWithFrame:CGRectZero];
    _shuffle.fallbackGlyph = [UIImage systemImageNamed:@"shuffle"];
    // White like the buttons beside it while off -- Spotify's off gray read as a disabled button next to the
    // white download (issue #65) -- and the accent while on, so its state still shows.
    _shuffle.glyphColor = SGRPrimary();
    _shuffle.onGlyphColor = SGRAccent();
    _play = [[SGRPlayCapsule alloc] initWithFrame:CGRectZero];
    [self sgr_fillPlay];
    _trailing = [[SGRMirrorButton alloc] initWithFrame:CGRectZero];
    for (UIView *button in @[_shuffle, _play, _trailing]) {
        button.hidden = YES;
        [self addSubview:button];
    }
    return self;
}

- (BOOL)sgr_coverBeside { return _beside; }

- (void)dealloc {
    [_clipScroll removeObserver:self forKeyPath:@"contentOffset" context:kClipScrollContext];
    if (_besideDefaultsObserver) [NSNotificationCenter.defaultCenter removeObserver:_besideDefaultsObserver];
    if (_besideTextObserver) [NSNotificationCenter.defaultCenter removeObserver:_besideTextObserver];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    BOOL textSize = ![previous.preferredContentSizeCategory isEqual:self.traitCollection.preferredContentSizeCategory];
    // The fonts are made at the text size they were made at, beside the cover or stacked: made again at the new one.
    if (textSize) {
        [self sgr_besideTypography:_besideFonts traits:self.traitCollection];
        [self setNeedsLayout];
    }
    if (_besideRefresh && (textSize || previous.horizontalSizeClass != self.traitCollection.horizontalSizeClass)) _besideRefresh();
}

// The stacked title's: the artist's Large Title (largeTitle) or Title 2, capped with the rest.
- (UIFont *)sgr_stackedTitleFont {
    return _largeTitle ? SGCategoryCappedFont(UIFontTextStyleLargeTitle, UIFontWeightBold, UIContentSizeCategoryExtraLarge)
                       : infoFont(SGRInfoTitle);
}

- (void)sgr_besideTypography:(BOOL)beside traits:(UITraitCollection *)traits {
    NSArray<UILabel *> *labels = @[_title, _creator, _length, _about];
    BOOL changed = NO;
    for (SGRInfoLine i = SGRInfoTitle; i < labels.count; i++) {
        UILabel *label = labels[i];
        UIFont *font;
        NSInteger lines;
        if (beside) {
            UIFont *preferred = [UIFont preferredFontForTextStyle:infoStyle(i) compatibleWithTraitCollection:traits];
            font = [UIFont systemFontOfSize:preferred.pointSize weight:infoWeight(i)];
            lines = 0;
        } else {
            font = i == SGRInfoTitle ? [self sgr_stackedTitleFont] : infoFont(i);
            lines = i == SGRInfoTitle || i == SGRInfoAbout ? 2 : 1;
        }
        if ([label.font isEqual:font] && label.numberOfLines == lines) continue;
        label.font = font;
        label.numberOfLines = lines;
        changed = YES;
    }
    _besideFonts = beside;
    // A page hands the same fonts over on every pass beside the cover: measured again only for ones that changed.
    if (changed) [_lines removeAllObjects];
}

- (CGRect)sgr_coverBesideIn:(UIView *)space available:(CGRect)available fitHeight:(BOOL)fitHeight
                 direction:(UIUserInterfaceLayoutDirection)direction
             stackedParent:(UIView *)parent stackedFrame:(CGRect)frame
                      more:(UIView *)more download:(UIView *)download
                   refresh:(dispatch_block_t)refresh {
    _besideRefresh = [refresh copy];
    if (!_besideDefaultsObserver) {
        __weak SGRHeaderInfo *weakSelf = self;
        __block BOOL enabled = SGEnabled(SGRKeyCoverBeside);
        _besideDefaultsObserver = [NSNotificationCenter.defaultCenter
            addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    SGPrefsChanged();
                    BOOL on = SGEnabled(SGRKeyCoverBeside);
                    if (on == enabled) return;
                    enabled = on;
                    SGRHeaderInfo *info = weakSelf;
                    if (info && info->_besideRefresh) info->_besideRefresh();
                });
            }];
        _besideTextObserver = [NSNotificationCenter.defaultCenter
            addObserverForName:UIContentSizeCategoryDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    SGRHeaderInfo *info = weakSelf;
                    if (info && info->_besideRefresh) info->_besideRefresh();
                });
            }];
    }
    BOOL eligible = space.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad &&
        space.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular && SGEnabled(SGRKeyCoverBeside);
    if (eligible || _besideFonts) [self sgr_besideTypography:eligible traits:space.traitCollection];
    // Fit the whole row, including the existing download/More capsule, before committing either column.
    const CGFloat gap = 28, maximumCover = 320, coverShare = 0.4;
    CGFloat side = MIN(maximumCover, available.size.width * coverShare);
    if (fitHeight) side = MIN(side, available.size.height);
    CGFloat column = available.size.width - side - gap;
    CGFloat extra = ((!more.hidden && more) ? SGRGlassCircleSize : 0) +
                    ((!download.hidden && download) ? SGRGlassCircleSize : 0);
    CGFloat rowWidth = MAX(kPlayWidth, [_play sgr_width]) + 2 * (SGRActionHeight + kRowSpacing);
    if (extra) rowWidth += kRowSpacing + extra;
    CGFloat content = [self sgr_contentHeightForTextWidth:MAX(0, column)];
    BOOL beside = eligible && side > 0 && column >= rowWidth &&
        content <= side && side <= available.size.height;
    if (!beside && _besideFonts) [self sgr_besideTypography:NO traits:space.traitCollection];
    _beside = beside;
    if (beside) {
        if (more && more.superview != self) {
            _morePage = more.superview;
            [self addSubview:more];
        }
        if (download && download.superview != self) {
            _downloadPage = download.superview;
            if (more.superview == self) [self insertSubview:download belowSubview:more];
            else [self addSubview:download];
        }
    } else {
        if (_besideDownload.superview == self && _downloadPage) {
            [_downloadPage addSubview:_besideDownload];
            [_downloadPage setNeedsLayout];
        }
        if (_besideMore.superview == self && _morePage) {
            [_morePage addSubview:_besideMore];
            [_morePage setNeedsLayout];
        }
    }
    _besideMore = beside ? more : nil;
    _besideDownload = beside ? download : nil;
    CGRect cover = CGRectZero;
    if (beside) {
        BOOL rtl = direction == UIUserInterfaceLayoutDirectionRightToLeft;
        self.semanticContentAttribute = rtl ? UISemanticContentAttributeForceRightToLeft : UISemanticContentAttributeForceLeftToRight;
        CGFloat top = CGRectGetMinY(available) + (available.size.height - side) / 2;
        cover = CGRectMake(rtl ? CGRectGetMaxX(available) - side : CGRectGetMinX(available), top, side, side);
        CGRect text = CGRectMake(rtl ? CGRectGetMinX(available) : CGRectGetMaxX(cover) + gap, top, column, side);
        if (self.superview != space) [space addSubview:self];
        if (!CGRectEqualToRect(self.frame, text)) self.frame = text;
        NSMutableArray *order = [NSMutableArray array];
        for (UIView *view in @[_title, _creator, _length, _shuffle, _play, _trailing]) {
            if (!view.hidden) [order addObject:view];
        }
        if (download && !download.hidden) [order addObject:download];
        if (more && !more.hidden) [order addObject:more];
        if (!_about.hidden) [order addObject:_about];
        self.accessibilityElements = order;
    } else {
        self.semanticContentAttribute = UISemanticContentAttributeUnspecified;
        if (self.superview != parent) [parent addSubview:self];
        if (!CGRectEqualToRect(self.frame, frame)) self.frame = frame;
        self.accessibilityElements = nil;
    }
    [self setNeedsLayout];
    return cover;
}

// Touches only for the buttons and, where there is one, the creator line: the rest of the text lets a
// pull or a tap through to the page under it.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    // The creator label is the width of the view, so the label itself answers a touch well away from the
    // name; both it and the view answer only where the name is drawn.
    if (hit == self || hit == _creator) return [self sgr_creatorHit:point];
    return hit;
}

// The picture often arrives from the network with the page already on screen. There the picture and the
// title cross over, and the block makes room for the picture in one move rather than in a frame, the picture
// growing out of the title's place; out of a window it all happens at once.
- (void)showTitleImage:(UIImage *)image {
    if (_titleImage == image) return;
    if (!_logo) {
        _logo = [UIImageView new];
        _logo.contentMode = UIViewContentModeScaleAspectFit;
        _logo.isAccessibilityElement = YES;
        _logo.accessibilityTraits = UIAccessibilityTraitHeader;
        _logo.alpha = 0;
        [self addSubview:_logo];
    }
    _titleImage = image;
    [_lines removeAllObjects];
    _title.accessibilityElementsHidden = image != nil;
    if (image) {
        if (!_logo.image) [UIView performWithoutAnimation:^{ self->_logo.frame = self->_title.frame; }];
        _logo.image = image;
        _logo.hidden = NO;
    }
    [self setNeedsLayout];
    void (^fade)(void) = ^{
        self->_logo.alpha = image ? 1 : 0;
        self->_title.alpha = image ? 0 : 1;
    };
    void (^faded)(BOOL) = ^(BOOL finished) {
        if (self->_titleImage) return;
        self->_logo.image = nil;
        self->_logo.hidden = YES;
    };
    if (!self.window) {
        fade();
        faded(YES);
        return;
    }
    SGRAnimate(SGRMotionFade, fade, faded);
    SGRAnimateLayout(self, ^{ [self layoutIfNeeded]; }, nil);
}

// The space under a line: a picture needs more room under it than a line of text does.
- (CGFloat)sgr_gapAfter:(UILabel *)label {
    if (label == _title && _titleImage) return 8;
    return label == _creator ? 4 : 2;
}

// How many text widths the lines are kept measured at: one pass asks at the column beside the cover, the header's
// width and the info's own; a width past those is one changing, whose earlier ones are not asked at again.
static const NSUInteger kMeasuredWidths = 3;

// The lines at the text width `text`, in SGRInfoLine order, then the creator's picture: measured once for the width, so
// a pass that changes none of what they are measured from (a scroll collapsing the header) measures no text. A hidden
// line is CGSizeZero. The title's line is the picture's fitted size where there is a picture; the creator's name is
// measured at the width its faces or picture leave it; the picture is as high and wide as the name is across all of
// `text`, zero without one.
- (NSArray<NSValue *> *)sgr_linesAt:(CGFloat)text {
    NSNumber *key = @(text);
    NSArray<NSValue *> *lines = _lines[key];
    if (lines) return lines;
    CGFloat picture = _picture.image && !_creator.hidden ? ceil([_creator sizeThatFits:CGSizeMake(text, CGFLOAT_MAX)].height) : 0;
    CGFloat lead = _faceImages.count ? [self sgr_facesWidth] : picture;
    NSMutableArray<NSValue *> *measured = [NSMutableArray array];
    for (UILabel *label in @[_title, _creator, _length, _about]) {
        CGSize size = CGSizeZero;
        if (label.hidden) {
        } else if (label == _title && _titleImage) {
            CGSize image = _titleImage.size;
            if (image.width > 0 && image.height > 0) {
                CGFloat scale = MIN(text * kLogoWidthShare / image.width, kLogoMaxHeight / image.height);
                size = CGSizeMake(round(image.width * scale), round(image.height * scale));
            }
        } else {
            CGFloat across = label == _creator && lead ? MAX(0, text - lead - kPictureGap) : text;
            size = [label sizeThatFits:CGSizeMake(across, CGFLOAT_MAX)];
        }
        [measured addObject:[NSValue valueWithCGSize:size]];
    }
    [measured addObject:[NSValue valueWithCGSize:CGSizeMake(picture, picture)]];
    if (_lines.count >= kMeasuredWidths) [_lines removeAllObjects];
    _lines[key] = measured;
    return measured;
}

// How wide what stands before the creator's name is: the faces, or the picture; 0 with neither.
- (CGFloat)sgr_creatorLeadAt:(CGFloat)text {
    if (_faceImages.count) return [self sgr_facesWidth];
    return [self sgr_linesAt:text][SGRInfoAbout + 1].CGSizeValue.width;
}

- (CGSize)sgr_sizeOf:(UILabel *)label width:(CGFloat)text {
    SGRInfoLine line = label == _title ? SGRInfoTitle : label == _creator ? SGRInfoCreator : label == _length ? SGRInfoLength : SGRInfoAbout;
    return [self sgr_linesAt:text][line].CGSizeValue;
}

- (BOOL)showTitle:(NSString *)title creator:(NSString *)creator length:(NSString *)length about:(NSString *)about {
    BOOL changed = NO;
    changed |= setText(_title, title);
    changed |= setText(_creator, creator);
    changed |= setText(_length, length);
    changed |= setText(_about, about);
    if (changed) {
        [_lines removeAllObjects];
        [self setNeedsLayout];
    }
    return changed;
}

// The creator line, tappable. The label is as wide as the view and centered, so the target is narrowed to
// the text itself -- a tap either side of a short name belongs to the page under it, which a pull down
// starts on. Spotify's own control stays concealed where it is and only fires.
- (void)showCreatorLink:(UIView *)control {
    _creatorLink = control;
    BOOL live = control != nil;
    if (_creator.userInteractionEnabled == live) return;
    _creator.userInteractionEnabled = live;
    _creator.accessibilityTraits = live ? UIAccessibilityTraitButton : UIAccessibilityTraitStaticText;
    if (!live || _creator.gestureRecognizers.count) return;
    [_creator addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(sgr_creatorTapped)]];
}

- (void)sgr_creatorTapped {
    SGRActivate(_creatorLink);
}

- (void)showCreatorPicture:(UIImageView *)source {
    if (source != _pictureSource) {
        _pictureSource = source;
        __weak SGRHeaderInfo *weakSelf = self;
        if (source) SGRObserveImage(source, ^(UIImageView *view) {
            SGRHeaderInfo *info = weakSelf;
            if (info && view == info->_pictureSource) [info sgr_takePicture:view.image];
        });
    }
    [self sgr_takePicture:source.image];
}

// The picture fades in where it lands with the page on screen; the name makes room for it in the same move.
- (void)sgr_takePicture:(UIImage *)image {
    if (image == _picture.image) return;
    BOOL appears = image && !_picture.image;
    // The name is measured at the width the picture leaves it.
    if (!image != !_picture.image) [_lines removeAllObjects];
    _picture.image = image;
    _picture.hidden = image == nil;
    [self setNeedsLayout];
    if (!appears || !self.window) return;
    _picture.alpha = 0;
    SGRAnimate(SGRMotionFade, ^{ self->_picture.alpha = 1; }, nil);
    SGRAnimateLayout(self, ^{ [self layoutIfNeeded]; }, nil);
}

- (void)showCreatorFaces:(NSArray<UIImageView *> *)sources from:(UIView *)parent {
    NSString *name = _creator.text ?: @"";
    if (parent != _faceParent || ![name isEqualToString:_faceName]) {
        // Another album's line, or the header reused for one: what was drawn is not its faces.
        _faceParent = parent;
        _faceName = name;
        [self sgr_setFaces:@[]];
    }
    if (![_faceSources.allObjects isEqualToArray:sources ?: @[]]) {
        _faceSources = [NSPointerArray weakObjectsPointerArray];
        __weak SGRHeaderInfo *weakSelf = self;
        for (UIImageView *source in sources) {
            [_faceSources addPointer:(__bridge void *)source];
            SGRObserveImage(source, ^(UIImageView *view) { [weakSelf sgr_faceChanged:view]; });
        }
    }
    [self sgr_updateFaces];
}

// A picture set on one of the faces' image views, Spotify's: the faces are drawn again once for all that land together.
- (void)sgr_faceChanged:(UIImageView *)view {
    if (_facesPending || ![_faceSources.allObjects containsObject:view]) return;
    _facesPending = YES;
    __weak SGRHeaderInfo *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        SGRHeaderInfo *info = weakSelf;
        if (!info) return;
        info->_facesPending = NO;
        [info sgr_updateFaces];
    });
}

- (void)sgr_updateFaces {
    // Shown as they are now, not as they were at the header's pass: a picture can land in a view hidden since.
    UIView *parent = _faceParent;
    NSMutableArray<UIImage *> *images = [NSMutableArray array];
    NSUInteger shown = 0;
    for (UIImageView *source in _faceSources.allObjects) {
        if (!parent || !shownIn(source, parent)) continue;
        shown++;
        if (source.image && images.count < kMaxFaces) [images addObject:source.image];
    }
    // Spotify empties its image views before it fills them again: the faces drawn stay while shown ones wait for theirs.
    if (!images.count && shown) return;
    [self sgr_setFaces:images];
}

// The faces fade in where they land with the page on screen, the name making room for them in the same move.
- (void)sgr_setFaces:(NSArray<UIImage *> *)images {
    if ([_faceImages ?: @[] isEqualToArray:images]) return;
    BOOL appears = images.count && !_faceImages.count;
    // The name is measured at the width the faces leave it.
    if (images.count != _faceImages.count) [_lines removeAllObjects];
    _faceImages = images.count ? images : nil;
    if (!_faces && images.count) {
        _faces = [UIView new];
        _faces.userInteractionEnabled = NO;
        _faces.accessibilityElementsHidden = YES;
        [self addSubview:_faces];
    }
    while (_faces.subviews.count < images.count) {
        UIImageView *face = [UIImageView new];
        face.contentMode = UIViewContentModeScaleAspectFill;
        face.clipsToBounds = YES;
        [_faces addSubview:face];
    }
    [_faces.subviews enumerateObjectsUsingBlock:^(UIView *view, NSUInteger i, BOOL *stop) {
        UIImageView *face = (UIImageView *)view;
        face.image = i < images.count ? images[i] : nil;
        face.hidden = face.image == nil;
    }];
    _faces.hidden = !images.count;
    [self setNeedsLayout];
    if (!appears || !self.window) return;
    _faces.alpha = 0;
    SGRAnimate(SGRMotionFade, ^{ self->_faces.alpha = 1; }, nil);
    SGRAnimateLayout(self, ^{ [self layoutIfNeeded]; }, nil);
}

// The circles a line's height and a point across, at most kMaxFaceSide.
- (CGFloat)sgr_faceSide {
    return MIN(ceil(_creator.font.lineHeight) + 1, kMaxFaceSide);
}

- (CGFloat)sgr_facesWidth {
    CGFloat side = [self sgr_faceSide];
    return side + (_faceImages.count - 1) * round(side * kFaceStep);
}

// The faces in `frame`, the leading one at the leading edge; each next one has the ring around the one before cut out.
- (void)sgr_placeFaces:(CGRect)frame rtl:(BOOL)rtl {
    _faces.frame = frame;
    CGFloat side = frame.size.height, step = round(side * kFaceStep);
    NSUInteger count = _faceImages.count;
    for (NSUInteger i = 0; i < count; i++) {
        UIImageView *face = _faces.subviews[i];
        CGFloat x = rtl ? frame.size.width - side - i * step : i * step;
        face.frame = CGRectMake(x, 0, side, side);
    }
    // The circles and their cut rings follow from these alone (kFaceRing is fixed): made again only when one changes.
    if (side == _placedSide && step == _placedStep && rtl == _placedRTL && count == _placedCount) return;
    _placedSide = side;
    _placedStep = step;
    _placedRTL = rtl;
    _placedCount = count;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (NSUInteger i = 0; i < count; i++) {
        UIImageView *face = _faces.subviews[i];
        face.layer.cornerRadius = side / 2;
        if (i == 0) {
            face.layer.mask = nil;
            continue;
        }
        // The one before, its centre in this one's bounds, rtl to the right of it.
        CGPoint before = CGPointMake(side / 2 + (rtl ? step : -step), side / 2);
        UIBezierPath *cut = [UIBezierPath bezierPathWithRect:CGRectMake(0, 0, side, side)];
        CGFloat ring = side / 2 + kFaceRing;
        [cut appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(before.x - ring, before.y - ring, 2 * ring, 2 * ring)]];
        CAShapeLayer *mask = [face.layer.mask isKindOfClass:CAShapeLayer.class] ? (CAShapeLayer *)face.layer.mask : nil;
        if (!mask) {
            mask = [CAShapeLayer layer];
            mask.fillRule = kCAFillRuleEvenOdd;
            face.layer.mask = mask;
        }
        mask.frame = CGRectMake(0, 0, side, side);
        mask.path = cut.CGPath;
    }
    [CATransaction commit];
}

// The creator line takes a touch only where its text and its picture are; everything else of the view is the
// page's. The label is laid out at the text's own width (-layoutSubviews).
- (UIView *)sgr_creatorHit:(CGPoint)point {
    if (!_creator.userInteractionEnabled || _creator.hidden) return nil;
    CGRect line = _picture.hidden ? _creator.frame : CGRectUnion(_creator.frame, _picture.frame);
    if (_faces && !_faces.hidden) line = CGRectUnion(line, _faces.frame);
    return CGRectContainsPoint(CGRectInset(line, -8, -6), point) ? _creator : nil;
}

- (void)showShuffle:(UIView *)shuffle play:(UIView *)play trailing:(UIView *)trailing
   trailingFallback:(UIImage *)trailingFallback playColor:(UIColor *)playColor {
    _trailing.fallbackGlyph = trailingFallback;
    if (_trailing.readState != self.trailingState) {
        _trailing.readState = self.trailingState;
        _trailing.stateOffSymbol = self.trailingOffSymbol;
        _trailing.stateOnSymbol = self.trailingOnSymbol;
    }
    if (shuffle) [_shuffle feedFrom:shuffle];
    if (play) {
        if (playColor && playInPageColour()) _play.contentColor = playColor;
        // The accent as it is now: Automatic moves it with the page.
        if (_play.cutOut) [self sgr_fillPlay];
        [_play feedFrom:play];
    }
    // Another of Spotify's buttons in the trailing place (save becoming download once the playlist is saved) is
    // a crossfade, a change of what the button is rather than a move.
    if (trailing && _trailing.source && trailing != _trailing.source && !_trailing.hidden && self.window) {
        [UIView transitionWithView:_trailing duration:SGRCrossfade options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{ [self->_trailing feedFrom:trailing]; } completion:nil];
    }
    else if (trailing) [_trailing feedFrom:trailing];

    BOOL changed = NO;
    NSArray<UIView *> *buttons = @[_shuffle, _play, _trailing];
    NSArray<NSNumber *> *shown = @[@(shuffle != nil), @(play != nil), @(trailing != nil)];
    for (NSUInteger i = 0; i < buttons.count; i++) {
        BOOL hide = !shown[i].boolValue;
        if (buttons[i].hidden != hide) {
            buttons[i].hidden = hide;
            changed = YES;
        }
    }
    if (changed) [self setNeedsLayout];
}

- (void)trailingStateChanged {
    if (_trailing.source) [_trailing feedFrom:_trailing.source];
}

- (void)setLargeTitle:(BOOL)largeTitle {
    if (_largeTitle == largeTitle) return;
    _largeTitle = largeTitle;
    _title.font = [self sgr_stackedTitleFont];
    [_lines removeAllObjects];
    [self setNeedsLayout];
}

- (void)setRoundPlay:(BOOL)roundPlay {
    if (_roundPlay == roundPlay) return;
    _roundPlay = roundPlay;
    _play.cutOut = roundPlay && cutOutPlay();
    [self sgr_fillPlay];
    [self setNeedsLayout];
}

// Play's fill: white, or the accent for a cut-out Play while SGRKeyAccentPlay is on.
- (void)sgr_fillPlay {
    _play.fillColor = _play.cutOut && accentPlay() ? SGRAccent() : UIColor.whiteColor;
}

- (CGFloat)sgr_rowHeight {
    return _roundPlay ? kRoundRow : SGRActionHeight;
}

- (void)clipUnderTopBarFollowing:(UIScrollView *)scroll {
    if (scroll != _clipScroll) {
        [_clipScroll removeObserver:self forKeyPath:@"contentOffset" context:kClipScrollContext];
        _clipScroll = scroll;
        [scroll addObserver:self forKeyPath:@"contentOffset" options:0 context:kClipScrollContext];
    }
    _clipsUnderBar = scroll != nil;
    if (_clipsUnderBar) [self clipUnderTopBar];
    else if (_barClip && self.layer.mask == _barClip) self.layer.mask = nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != kClipScrollContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    [self clipUnderTopBar];
}

- (void)clipUnderTopBar {
    CALayer *mask = self.layer.mask;
    if (mask && mask != _barClip) return;
    UIWindow *window = self.window;
    CGFloat line = [self convertPoint:CGPointMake(0, window.safeAreaInsets.top + kTopBar) fromView:nil].y;
    BOOL under = window && line - _contentTop >= kUnderBar;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (!under) {
        if (mask) self.layer.mask = nil;
    } else {
        if (!_barClip) {
            _barClip = [CAGradientLayer layer];
            _barClip.colors = @[(id)UIColor.clearColor.CGColor, (id)UIColor.blackColor.CGColor];
        }
        // Sized and graded once per header size: as tall as the header, and at least the fade, so it covers all of
        // the header under any line in it and the fade keeps its length. A scroll only moves its top edge to the line.
        CGSize size = self.bounds.size;
        CGRect bounds = CGRectMake(0, 0, size.width, MAX(kBarFade, size.height));
        if (!CGRectEqualToRect(_barClip.bounds, bounds)) {
            _barClip.bounds = bounds;
            _barClip.locations = @[@0, @(kBarFade / bounds.size.height)];
        }
        CGPoint position = CGPointMake(CGRectGetMidX(bounds), line + CGRectGetMidY(bounds));
        if (!CGPointEqualToPoint(_barClip.position, position)) _barClip.position = position;
        if (!mask) self.layer.mask = _barClip;
    }
    [CATransaction commit];
}

- (CGFloat)sgr_contentHeightForTextWidth:(CGFloat)text {
    CGFloat height = 0;
    UILabel *previous = nil;
    for (UILabel *label in @[_title, _creator, _length]) {
        if (label.hidden) continue;
        if (previous) height += [self sgr_gapAfter:previous];
        height += ceil([self sgr_sizeOf:label width:text].height);
        previous = label;
    }
    if (previous) height += kRowAbove;
    height += [self sgr_rowHeight];
    if (!_about.hidden) height += kAboutAbove + ceil([self sgr_sizeOf:_about width:text].height);
    return height;
}

- (CGFloat)contentHeightForWidth:(CGFloat)width {
    return [self sgr_contentHeightForTextWidth:MAX(0, width - 2 * (_beside ? 0 : kSide))];
}

// The first placement, from the zero frame the info is made with, and the first layout of what is in it join no
// animation running around them: a page laid out inside one as it opens would slide the row in from the corner.
- (void)setFrame:(CGRect)frame {
    if (!CGRectIsEmpty(self.frame) || CGRectIsEmpty(frame)) {
        [super setFrame:frame];
        return;
    }
    [UIView performWithoutAnimation:^{ [super setFrame:frame]; }];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (_laidOut) {
        [self sgr_layout];
        return;
    }
    // Any pass before it, at the zero size, is outside any animation as well: what it places would start from there.
    _laidOut = !CGRectIsEmpty(self.bounds);
    // The buttons are laid out here too, from this pass, rather than later in the same pass and inside the animation.
    [UIView performWithoutAnimation:^{
        [self sgr_layout];
        for (UIView *button in @[self->_shuffle, self->_play, self->_trailing]) [button layoutIfNeeded];
    }];
}

- (void)sgr_layout {
    CGFloat width = self.bounds.size.width, inset = _beside ? 0 : kSide, text = MAX(0, width - 2 * inset);
    BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    NSTextAlignment leading = rtl ? NSTextAlignmentRight : NSTextAlignmentLeft;
    // Only the column beside the cover is laid out from the leading edge; stacked, the artist's large name is centred too.
    BOOL atLeading = _beside;
    CGFloat content = [self contentHeightForWidth:width];
    CGFloat y = round(self.bounds.size.height - SGRHeaderInfoBottom - content);
    if (self.pinnedTop > 0 && self.pinnedTop + content <= self.bounds.size.height) y = round(self.pinnedTop);
    if (_beside) y = round((self.bounds.size.height - content) / 2);
    _contentTop = y;
    // No name, no picture: it belongs to the line.
    _picture.hidden = !_picture.image || _creator.hidden;
    BOOL faces = _faceImages.count && !_creator.hidden;
    _faces.hidden = !faces;

    UILabel *previous = nil;
    for (UILabel *label in @[_title, _creator, _length]) {
        if (label.hidden) continue;
        if (previous) y += [self sgr_gapAfter:previous];
        CGSize size = [self sgr_sizeOf:label width:text];
        CGFloat height = ceil(size.height);
        label.textAlignment = atLeading ? leading : NSTextAlignmentCenter;
        label.frame = CGRectMake(inset, y, text, height);
        // The name at its own width, so a tap beside it is the page's (-sgr_creatorHit:), and before it the
        // picture, a line high so the line keeps its height, the two centered together. The picture leads, so it
        // is on the right in a right-to-left language.
        // The faces, where the creator has them, take the picture's place: centred on the line, which keeps its height.
        if (label == _creator) {
            CGFloat lead = [self sgr_creatorLeadAt:text];
            CGFloat picture = faces || !_picture.hidden ? lead + kPictureGap : 0;
            CGFloat named = MIN(ceil(size.width), MAX(0, text - picture));
            CGFloat x = round((width - picture - named) / 2);
            if (atLeading) x = rtl ? inset + text - picture - named : inset;
            CGFloat leadX = rtl ? x + named + kPictureGap : x;
            if (faces) {
                CGFloat side = [self sgr_faceSide], scale = self.traitCollection.displayScale ?: UIScreen.mainScreen.scale;
                [self sgr_placeFaces:CGRectMake(leadX, y + round((height - side) / 2 * scale) / scale, lead, side) rtl:rtl];
            } else {
                _picture.frame = CGRectMake(leadX, y, lead, lead);
                _picture.layer.cornerRadius = lead / 2;
            }
            label.frame = CGRectMake(rtl ? x : x + picture, y, named, height);
        }
        if (label == _title && _titleImage) {
            CGFloat x = atLeading ? (rtl ? inset + text - size.width : inset) : round((width - size.width) / 2);
            _logo.frame = CGRectMake(x, y, size.width, height);
            _logo.accessibilityLabel = _title.text;
        }
        y += height;
        previous = label;
    }
    if (previous) y += kRowAbove;

    // Play on the middle of the page, the other two hung off its sides, so it holds its place whether both
    // are there or not.
    CGFloat row = [self sgr_rowHeight];
    // As wide as its words ask (sgr_width), unless the buttons shown either side of it would then not fit with the usual
    // gap: Play is then round, a circle the row's height with its glyph alone, its word only what VoiceOver reads. Beside
    // the cover the row was fitted before the cover was given its column (-sgr_coverBesideIn:...).
    CGFloat playWidth = MAX(kPlayWidth, [_play sgr_width]);
    CGFloat flank = _shuffle.hidden && _trailing.hidden ? 0 : row + kRowSpacing;
    BOOL narrow = !_roundPlay && !_beside && playWidth > width - 2 * (kSide + flank);
    if (_play.round != (_roundPlay || narrow)) _play.round = _roundPlay || narrow;
    if (narrow) playWidth = row;
    if (_roundPlay) {
        // The circle the row's height; the round buttons level with its middle.
        CGFloat side = SGRGlassCircleSize, level = y + round((row - side) / 2);
        CGRect play = CGRectMake(round((width - row) / 2), y, row, row);
        _play.frame = play;
        _shuffle.frame = CGRectMake(CGRectGetMinX(play) - kRoundSpacing - side, level, side, side);
        _trailing.frame = CGRectMake(CGRectGetMaxX(play) + kRoundSpacing, level, side, side);
    } else {
        CGFloat side = row;
        CGRect play = CGRectMake(round((width - playWidth) / 2), y, playWidth, side);
        _play.frame = play;
        _shuffle.frame = CGRectMake(CGRectGetMinX(play) - kRowSpacing - side, y, side, side);
        _trailing.frame = CGRectMake(CGRectGetMaxX(play) + kRowSpacing, y, side, side);
    }
    if (_beside) {
        NSMutableArray<UIView *> *buttons = [NSMutableArray array];
        for (UIView *button in @[_shuffle, _play, _trailing]) if (!button.hidden) [buttons addObject:button];
        if (_besideDownload && !_besideDownload.hidden) [buttons addObject:_besideDownload];
        if (_besideMore && !_besideMore.hidden) [buttons addObject:_besideMore];
        CGFloat x = 0;
        for (NSUInteger i = 0; i < buttons.count; i++) {
            UIView *button = buttons[i];
            CGFloat height = button == _besideDownload || button == _besideMore ? SGRGlassCircleSize : row;
            CGFloat w = button == _play ? _play.bounds.size.width : height;
            CGRect place = CGRectMake(rtl ? width - x - w : x, y + (row - height) / 2, w, height);
            CGRect target = [self convertRect:place toView:button.superview];
            if (!CGRectEqualToRect(button.frame, target)) button.frame = target;
            x += w;
            if (i + 1 < buttons.count && !(button == _besideDownload && buttons[i + 1] == _besideMore)) x += kRowSpacing;
        }
    }
    y += row;

    if (!_about.hidden) {
        y += kAboutAbove;
        _about.textAlignment = _beside ? leading : NSTextAlignmentNatural;
        _about.frame = CGRectMake(inset, y, text, ceil([self sgr_sizeOf:_about width:text].height));
    }
    if (_clipsUnderBar) [self clipUnderTopBar];
}

@end
