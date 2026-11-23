// Playlist redesign: the header the Music app gives a playlist (iOS 26.4). The cover runs full bleed across
// the top of the page and dissolves into the page's color; the title, the creator and the length are centered
// on the bottom of that dissolve; under them one row -- shuffle, a white Play capsule, and save (someone
// else's playlist) or download (one's own, Liked Songs) -- and the description last.
//
// Tree (trees/clean/playlist/01.txt:640-869). Spotify's header is id=PL.Header, and at rest its
// HeaderContentLayout starts at the very top of the page. It holds exactly two things:
//
//     Components.Header.UI.ArtworkImage   a ShadowContainer, the cover square, centered at {80, 68} 243x243
//     the block                           a plain UIView at {0, 327} 386x178: a column of title, description,
//                                         creator row and length, and under it the action row
//
// A mix Spotify makes (Indie Rock Mix, Discover Weekly) is laid out the same way but draws its cover
// differently: there is no artwork square, and in its place a HeaderFullbleedCentralView holds the picture
// full bleed with Spotify's own big title over the bottom of it (trees/continuous/4.txt:1066). So the cover
// is whichever of the two the layout has, and the block is the one thing that is neither.
//
// Nothing is measured from what the header shows: -[SPTFreeTierPlaylistEncoreHeaderViewController update]
// counts a stored fullHeaderHeight and pins headerViewHeightConstraint to it. So the redesign changes no
// height: the cover's square is where the full bleed picture goes, and the block keeps its place, its size
// and its fading as the header collapses.
//
// What is in the block is the redesign's own (the Kit's SGRHeaderInfo), not Spotify's rearranged. Moving Spotify's
// column and controls meant answering every layout pass of theirs -- stacks re-arranging, Auto Layout putting
// frames back, buttons flashing where Spotify wanted them -- so Spotify's contents of the block are concealed
// whole and one view of the redesign's own is drawn in their place, which nothing of Spotify's lays out. It
// reads what it shows from the page's view model (FTPViewModelImplementation: the name, the description,
// whose playlist it is; device 2026-09-18) and from Spotify's concealed labels where the model has no getter
// (the creator, and the length line, already in the app's language). Its buttons draw Spotify's glyphs and
// fire Spotify's own concealed controls, so every action, state and language stays Spotify's.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRCoverViewer.h"
#import "Redesigned/Kit/SGRHeroVeil.h"
#import "Playlist.h"
#import "Redesigned/Album/SGRCoverBeside.h"
#import <objc/message.h>

// How much of the cover's height the dissolve into the field covers, and the scrim over the top of it that
// keeps the status bar and the back button legible on a bright picture.
static const CGFloat kDissolve = 0.46, kTopScrim = 140, kTopScrimAlpha = 0.28;
// A header whose cover square is smaller than this is one mid collapse or mid load, not one to measure
// the hero from.
static const CGFloat kMinHero = 120;

// Whether a tap on the picture opens the cover full screen (SGRKeyPlaylistCoverViewer), read at launch.
static BOOL sg_coverViewer;

static char kCoverKey, kMetaKey, kPlayKey, kLayoutKey, kToolbarKey, kScrimKey, kBarScrimKey;
static char kShuffleKey, kAddKey, kDownloadKey, kPlainDownloadKey, kInfoKey, kBlockHeightKey, kBlockWatchedKey;
static char kHeroKey, kHeroHeightKey, kRestPlaneKey, kRowKey, kRowWatchedKey, kMoreKey, kCreatorKey, kPinnedMoreKey, kPinnedDownloadKey, kSortKey, kTitleKey;
static char kIndependentActionsKey, kListKey;

#pragma mark - finding things

// The page the header is on: FTPViewController's own view -- or, for the songs the user liked by one artist,
// CollectionArtistViewController's, the same header kit with no cover -- which holds the field, the list and the
// header and does not scroll. Walked from the header rather than taken off sgr_playlistRoot, so a playlist under
// another one on the stack pins its own ⋯ and not the one on top.
UIView *SGRPlaylistPageOf(UIView *view) {
    for (UIResponder *r = view; r; r = r.nextResponder) {
        if (![r isKindOfClass:UIViewController.class]) continue;
        NSString *name = NSStringFromClass(r.class);
        // The page of the songs liked by one artist is the cover-less case of the same header kit.
        if ([name containsString:@"FTPViewController"] || [name hasSuffix:@"CollectionArtistViewController"]) return ((UIViewController *)r).viewIfLoaded;
    }
    return nil;
}

UIViewController *SGRPlaylistHeaderOf(UIView *view) {
    for (UIResponder *r = view; r; r = r.nextResponder) {
        if (![r isKindOfClass:UIViewController.class]) continue;
        NSString *name = NSStringFromClass(r.class);
        return [name containsString:@"FreeTierPlaylist"] || [name hasSuffix:@"CollectionArtistHeaderViewController"] ? (UIViewController *)r : nil;
    }
    return nil;
}

static UIView *firstOfClass(UIView *root, Class wanted) {
    __block UIView *found = nil;
    SGForEachView(root, ^(UIView *v) {
        if (!found && [v isKindOfClass:wanted]) found = v;
    });
    return found;
}

#pragma mark - the cover, full bleed

// The picture across the top of the page, a scrim over its top for the status bar, and its bottom masked
// away so the field shows through whatever color it is at that height: pulled down, the hero ends where
// the field is already fading to black, and a fade to the field's flat color showed as an edge.
//
// A tap on the picture, above where the title starts, opens the cover full screen (Kit/SGRCoverViewer.h), as on
// an album (Album/AlbumHeader.x). The hero is drawn on the plane under Spotify's header layout, which takes the
// touches over it, so the tap is the layout's and the hero only says which touches are the picture's: inside it,
// above the title, and on none of Spotify's controls or the block's buttons. A drag still scrolls the page.
@interface SGRPlaylistHero : UIView <UIGestureRecognizerDelegate>
@property (nonatomic, readonly) UIImageView *picture;
// The cover in Spotify's artwork view, and every cover it puts there afterward: the hero keeps itself
// right, rather than being handed a picture on each of the header's passes and staying empty between them.
- (void)followCover:(UIImageView *)source;
// The tap that opens the cover goes on `layout`, the header's content layout over the hero. The same layout
// again is a no-op; nothing while the switch is off.
- (void)openFrom:(UIView *)layout;
@property (nonatomic) BOOL squareOnly;
@property (nonatomic) CGRect besideFrame;
// The scroll veil over the picture (Kit/SGRHeroVeil.h); nil while it is off. The plane already stretches the hero
// with a pull, so the veil adds no zoom. Over Spotify's own square (squareOnly) it blurs and dims that square's
// picture, and moves nothing: the square is placed by Spotify, which sets its frames itself.
@property (nonatomic, readonly) SGRHeroVeil *veil;
@end

@implementation SGRPlaylistHero {
    CAGradientLayer *_scrim, *_dissolve;   // the dissolve is the layer's mask
    __weak UIImageView *_cover;
    UITapGestureRecognizer *_tap;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = !sg_coverViewer;
    self.accessibilityTraits = UIAccessibilityTraitButton | UIAccessibilityTraitImage;
    self.accessibilityLabel = SGL(@"settings.playlist.cover_viewer.cover", @"Playlist cover");
    self.clipsToBounds = YES;

    _picture = [[UIImageView alloc] initWithFrame:self.bounds];
    _picture.contentMode = UIViewContentModeScaleAspectFill;
    _picture.clipsToBounds = YES;
    _picture.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_picture];

    // Above the picture's own layer whatever else is added to the view later.
    _scrim = [CAGradientLayer layer];
    _scrim.zPosition = 1;
    _scrim.colors = @[(id)[UIColor colorWithWhite:0 alpha:kTopScrimAlpha].CGColor, (id)UIColor.clearColor.CGColor];
    [self.layer addSublayer:_scrim];

    _dissolve = [CAGradientLayer layer];
    _dissolve.colors = @[(id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor,
                         (id)[UIColor colorWithWhite:0 alpha:0.28].CGColor, (id)UIColor.clearColor.CGColor];
    self.layer.mask = _dissolve;
    if (SGRHeroScrollVeilOn()) {
        _veil = [[SGRHeroVeil alloc] initWithHero:self];
        _veil.art = @[_picture.layer];
        _veil.stretchesItself = YES;
        // The page's color is read off the main thread, so it can land after the last layout pass of the page.
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sgr_fieldColorDidChange)
                                                   name:SGRFieldColorDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    // The layout outlives the hero it was given; its tap must not call one that is gone.
    [_tap.view removeGestureRecognizer:_tap];
}

- (void)sgr_fieldColorDidChange {
    if (self.superview) _veil.color = SGRPlaylistFieldColor(self);
}

- (void)openFrom:(UIView *)layout {
    if (!sg_coverViewer || !layout || _tap.view == layout) return;
    if (!_tap) {
        _tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(sgr_openCover)];
        _tap.delegate = self;
    }
    [_tap.view removeGestureRecognizer:_tap];
    [layout addGestureRecognizer:_tap];
}

// The part of the picture over no text: the title and the creator start SGRHeaderInfoTitleRise above its bottom.
- (CGRect)sgr_coverArea {
    if (!CGRectIsEmpty(_besideFrame)) return self.bounds;
    if (_squareOnly && _cover) return [_cover convertRect:_cover.bounds toView:self];
    return CGRectMake(0, 0, self.bounds.size.width, MAX(0, self.bounds.size.height - SGRHeaderInfoTitleRise));
}

- (void)setSquareOnly:(BOOL)squareOnly {
    _squareOnly = squareOnly;
    // Keep the invisible hero accessible and its layout's cover tap alive over Spotify's square.
    _picture.hidden = squareOnly;
    _scrim.hidden = squareOnly;
    _veil.art = squareOnly ? @[] : @[_picture.layer];
    _veil.surface = squareOnly ? _cover : nil;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if (!_picture.image || !self.window || self.layer.hidden) return NO;
    if (!CGRectContainsPoint([self sgr_coverArea], [touch locationInView:self])) return NO;
    for (UIView *v = touch.view; v && v != gesture.view; v = v.superview) {
        if ([v isKindOfClass:UIControl.class] || [v isKindOfClass:SGRHeaderInfo.class]) return NO;
    }
    return YES;
}

- (void)sgr_openCover {
    SGRShowCover(_picture.image, SGL(@"settings.playlist.cover_viewer.cover", @"Playlist cover"));
}

- (BOOL)isAccessibilityElement {
    return sg_coverViewer && _picture.image != nil;
}

- (CGRect)accessibilityFrame {
    return UIAccessibilityConvertFrameToScreenCoordinates([self sgr_coverArea], self);
}

- (BOOL)accessibilityActivate {
    if (!sg_coverViewer) return NO;
    [self sgr_openCover];
    return YES;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    // The picture is resized with the hero, which happened with the veil's placement on it: laid out again without.
    [_veil artWillLayOut];
    if (_veil) _picture.frame = bounds;
    _scrim.frame = CGRectMake(0, 0, bounds.size.width, MIN(kTopScrim, bounds.size.height));
    CGFloat height = MAX(1, bounds.size.height), fade = round(height * kDissolve);
    _dissolve.frame = bounds;
    _dissolve.locations = @[@0, @((height - fade) / height), @((height - fade * 0.38) / height), @1];
    self.layer.mask = CGRectIsEmpty(_besideFrame) ? _dissolve : nil;
    _scrim.hidden = _squareOnly || !CGRectIsEmpty(_besideFrame);
    [_veil artDidLayOut];
    [CATransaction commit];
}

- (void)followCover:(UIImageView *)source {
    if (!source) return;
    [self takeCover:source late:NO];
    if (_cover == source) return;
    _cover = source;
    __weak SGRPlaylistHero *weakSelf = self;
    SGRObserveImage(source, ^(UIImageView *view) { [weakSelf takeCover:view late:YES]; });
}

// Spotify loads the artwork at the size the cover square is asking for, and the square shrinks as the
// header collapses: scrolled down it swapped a 105px copy in for the 254px one and the picture across the
// top of the page went soft with it (trees/continuous/2.txt, 2026-09-17). So a copy is taken only while the
// square is still at full size, which is the only time Spotify asks for one worth showing.
//
// `late` is a cover that arrived after the header had laid out -- a playlist opened for the first time,
// whose artwork is still being fetched while the page is already on screen. The log line says once that the
// watch, and not one of the header's passes, is what filled the hero.
- (void)takeCover:(UIImageView *)source late:(BOOL)late {
    UIImage *image = source.image;
    if (!image || source.bounds.size.width < kMinHero || _picture.image == image) return;

    _picture.image = image;
    // The page's field takes its color from the same picture.
    SGRPlaylistSetArtwork(self, image);
    static BOOL logged;
    if (late && !logged) {
        logged = YES;
        SGLog(@"redesign playlist: the cover landed after the header had laid out; the hero took it");
    }
}

@end

// Card hands rendering back to Spotify's square when beside mode ends. Keep every property
// SGRConcealView changes, including a mask Spotify may already own, for that handoff.
@interface SGRPlaylistBesideCover : NSObject
@property (nonatomic, weak, readonly) UIView *cover;
- (instancetype)initWithCover:(UIView *)cover;
- (void)restore;
@end

@implementation SGRPlaylistBesideCover {
    CALayer *_mask;
    BOOL _hidden, _interactive, _accessibilityHidden;
}
- (instancetype)initWithCover:(UIView *)cover {
    if (!(self = [super init])) return nil;
    _cover = cover;
    _mask = cover.layer.mask;
    _hidden = cover.layer.hidden;
    _interactive = cover.userInteractionEnabled;
    _accessibilityHidden = cover.accessibilityElementsHidden;
    return self;
}
- (void)restore {
    _cover.layer.hidden = _hidden;
    _cover.layer.mask = _mask;
    _cover.userInteractionEnabled = _interactive;
    _cover.accessibilityElementsHidden = _accessibilityHidden;
    _cover = nil;
}
- (void)dealloc { [self restore]; }
@end

static char kBesideCoverState;
static void rememberBesideCover(UIView *layout, UIView *cover, BOOL beside) {
    SGRPlaylistBesideCover *state = objc_getAssociatedObject(layout, &kBesideCoverState);
    if (state && (!beside || state.cover != cover)) {
        [state restore];
        objc_setAssociatedObject(layout, &kBesideCoverState, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        state = nil;
    }
    if (beside && cover && !state) {
        state = [[SGRPlaylistBesideCover alloc] initWithCover:cover];
        objc_setAssociatedObject(layout, &kBesideCoverState, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// The hero sits in the plane Spotify's color wash is drawn on, which slides away as the header collapses, so
// Core Animation carries it and its frame is only measured at rest: reading the header per frame flickers.
// Pulled down past the top the plane grows and the hero stretches with it, bottom kept in place.
static void applyHero(UIView *layout, UIView *cover, UIView *plane, UIView *block, CGFloat reach, CGFloat stretch, CGRect beside) {
    if (!plane || !block) return;
    SGRPlaylistHero *hero = objc_getAssociatedObject(plane, &kHeroKey);
    if (!hero) {
        hero = [[SGRPlaylistHero alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(plane, &kHeroKey, hero, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (hero.superview != plane) [plane insertSubview:hero atIndex:0];
    else if (plane.subviews.firstObject != hero) [plane sendSubviewToBack:hero];

    hero.besideFrame = CGRectIsEmpty(beside) ? CGRectZero : [layout convertRect:beside toView:plane];
    CGRect frame = hero.besideFrame;
    BOOL squareOnly = CGRectIsEmpty(frame) && !SGRPageFullCover(SGRKeyPlaylistFullCover) &&
        [cover.accessibilityIdentifier isEqualToString:@"Components.Header.UI.ArtworkImage"];
    hero.autoresizingMask = CGRectIsEmpty(frame) ? UIViewAutoresizingFlexibleHeight : UIViewAutoresizingNone;
    if (CGRectIsEmpty(frame)) {
        // Grow-only: a stacked header still loading puts the block higher than it ends up.
        CGFloat height = [objc_getAssociatedObject(hero, &kHeroHeightKey) doubleValue];
        CGFloat top = CGRectGetMinY(block.frame);
        if (stretch < 0.5 && top > height + 0.5) {
            height = top;
            objc_setAssociatedObject(hero, &kHeroHeightKey, @(height), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            SGLog(@"redesign playlist: hero %.0fpt across the top of the plane", height);
        }
        // Card has already restored Spotify's square. Hand off the picture
        // even before the stacked header is tall enough to size a drawn hero.
        if (height < kMinHero && !squareOnly) return;
        // Reach into the block so the title sits on the bottom of the dissolve.
        frame = CGRectMake(0, 0, plane.bounds.size.width, MAX(kMinHero, round(height + reach)) + stretch);
    }
    if (!CGRectEqualToRect(hero.frame, frame)) hero.frame = frame;

    [hero followCover:SGRHeaderArtworkIn(cover)];
    [hero openFrom:layout];
    hero.veil.color = SGRPlaylistFieldColor(layout);
    // Full bleed covers off: Spotify's own square stays above the block, shrinking as the header collapses, and the
    // hero only reads the picture for the field. A mix's picture is full bleed in Spotify's own layout, so it stays.
    hero.squareOnly = squareOnly;
    if (squareOnly) return;
    SGRConcealView(cover);
}

#pragma mark - the block, the redesign's own

// The page's view model: the header controller's defaultHeaderViewModel, FTPViewModelImplementation on every
// playlist, Liked Songs and a shared playlist alike (device, 2026-09-18). Its getters are plain ObjC --
// playlistName and playlistDescription @, isOwnedBySelf B, formatListType @ (Spotify 9.1.78) -- and each is
// checked before it is called, so a Spotify without one shows Spotify's text for it rather than crashing.
static id viewModelOf(UIViewController *headerVC) {
    SEL controllerSel = NSSelectorFromString(@"headerController"), modelSel = NSSelectorFromString(@"defaultHeaderViewModel");
    if (![headerVC respondsToSelector:controllerSel]) return nil;
    id controller = ((id (*)(id, SEL))objc_msgSend)(headerVC, controllerSel);
    if (![controller respondsToSelector:modelSel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(controller, modelSel);
}

static NSString *modelString(id model, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    if (![model respondsToSelector:sel]) return nil;
    id value = ((id (*)(id, SEL))objc_msgSend)(model, sel);
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static BOOL modelFlag(id model, NSString *name, BOOL fallback) {
    SEL sel = NSSelectorFromString(name);
    if (![model respondsToSelector:sel]) return fallback;
    return ((BOOL (*)(id, SEL))objc_msgSend)(model, sel);
}

// A description is HTML: links to other playlists as <a> and entities for quotes and ampersands.
static NSString *plainText(NSString *html) {
    if (!html.length) return nil;
    static NSRegularExpression *tags;
    if (!tags) tags = [NSRegularExpression regularExpressionWithPattern:@"<[^>]+>" options:0 error:NULL];
    NSMutableString *text = [[tags stringByReplacingMatchesInString:html options:0 range:NSMakeRange(0, html.length)
                                                       withTemplate:@""] mutableCopy];
    NSDictionary<NSString *, NSString *> *entities = @{@"&amp;": @"&", @"&quot;": @"\"", @"&#x27;": @"'", @"&#39;": @"'",
                                                       @"&lt;": @"<", @"&gt;": @">", @"&nbsp;": @" "};
    for (NSString *entity in entities) {
        [text replaceOccurrencesOfString:entity withString:entities[entity] options:0 range:NSMakeRange(0, text.length)];
    }
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.length ? trimmed : nil;
}

// The first label under `root` outside `skip` with at least `minLength` characters. A line that is only a name
// takes 1, since a creator can be one character ("X", "林"); the others pass 2 to pass over a single initial.
static NSString *firstText(UIView *root, UIView *skip, NSUInteger minLength) {
    __block NSString *found = nil;
    SGForEachView(root, ^(UIView *v) {
        if (found || ![v isKindOfClass:UILabel.class] || (skip && [v isDescendantOfView:skip])) return;
        NSString *text = [((UILabel *)v).text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (text.length >= minLength) found = text;
    });
    return found;
}

// The creator is on no getter of the page's model; Spotify's own creator row has the name beside the facepile
// (its avatars, whose initial is a one-letter label of its own: "D | Darkk" on the device, 2026-09-18). A
// shared playlist's reads "Darkk" as well, with the others in the facepile. Looked for no further up than the
// facepile's own row, where the title would be the next label found.
static NSString *creatorIn(UIView *block) {
    __block UIView *facepile = nil;
    SGForEachView(block, ^(UIView *v) {
        if (!facepile && [NSStringFromClass(v.class) containsString:@"FacepileView"]) facepile = v;
    });
    UIView *row = facepile.superview;
    for (NSUInteger level = 0; row && row != block && level < 3; level++, row = row.superview) {
        NSString *name = firstText(row, facepile, 1);
        if (name) return name;
    }
    return nil;
}

// The length line, as Spotify words it in the app's language: "8 saves • 41h 14m", "1 038 songs".
static NSString *lengthIn(UIView *block) {
    return firstText(SGRFindByIdentifier(block, @"Components.Header.UI.Metadata", &kMetaKey), nil, 2);
}

// The header of the songs the user liked by one artist: the playlist page's kit with no playlist behind it.
static BOOL isCollectionArtist(UIView *root) {
    return [NSStringFromClass(SGRPlaylistHeaderOf(root).class) hasSuffix:@"CollectionArtistHeaderViewController"];
}

// The name on the songs liked by one artist: the page's big label. Not the first text of the block, which is the
// word on Spotify's Follow button for as long as the name has not been filled in.
static NSString *artistTitle(UIView *block) {
    UIView *label = SGRFindByIdentifier(block, @"Encore.Label-internal", &kTitleKey);
    NSString *text = [label isKindOfClass:UILabel.class] ? ((UILabel *)label).text : nil;
    text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return text.length ? text : nil;
}

// What the playlist's header shows: the name and the description from the page's model, the creator and the
// length from Spotify's concealed labels. Save and download each keep their own button when both exist.
// One's own playlists and Liked Songs keep their existing row with download alone.
static BOOL sg_creatorLine, sg_creatorPicture, sg_description;
static void showPlaylist(SGRHeaderInfo *info, UIView *block, UIView *root, id model) {
    BOOL artistPage = isCollectionArtist(root);
    NSString *title = modelString(model, @"playlistName") ?: (artistPage ? artistTitle(block) : firstText(block, nil, 2));
    BOOL line = artistPage || sg_creatorLine;
    NSString *name = line ? creatorIn(block) : nil, *length = line ? lengthIn(block) : nil;
    [info showTitle:title creator:name length:length
              about:(artistPage || sg_description) ? plainText(modelString(model, @"playlistDescription")) : nil];

    BOOL liked = [modelString(model, @"formatListType") isEqualToString:@"liked-songs"];
    BOOL own = modelFlag(model, @"isOwnedBySelf", YES) || liked;
    UIView *shuffle = SGRFindByIdentifier(block, @"Components.UI.ShuffleButton", &kShuffleKey);
    UIView *play = SGRFindByIdentifier(root, @"header-play-button", &kPlayKey);
    UIView *save = own ? nil : SGRFindByIdentifier(block, @"Components.UI.AddToButton", &kAddKey);
    UIView *download = SGRFindByIdentifier(block, @"DownloadButton.Granular*", &kDownloadKey)
        ?: SGRFindByIdentifier(block, @"Components.UI.DownloadButton", &kPlainDownloadKey);
    // The title and cover do not determine which actions a playlist supports. Whenever Spotify
    // supplies both save and download, give each its own glass button. Keep that row's layout
    // through transient model updates; a missing source hides only its own button.
    BOOL independent = [objc_getAssociatedObject(info, &kIndependentActionsKey) boolValue];
    if (!independent && save && download) {
        independent = YES;
        objc_setAssociatedObject(info, &kIndependentActionsKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // Download then goes beside the pinned ⋯ (below), and the row is shuffle, Play and save as an album's.
    [info showShuffle:shuffle play:play trailing:independent ? save : save ?: download
     trailingFallback:[UIImage systemImageNamed:independent || save ? @"plus" : @"arrow.down"]
            playColor:SGRPlaylistFieldColor(info)];
    // Only what the button draws goes: a concealed layer still sends the actions the capsule fires.
    SGRConcealView(play);

    // Whoever made the playlist, opened from the line that names them. Spotify's own button carries the
    // facepile and the name and takes the tap to a profile -- or, for a playlist several people are on, to
    // the picker it opens itself (issue #56).
    UIView *creator = name.length ? SGRFindByIdentifier(block, @"Components.PlaylistHeader.collaboratorsButton", &kCreatorKey) : nil;
    [info showCreatorLink:creator];
    // And their picture before their name, the first face of the facepile that button carries.
    [info showCreatorPicture:(creator && (artistPage || sg_creatorPicture)) ? SGRCreatorPicture(creator) : nil];

    // More, pinned over the page rather than left in the block, which is concealed and scrolls away; and
    // Spotify's own Sort, from the find-on-page toolbar this header conceals, for the ⋯ sheet to fire.
    UIView *page = SGRPlaylistPageOf(root);
    SGRPinnedMore(page, &kPinnedMoreKey, SGRFindByIdentifier(block, @"Components.UI.ContextMenuButton*", &kMoreKey));
    SGRPinnedDownload(page, &kPinnedDownloadKey, independent ? download : nil);
    SGRPlaylistTakeSort(page, SGRFindByIdentifier(root, @"Components.Header.UI.Toolbar.Button", &kSortKey));

    static BOOL logged;
    if (!logged && info.window && (title || play)) {
        logged = YES;
        SGLog(@"redesign playlist: own block \"%@\" by %@, \"%@\"; shuffle %@, play %@, %@; model %@",
              title, name ?: @"nobody", length ?: @"no length", shuffle ? @"found" : @"missing",
              play ? @"found" : @"missing", save ? @"save" : (download ? @"download" : @"nothing on the right"),
              model ? NSStringFromClass([model class]) : @"missing");
    }
}

static SGRHeaderInfo *applyInfo(UIView *block, UIView *headerRoot, UIViewController *headerVC, CGRect *stacked);
static void applyHeader(UIView *layout);

// `view`'s own pass puts the block together again, installed once under `key`.
static void reapplyOnPass(UIView *view, const void *key, UIView *block, UIView *headerRoot, UIViewController *headerVC) {
    if (!view || objc_getAssociatedObject(view, key)) return;
    objc_setAssociatedObject(view, key, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakBlock = block, *weakRoot = headerRoot;
    __weak UIViewController *weakVC = headerVC;
    SGRObserveLayout(view, ^(UIView *laidOut) {
        // A block the view has since left is Spotify's to lay out alone.
        SGRHeaderInfo *info = objc_getAssociatedObject(weakRoot, &kInfoKey);
        if (!weakBlock || !weakRoot || !weakVC) return;
        if (info.sgr_coverBeside) {
            applyHeader(weakBlock.superview);
            return;
        }
        if (info.superview != weakBlock) return;
        applyInfo(weakBlock, weakRoot, weakVC, NULL);
    });
}

// The block's own content goes, whole, and the redesign's takes its place. Spotify adds to the block as the page
// loads and shows parts of it again when Play is pressed, so everything of Spotify's in it is concealed on every
// pass and again from the block's own pass; concealing is idempotent and costs nothing once done.
static SGRHeaderInfo *applyInfo(UIView *block, UIView *headerRoot, UIViewController *headerVC, CGRect *stacked) {
    // One per page, kept on the header's root: if Spotify ever hands over another block, the same view moves
    // into it rather than a second one being drawn beside the first.
    SGRHeaderInfo *info = objc_getAssociatedObject(headerRoot, &kInfoKey);
    if (!info) {
        info = [[SGRHeaderInfo alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(headerRoot, &kInfoKey, info, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!info.sgr_coverBeside && info.superview != block) {
        if (info.superview) SGLog(@"redesign playlist: the block moved, %@ -> %@", NSStringFromCGRect(info.superview.frame), NSStringFromCGRect(block.frame));
        [block addSubview:info];
    }
    else if (info.superview == block && block.subviews.lastObject != info) [block bringSubviewToFront:info];
    for (UIView *sub in block.subviews) {
        if (sub != info) SGRConcealView(sub);
    }
    // The page's width, centered on the screen: Spotify's block is 16pt narrower than the page (386 of 402).
    CGFloat x = -[block convertPoint:CGPointZero toView:headerRoot].x;
    CGRect frame = CGRectMake(round(x), 0, headerRoot.bounds.size.width, block.bounds.size.height);
    showPlaylist(info, block, headerRoot, viewModelOf(headerVC));
    // Spotify's block still reserves the hidden metadata. Fit the stacked Card to the
    // remaining lines without moving its top away from the square or enlarging a collapsed header.
    if ((!sg_creatorLine || !sg_description) && block.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPhone &&
        !SGRPageFullCover(SGRKeyPlaylistFullCover) &&
        SGRFindByIdentifier(block.superview, @"Components.Header.UI.ArtworkImage", &kCoverKey)) {
        frame.size.height = MIN(frame.size.height, [info contentHeightForWidth:frame.size.width] + SGRHeaderInfoBottom);
    }
    if (stacked) *stacked = frame;
    if (!info.sgr_coverBeside && !CGRectEqualToRect(info.frame, frame)) info.frame = frame;

    reapplyOnPass(block, &kBlockWatchedKey, block, headerRoot, headerVC);
    // Save arrives after the header has laid out on a playlist opened for the first time, in a row that lays
    // nothing else out: Play's right drew download, or nothing, until the page was opened again (issue #19). The
    // row's own pass is watched too, a plain UIStackView, as the album's and the artist's are.
    reapplyOnPass(SGRFindByIdentifier(block, @"HeaderActionsRow", &kRowKey), &kRowWatchedKey, block, headerRoot, headerVC);
    return info;
}

#pragma mark - the header's pass

// Find on this page and Sort sit above the cover, shown as the page is pulled down. They stay Spotify's own
// controls, so the tap opens Spotify's find page; only the gray box becomes glass.
static void glassUp(UIView *box, const void *key) {
    CGSize size = box.bounds.size;
    if (size.width < 1 || size.height < 1) return;
    if (box.backgroundColor != UIColor.clearColor) box.backgroundColor = UIColor.clearColor;
    if (box.layer.cornerRadius != size.height / 2) box.layer.cornerRadius = size.height / 2;
    SGRGlassCapsuleInside(box, key, size, NO);
}

static void applyToolbar(UIView *headerRoot) {
    static char kFieldKey, kSortBoxKey, kFieldGlassKey, kSortGlassKey;
    UIView *toolbar = SGRFindByIdentifier(headerRoot, @"Components.Header.UI.Toolbar.Content", &kToolbarKey);
    if (!toolbar) return;
    UIView *field = SGRFindByIdentifier(toolbar, @"Components.Header.UI.Toolbar.SearchField", &kFieldKey);
    glassUp(field, &kFieldGlassKey);
    glassUp(SGRFindByIdentifier(toolbar, @"Components.Header.UI.Toolbar.ButtonContainer", &kSortBoxKey), &kSortGlassKey);
    static BOOL logged;
    if (!logged && field.window) {
        logged = YES;
        SGLog(@"redesign playlist: find field %@ in glass, %.0fx%.0f", field.accessibilityLabel,
              field.bounds.size.width, field.bounds.size.height);
    }
}

// Two scrims Spotify fades in under the navigation bar as the page scrolls, each tinted with its own color
// for the page rather than the field's: LiquidGlass.gradientContainer (124pt, a child of HeaderLayout) and
// the HeaderNavigationBar's GradientView. On Liked Songs the first is Spotify's blue, a band across the top
// of a black page (trees/continuous/2.txt, 2026-09-18). UIKit's own scroll edge effect is still there under
// the bar and keeps the back button legible, as on Home, Search and Library. Concealed rather than faded:
// Spotify writes their alpha on every step of the scroll, and the navigation bar's with -setHidden:.
static void applyScrims(UIView *headerRoot) {
    SGRConcealView(SGRFindByIdentifier(headerRoot, @"LiquidGlass.gradientContainer", &kScrimKey));
    // A concealed view stays concealed, so the bar is looked for until it is found and then never again:
    // the header lays out on every step of its collapse.
    if (objc_getAssociatedObject(headerRoot, &kBarScrimKey)) return;
    static Class bar;
    if (!bar) bar = NSClassFromString(@"_TtC28EncoreConsumerMobile_BaseKit19HeaderNavigationBar");
    UIView *navigation = firstOfClass(headerRoot, bar);
    for (UIView *sub in navigation.subviews) {
        if (![NSStringFromClass(sub.class) containsString:@"GradientView"]) continue;
        SGRConcealView(sub);
        objc_setAssociatedObject(headerRoot, &kBarScrimKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// Spotify's color wash goes, so the page's field shows through, and the plane it was drawn on is handed
// back: it is where the hero belongs (applyHero).
//
// The wash is a gradient on a plain view of its own, and that view is painted the base surface. Spotify
// keeps it at alpha 0 on an ordinary playlist, so concealing the gradient was enough; with the Mix feature
// turned on it raises the alpha and the view -- opaque black, drawn after the hero -- covered the picture
// whole (device, trees/continuous/1.txt 2026-09-20, issue #53). So the paint comes off everything on the
// plane as well, which is the same thing the field does to the rest of the page. The hero is left alone:
// the picture is drawn in it.
static UIView *applyBackground(UIView *layout) {
    UIView *container = nil;
    for (UIView *v = layout.superview; v && !container; v = v.superview) {
        for (UIView *sub in v.subviews) {
            if ([sub.accessibilityIdentifier isEqualToString:@"_backgroundViewContainer"]) container = sub;
        }
    }
    UIView *plane = container.subviews.firstObject;
    SGRPlaylistHero *hero = objc_getAssociatedObject(plane, &kHeroKey);
    SGForEachView(container, ^(UIView *v) {
        if (hero && (v == hero || [v isDescendantOfView:hero])) return;
        if ([NSStringFromClass(v.class) containsString:@"GradientView"]) {
            SGRConcealView(v);
            return;
        }
        CGColorRef color = v.layer.backgroundColor;
        if (color && SGIsBaseSurface(color)) v.backgroundColor = UIColor.clearColor;
    });
    return plane;
}

// The full bleed picture a mix is given instead of the artwork square: a child of the layout, as wide as the
// page and at the top of it.
static UIView *fullbleedIn(UIView *layout) {
    static Class fullbleed;
    if (!fullbleed) fullbleed = NSClassFromString(@"_TtC28EncoreConsumerMobile_BaseKit26HeaderFullbleedCentralView");
    for (UIView *sub in layout.subviews) {
        if ([sub isKindOfClass:fullbleed]) return sub;
    }
    return nil;
}

// The layout holds the cover square and, under it, the block of text and controls: the one child nearly as
// wide as the page. Taken by width, not by being lowest: Liked Songs' layout also holds a 45pt slot for its
// icon, which while the page loads sits below the block, and taken for it the header was drawn twice, once
// in the slot and once in the block (device, 2026-09-18).
//
// A mix's full bleed picture is as wide as the page too, and while the block is still unmeasured it is the
// only child wide enough to be taken for it -- which drew the redesign inside it and concealed the picture
// along with the rest of what it holds, leaving a black hero for good, since concealing does not come undone
// (trees/continuous/3.txt against 4.txt, 2026-09-20). It is never the block, so it is skipped like the cover.
static UIView *blockIn(UIView *layout, UIView *cover, UIView *fullbleed) {
    // On iPad the native content can be constrained to its readable guide: not
    // necessarily 60% of the header, nor centered underneath the artwork.
    if (layout.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        UIView *owner = SGRFindByIdentifier(layout, @"HeaderActionsRow", &kRowKey);
        while (owner && owner.superview != layout) owner = owner.superview;
        if (owner && owner != cover && owner != fullbleed && !CGRectIsEmpty(owner.bounds)) return owner;
    }
    UIView *block = nil;
    CGFloat wide = layout.bounds.size.width * 0.6;
    for (UIView *sub in layout.subviews) {
        if (sub == cover || sub == fullbleed || [sub isKindOfClass:SGRPlaylistHero.class] ||
            [sub isKindOfClass:SGRHeaderInfo.class] || sub.bounds.size.width < wide) continue;
        if (!block || CGRectGetMinY(sub.frame) > CGRectGetMinY(block.frame)) block = sub;
    }
    return block;
}

static void applyHeader(UIView *layout) {
    UIViewController *headerVC = SGRPlaylistHeaderOf(layout);
    UIView *headerRoot = headerVC.viewIfLoaded;
    if (!headerRoot) return;

    // A playlist's artwork square, or a mix's full bleed picture where there is no square. Either way it is
    // the view the picture is read from and the view that is concealed once the hero is drawing it.
    UIView *fullbleed = fullbleedIn(layout);
    UIView *cover = SGRFindByIdentifier(layout, @"Components.Header.UI.ArtworkImage", &kCoverKey) ?: fullbleed;
    UIView *block = blockIn(layout, cover, fullbleed);
    if (!block) {
        rememberBesideCover(layout, nil, NO);
        return;
    }

    UIView *plane = applyBackground(layout);
    applyToolbar(headerRoot);
    applyScrims(headerRoot);
    CGRect stacked;
    SGRHeaderInfo *info = applyInfo(block, headerRoot, headerVC, &stacked);

    // How far the page is pulled down past the top: the plane grows by that much and the block moves with it,
    // so nothing is measured then. Rest is the smallest the plane has been.
    CGFloat planeHeight = plane.bounds.size.height;
    CGFloat restPlane = [objc_getAssociatedObject(plane, &kRestPlaneKey) doubleValue];
    if (planeHeight > 0 && (restPlane <= 0 || planeHeight < restPlane - 0.5)) {
        restPlane = planeHeight;
        objc_setAssociatedObject(plane, &kRestPlaneKey, @(restPlane), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(objc_getAssociatedObject(plane, &kHeroKey), &kHeroHeightKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(block, &kBlockHeightKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat stretch = MAX(0, planeHeight - restPlane);

    // How far into the block the picture reaches: past the block's top by the title and the creator. The
    // block's height only grows (loading the description grows it, collapsing shrinks it).
    CGFloat rest = [objc_getAssociatedObject(block, &kBlockHeightKey) doubleValue];
    if (stretch < 0.5 && block.bounds.size.height > rest) {
        rest = block.bounds.size.height;
        objc_setAssociatedObject(block, &kBlockHeightKey, @(rest), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat top = cover ? CGRectGetMinY(cover.frame) : 0;
    CGRect available = CGRectMake(20, top, layout.bounds.size.width - 40,
        CGRectGetMaxY(block.frame) - top - SGRHeaderInfoBottom);
    UIView *page = SGRPlaylistPageOf(layout);
    // Artwork and metadata live in different planes. Fit both to their common
    // header footprint in content coordinates; neither can use space outside it.
    if (cover && plane && layout.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        CGRect footprint = CGRectIntersection(layout.bounds, [plane convertRect:plane.bounds toView:layout]);
        // The controller's root does not clip its children; the wash's container
        // does. They need not be the same height during a scene resize.
        footprint = CGRectIntersection(footprint, [plane.superview convertRect:plane.superview.bounds toView:layout]);
        if (page) footprint = CGRectIntersection(footprint, [page convertRect:page.bounds toView:layout]);
        available = CGRectIntersection(available, footprint);
        if (CGRectIsEmpty(available)) available = CGRectZero;
    }
    __weak UIView *weakLayout = layout;
    CGRect beside = [info sgr_coverBesideIn:layout available:cover ? available : CGRectZero fitHeight:YES
        direction:page.effectiveUserInterfaceLayoutDirection
        stackedParent:block stackedFrame:stacked
        more:objc_getAssociatedObject(page, &kPinnedMoreKey) download:objc_getAssociatedObject(page, &kPinnedDownloadKey)
        refresh:^{ if (weakLayout) applyHeader(weakLayout); }];
    rememberBesideCover(layout, cover, !CGRectIsEmpty(beside));
    CGFloat reach = rest - SGRHeaderInfoBottom - [info contentHeightForWidth:headerRoot.bounds.size.width] + SGRHeaderInfoTitleRise;
    if (cover) applyHero(layout, cover, plane, block, reach, stretch, beside);
    // Liked Songs has no cover at all, so there is nothing for its page to wait for once it has its title.
    else if (info.window && modelString(viewModelOf(headerVC), @"playlistName")) SGRPlaylistShowPage(layout);

    // The header sits over the page's list, which is what scrolls; it moves and collapses as the list does.
    SGRPlaylistHero *hero = objc_getAssociatedObject(plane, &kHeroKey);
    [hero setNeedsLayout];
    layout.accessibilityElements = hero && info.sgr_coverBeside ? @[hero, info] : nil;
    SGRHeroVeil *veil = hero.veil;
    if (veil) {
        UIView *list = SGRFindByIdentifier(SGRPlaylistPageOf(layout), SGRPlaylistListIdentifier, &kListKey);
        UIScrollView *scroll = [list isKindOfClass:UIScrollView.class] ? (UIScrollView *)list : nil;
        [info clipUnderTopBarFollowing:scroll];
        [veil followScroll:scroll];
        [veil update];
    }
}

// The content layout of the page `root` belongs to, kept weakly on it: the header lays out on every step of
// its collapse and a walk of its tree each time would be the redesign's own cost.
static UIView *layoutIn(UIView *root) {
    if (!root) return nil;
    static Class content;
    if (!content) content = NSClassFromString(@"_TtC28EncoreConsumerMobile_BaseKit19HeaderContentLayout");
    return SGFindRemembered(root, &kLayoutKey, ^BOOL(UIView *view) {
        return [view isKindOfClass:content];
    });
}

%hook _TtC28EncoreConsumerMobile_BaseKit19HeaderContentLayout
- (void)layoutSubviews {
    %orig;
    if (SGRPlaylistHeaderOf((UIView *)self)) applyHeader((UIView *)self);
}
%end

// The header's own pass catches the parts that fade in rather than being laid out: the find bar, and the
// action buttons as they arrive. The scroll's is where what Spotify fades back in is taken again.
// The play button arrives in the header's foreground plane after the row that replaces it has been laid
// out, so a page opening showed Spotify's green disc in the corner until something else laid the header out
// (device, 2026-09-17). Its own pass is where it goes, and the class is Spotify's own so nothing else pays
// for the check.
%hook _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView
- (void)layoutSubviews {
    %orig;
    UIView *button = (UIView *)self;
    if (button.layer.hidden || ![button.accessibilityIdentifier isEqualToString:@"header-play-button"]) return;
    if (SGRPlaylistHeaderOf(button)) SGRConcealView(button);
}
%end

%hook SPTFreeTierPlaylistEncoreHeaderViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *layout = layoutIn(((UIViewController *)self).viewIfLoaded);
    if (layout) applyHeader(layout);
}

// What the page's model says changes without a layout pass of the header's: the saves count comes in after the
// page opens (0, then 4647, device 2026-09-18), and a Save or an edit to the name updates it again.
- (void)update {
    %orig;
    UIView *layout = layoutIn(((UIViewController *)self).viewIfLoaded);
    if (layout) applyHeader(layout);
}

%end

%ctor {
    if (!SGRedesignedUI()) return;
    sg_coverViewer = SGEnabled(SGRKeyPlaylistCoverViewer);
    sg_creatorLine = SGEnabled(SGRKeyPlaylistCreatorLine);
    sg_creatorPicture = SGEnabled(SGRKeyPlaylistCreatorPicture);
    sg_description = SGEnabled(SGRKeyPlaylistDescription);
    %init;
    SGRequireClasses(@[
        @"_TtC28EncoreConsumerMobile_BaseKit19HeaderContentLayout",
        @"SPTFreeTierPlaylistEncoreHeaderViewController",
        @"_TtC28EncoreConsumerMobile_BaseKit14PlayButtonView",
    ]);
}
