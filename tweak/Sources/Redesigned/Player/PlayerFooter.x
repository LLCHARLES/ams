// Player redesign: the footer as the Music app's row of three glyphs, lyrics, devices and queue, spread
// evenly across the player, and no share button.
//
// Spotify's footer is Connect with the device's name at the leading edge, share, and the queue at the
// trailing edge. Connect and the queue stay Spotify's controls (the device sheet, the remote device
// tint, the Jam avatars) and are only moved, by a translation of the arranged view that holds each: a
// transform survives the stack view laying them out again, and moving the holder keeps its touches
// inside its own bounds. The device name goes transparent, since the glyph alone sits in the middle, and
// Connect's holder takes touches only in a square over the glyph (SGRPlayerCoverConnect).
// Both draw the Music app's glyphs, AirPlay audio and a bulleted list (issue #109): a stand-in inside each of
// Spotify's glyph views, so it is hidden, faded and pulsed with Spotify's own, while Spotify's drawing goes
// clear at its source. Connect's glyph is an image Spotify draws the color into: each new one is read once for
// that color, so a device in use still lights it in the accent (or the cover's, PlayerCoverAccent.x), and is
// swapped for a clear image of its size. The queue's is an SPTEncoreIconView: its foreground colors are kept
// for the stand-in and Spotify's drawn clear. Music app icons on the Player page (SGRKeyPlayerMusicIcons) switches the
// stand-ins off and on while the player is open; the row's places, the hidden device name and the touch square stay.
// Spotify has no lyrics control down here, so that one is the Kit's glyph button, and it turns the
// lyrics in the player on and off (PlayerLyrics.x): filled while they are up, dimmed and dead for a
// track that has none. With Music app icons off it draws Spotify's Encore microphone instead
// (SGRPlayerFooterGlyph), lit and dimmed the same way. In the iPad two column player (PlayerLyrics.x) Lyrics picks the
// side column's lines and a queue glyph of the Kit's, where the row puts Spotify's queue button, picks its queue; each
// is lit while its side shows. The same glyph stands in a row Spotify builds without a queue button (a Free account's)
// and opens Playing Next (PlayerQueue.m), as the Music app's row always has its queue.
//
// The bottom stack keeps the Music app's rhythm (keepRhythm): its gaps from the title row down to the footer row are
// Apple's, set as the stack's own spacing, which raises the title row into the cover's band.
//
// The row sits lower than Spotify puts it, just over the home indicator the way the Music app's does
// (issue #54): the footer unit's view is translated down, the controls follow it part of the way, and a
// band of the redesign's hands the touches below the bottom stack's bounds back to the row.
//
// Tree (trees/clean/player/01.txt:295-320): FooterElementsUnit's view 402x44 > UIStackView 382x44 >
// ElementView > ConnectButtonOutputSwitcherViewHolder id=Components.ConnectButtonOutputSwitcher 153x36
// (a 19x19 UIImageView glyph and a MarqueeLabel with the device name), a spacer, a hidden media trimmer,
// ElementView > EncoreButton id=ShareButtonNowPlayingView 44x44, ElementView > Queue control
// id=QueueButtonNowPlaying 47x32 (an 18x18 SPTEncoreIconView id=Encore.IconView glyph, out/rep/ptree.txt:1228-1279).
#import <substrate.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRPress.h"
#import "Headers/SPTEncoreIconView.h"
#import "Player.h"
#import "PlayerQueue.h"
#import <objc/message.h>

static const CGFloat kLyricsGlyphSize = 20;
// The platter a pressed glyph of the row sinks into (SGRPress.h), the row's touch square.
static const CGFloat kFooterPlatter = 44;
// Filled and at full strength while the lyrics are up, the way the Music app marks the control that is on.
static NSString *const kLyricsSymbol = @"quote.bubble", *const kLyricsSymbolOpen = @"quote.bubble.fill";
// Spotify's lyrics glyph, the microphone its other apps mark Lyrics with, drawn instead with Music app icons off.
// SPTEncoreIcon has no "lyrics" in 9.1.90 (its 571 class methods, SpotifyShared's metadata).
static NSString *const kLyricsEncore = @"microphone";
// Spotify's glyphs in the footer are drawn this size: the queue's SPTEncoreIconView is 18x18 (out/rep/ptree.txt:1228-1279).
static const CGFloat kEncoreGlyphSide = 18;
// Where the three glyphs sit, as parts of the footer's width.
static const CGFloat kLeading = 0.2, kMiddle = 0.5, kTrailing = 0.8;
static const CGFloat kGlyphMaxWidth = 30;

// Issue #54: Spotify ends its bottom stack 61pt above the screen's bottom (01.txt:127, 576.67 + 236 of
// 874), so the row's middle sat 83pt up, well clear of the home indicator, and the controls crowded it.
// The Music app keeps that row just over the home indicator: its middle this far above the safe area's
// bottom, and never less than kRowMinBottom above the screen's on a phone without a home indicator.
static const CGFloat kRowAboveSafeArea = 20, kRowMinBottom = 34;
// The controls follow a share of the row's move when nothing stands between them, so the gaps above
// and below them even out instead of all the room opening under them. Not while the rhythm below holds them.
static const CGFloat kControlsShare = 0.3;
// The Music app's gaps down its player (iOS 26, design/applemusic-gap item 4), each from the middle of what is above
// unless named: from the artist's last line to the progress bar, from the bar to the play button, and from the play
// button to the volume row (SGRPlayerVolumeToRow goes on to the footer row). Spotify's own were 27, 71 and 55.
static const CGFloat kArtistToBar = 38, kBarToPlay = 91, kPlayToVolume = 91;

// "airplayaudio" is the name iOS 16 knows; iOS 18 calls it airplay.audio and keeps this one as its alias.
static NSString *const kConnectSymbol = @"airplayaudio", *const kQueueSymbol = @"list.bullet";

static char kConnectKey, kShareKey, kTrimmerKey, kSharedByKey, kQueueKey, kQueueIconKey, kLyricsGlyphKey, kReachKey, kRowKey;
static char kQueueGlyphKey;
static __weak SGRGlyphButton *sg_lyricsGlyph, *sg_queueGlyph;
// Spotify's queue button, taken off the row while the two columns' queue glyph (placeQueueGlyph) stands in its place.
static NSHashTable<UIView *> *sg_queueStoodIn;

// The view the footer's stack view arranges around `view`.
static UIView *arrangedAround(UIView *view, UIView *host) {
    for (UIView *v = view; v && v != host; v = v.superview) {
        if ([v.superview isKindOfClass:UIStackView.class]) return v;
    }
    return nil;
}

// Where `point` of `view` is in the host with the arranged view's own transform left out.
static CGFloat untransformedX(UIView *arranged, UIView *view, CGPoint point, UIView *host) {
    CGPoint local = [view convertPoint:point toView:arranged];
    CGPoint inRow = CGPointMake(arranged.center.x + local.x - CGRectGetMidX(arranged.bounds), arranged.center.y);
    return [arranged.superview convertPoint:inRow toView:host].x;
}

static CGFloat moveTo(UIView *arranged, UIView *view, CGPoint point, UIView *host, CGFloat x) {
    if (!arranged) return -1;
    CGFloat from = untransformedX(arranged, view, point, host);
    CGAffineTransform transform = CGAffineTransformMakeTranslation(round(x - from), 0);
    if (!CGAffineTransformEqualToTransform(arranged.transform, transform)) arranged.transform = transform;
    return from;
}

#pragma mark - Spotify's glyphs in the redesign's buttons

// With Music app icons off (SGRKeyPlayerMusicIcons), Lyrics and the AI DJ's Queue are Spotify's Encore glyphs drawn in
// the button, the button's symbol hidden (not cleared: a press puts the symbol's alpha back). Kept on the button, so the
// switch on again takes it out and shows the symbol, and off again puts the same one back.
static char kEncoreGlyphKey;
static NSMutableSet<NSString *> *sg_missingEncore;

// Spotify's Encore glyph `name`, the size of Spotify's own glyph in the footer (the queue's), taking no touches.
static SPTEncoreIconView *makeEncoreGlyph(NSString *name) {
    Class icons = NSClassFromString(@"SPTEncoreIcon"), view = NSClassFromString(@"SPTEncoreIconView");
    SEL selector = NSSelectorFromString(name);
    id icon = [icons respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(icons, selector) : nil;
    SPTEncoreIconView *encore = icon && view ? [[view alloc] initWithIcon:icon] : nil;
    if (!encore) {
        SGLogOnce(&sg_missingEncore, name, @"redesign player: no Encore glyph %@, the Music app's stays");
        return nil;
    }
    encore.bounds = CGRectMake(0, 0, kEncoreGlyphSide, kEncoreGlyphSide);
    encore.userInteractionEnabled = NO;
    encore.isAccessibilityElement = NO;
    encore.accessibilityElementsHidden = YES;
    encore.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin
                            | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    return encore;
}

// The Encore glyph in the color the symbol has: Lyrics lit while the lyrics are up, dimmed with the button.
static void paintEncore(SGRGlyphButton *button) {
    SPTEncoreIconView *encore = objc_getAssociatedObject(button, &kEncoreGlyphKey);
    UIColor *color = button.glyph.tintColor;
    if (encore && ![encore.foregroundColor isEqual:color]) encore.foregroundColor = color;
}

UIView *SGRPlayerFooterGlyph(SGRGlyphButton *button, NSString *encoreName) {
    if (!button) return nil;
    SGRGlyphView *symbol = button.glyph;
    SPTEncoreIconView *encore = objc_getAssociatedObject(button, &kEncoreGlyphKey);
    if (SGEnabled(SGRKeyPlayerMusicIcons)) {
        if (encore.superview) [encore removeFromSuperview];
        if (symbol.hidden) symbol.hidden = NO;
        return symbol;
    }
    if (!encore) {
        encore = makeEncoreGlyph(encoreName);
        if (!encore) return symbol;
        objc_setAssociatedObject(button, &kEncoreGlyphKey, encore, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (encore.superview != button) [button addSubview:encore];
    CGPoint middle = CGPointMake(CGRectGetMidX(button.bounds), CGRectGetMidY(button.bounds));
    if (!CGPointEqualToPoint(encore.center, middle)) encore.center = middle;
    if (!symbol.hidden) symbol.hidden = YES;
    paintEncore(button);
    return encore;
}

#pragma mark - lyrics

// The queue glyph of the redesign's own, lit while the side column shows the queue, the way Lyrics is lit while it shows
// the lines; never lit in the one column, where it opens a sheet.
static void markQueueGlyph(void) {
    SGRGlyphButton *queue = sg_queueGlyph;
    if (!queue) return;
    BOOL shown = SGRPlayerQueueSideShown();
    UIColor *tint = shown ? SGRPrimary() : SGRSecondary();
    if (![queue.glyph.tintColor isEqual:tint]) queue.glyph.tintColor = tint;
    queue.accessibilityTraits = UIAccessibilityTraitButton | (shown ? UIAccessibilityTraitSelected : 0);
    paintEncore(queue);
}

void SGRPlayerLyricsChanged(void) {
    SGRPlayerMotionLyricsChanged();
    SGRPlayerVisualiserUpdate();
    SGRShownTitleRestyle();
    markQueueGlyph();
    SGRGlyphButton *glyph = sg_lyricsGlyph;
    if (!glyph) return;
    BOOL enabled = SGRPlayerLyricsAvailable() || SGRPlayerLyricsOpen(), open = SGRPlayerLyricsOpen();
    BOOL wasOpen = [glyph.glyph.symbol isEqualToString:kLyricsSymbolOpen];
    if (glyph.enabled == enabled && wasOpen == open) return;
    // Lyrics turn up once the player has fetched them, well after the footer laid out: a fade, not a pop.
    // While the player opens or closes the glyph and the lyrics come and go together, so nothing animates.
    BOOL animated = glyph.window && !SGRPlayerIsTransitioning();
    [glyph.glyph setSymbol:open ? kLyricsSymbolOpen : kLyricsSymbol animated:animated];
    void (^mark)(void) = ^{
        glyph.enabled = enabled;
        glyph.glyph.tintColor = open ? SGRPrimary() : SGRSecondary();
        paintEncore(glyph);
    };
    if (animated) SGRAnimate(SGRMotionFade, mark, nil);
    else mark();
}

SGRGlyphButton *SGRPlayerLyricsGlyphIn(UIView *host) {
    SGRGlyphButton *glyph = objc_getAssociatedObject(host, &kLyricsGlyphKey);
    if (!glyph) {
        glyph = [SGRGlyphButton buttonWithSymbol:kLyricsSymbol pointSize:kLyricsGlyphSize title:SGL(@"settings.main.lyrics.title", @"Lyrics")];
        glyph.glyph.tintColor = SGRSecondary();
        glyph.onTap = ^{ SGRPlayerToggleLyrics(); };
        objc_setAssociatedObject(host, &kLyricsGlyphKey, glyph, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (glyph.superview != host) [host addSubview:glyph];
    SGRPlayerFooterGlyph(glyph, kLyricsEncore);
    sg_lyricsGlyph = glyph;
    return glyph;
}

#pragma mark - the Music app's glyphs

// Switched off on the Player page (SGRKeyPlayerMusicIcons), the stand-ins come out of Spotify's glyph views and what
// Spotify drew is given back: Connect's last image, the queue's two colors. Each is kept on its view while a stand-in
// covers it. Switched on again, the next pass of the footer puts the stand-ins back over whatever Spotify draws then.
static char kStandInKey, kClearKey, kSpotifyImageKey, kQueueRestColorKey, kQueueActiveColorKey;

// The stand-in over `drawn`, while one is shown there; nil once the Music app's glyphs are switched off.
static SGRGlyphView *shownStandIn(UIView *drawn) {
    SGRGlyphView *glyph = objc_getAssociatedObject(drawn, &kStandInKey);
    return glyph.superview == drawn ? glyph : nil;
}

// The Kit's glyph centered inside `drawn`: it takes `drawn`'s hidden, alpha and animations with it.
static SGRGlyphView *standIn(UIView *drawn, NSString *symbol) {
    if (!drawn) return nil;
    SGRGlyphView *glyph = objc_getAssociatedObject(drawn, &kStandInKey);
    if (!glyph) {
        glyph = [[SGRGlyphView alloc] initWithSymbol:symbol pointSize:kLyricsGlyphSize weight:UIImageSymbolWeightRegular];
        glyph.userInteractionEnabled = NO;
        glyph.isAccessibilityElement = NO;
        glyph.tintColor = SGRSecondary();   // at rest, as the Lyrics glyph while it is off
        // Kept centered when Spotify resizes the view between the footer's passes (a new Connect image of another size).
        glyph.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin
                               | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        objc_setAssociatedObject(drawn, &kStandInKey, glyph, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (glyph.superview != drawn) [drawn addSubview:glyph];
    CGPoint middle = CGPointMake(CGRectGetMidX(drawn.bounds), CGRectGetMidY(drawn.bounds));
    if (!CGPointEqualToPoint(glyph.center, middle)) glyph.center = middle;
    return glyph;
}

// The color Spotify drew its glyph in (SGRPlayerImageInk, kept on the image, so an image Spotify hands over again costs
// a lookup). One drawn from the tint answers the tint.
static UIColor *inkOf(UIImageView *view, UIImage *image) {
    if (image.isSymbolImage || image.renderingMode == UIImageRenderingModeAlwaysTemplate) return view.tintColor;
    return SGRPlayerImageInk(image) ?: SGRPrimary();
}

// A lit glyph as a bitmap in its color, the way Spotify draws its own: Follow the cover finds lit controls by their
// pixels, and a symbol image has none to read. The symbol's alignment insets are kept, so it sits where it did.
// Drawn in the glyph's traits (Bold Text, contrast), as its template image is.
static UIImage *litImage(SGRGlyphView *glyph, UIImage *symbol, UIColor *color) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat formatForTraitCollection:glyph.traitCollection];
    format.scale = symbol.scale;
    UIImage *tinted = [symbol imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal];
    __block UIImage *bitmap;
    [glyph.traitCollection performAsCurrentTraitCollection:^{
        bitmap = [[[UIGraphicsImageRenderer alloc] initWithSize:symbol.size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [tinted drawAtPoint:CGPointZero];
        }];
    }];
    return [bitmap imageWithAlignmentRectInsets:symbol.alignmentRectInsets];
}

// Spotify's new Connect glyph: its color onto the stand-in, drawn into the stand-in's image so Follow the cover
// repaints it the way it did Spotify's, and a clear image of the same size in its place, so nothing moves.
static void takeConnectImage(UIImageView *drawn) {
    UIImage *image = drawn.image;
    UIImage *clear = objc_getAssociatedObject(drawn, &kClearKey);
    SGRGlyphView *glyph = shownStandIn(drawn);
    // Whatever Spotify sets while the stand-in shows, nil or an image with no bitmap included, is what goes back when the
    // Music app's glyphs are switched off; only the clear image set here is not Spotify's. One with no bitmap has no color
    // to read and stays drawn as Spotify set it.
    if (!glyph || (clear && image == clear)) return;
    objc_setAssociatedObject(drawn, &kSpotifyImageKey, image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!image.CGImage) return;
    UIImage *symbol = [UIImage systemImageNamed:glyph.symbol withConfiguration:glyph.preferredSymbolConfiguration];
    UIColor *ink = inkOf(drawn, image);
    BOOL lit = SGRPlayerAccentLike(ink);
    glyph.image = lit ? litImage(glyph, symbol, ink) : symbol;
    // Spotify hands the new image over with no layout pass, so Follow the cover is told here, or a lit glyph keeps the accent.
    if (lit) SGRPlayerPaintCover(glyph);
    if (!clear || !CGSizeEqualToSize(clear.size, image.size) || clear.scale != image.scale) {
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
        format.scale = image.scale;
        clear = [[[UIGraphicsImageRenderer alloc] initWithSize:image.size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {}];
        objc_setAssociatedObject(drawn, &kClearKey, clear, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    drawn.image = clear;
}

// Spotify draws a new glyph when the device changes, with no layout pass of the footer to tell it, so its setImage:
// tells the stand-in; the clear image set back in reports too, and stops there. Each pass looks too, at the cost of a
// compare, for a view the image cannot be watched on.
// Off, an image Spotify sets reaches takeConnectImage with no stand-in shown and stays.
static void standInForConnect(UIImageView *drawn) {
    if (!SGEnabled(SGRKeyPlayerMusicIcons)) {
        SGRGlyphView *glyph = shownStandIn(drawn);
        if (!glyph) return;
        [glyph removeFromSuperview];
        // Recorded on every image Spotify set since the stand-in went in, the first included (takeConnectImage below).
        UIImage *spotify = objc_getAssociatedObject(drawn, &kSpotifyImageKey);
        if (drawn.image != spotify) drawn.image = spotify;
        return;
    }
    BOOL made = objc_getAssociatedObject(drawn, &kStandInKey) != nil;
    if (!standIn(drawn, kConnectSymbol)) return;
    takeConnectImage(drawn);
    if (!made) SGRObserveImage(drawn, ^(UIImageView *view) { takeConnectImage(view); });
}

// The queue's state as Spotify sets it, for the stand-in; Spotify's own glyph is drawn in clear.
static void tintQueueStandIn(SPTEncoreIconView *icon) {
    SGRGlyphView *glyph = shownStandIn(icon);
    if (!glyph) return;
    // Lit by Spotify's own state, not by a color a cover could make look gray. Lit, it is drawn in the color, as Connect
    // is, so Follow the cover finds it by its pixels and repaints it.
    UIColor *active = objc_getAssociatedObject(icon, &kQueueActiveColorKey);
    UIImage *symbol = [UIImage systemImageNamed:glyph.symbol withConfiguration:glyph.preferredSymbolConfiguration];
    BOOL lit = icon.isActive && active;
    glyph.image = lit ? litImage(glyph, symbol, active) : symbol;
    if (lit) SGRPlayerPaintCover(glyph);
}

static void standInForQueue(SPTEncoreIconView *icon) {
    if (![icon isKindOfClass:%c(SPTEncoreIconView)]) return;
    BOOL on = SGEnabled(SGRKeyPlayerMusicIcons);
    SGRGlyphView *shown = shownStandIn(icon);
    if (on == (shown != nil)) return;
    // Spotify's colors: read while Spotify's drawing is its own, before the stand-in goes in; kept from then on by the
    // setters below, and handed back through them once it is out again.
    UIColor *color, *active;
    if (on) {
        color = icon.foregroundColor;
        active = icon.activeForegroundColor;
        standIn(icon, kQueueSymbol);
    } else {
        color = objc_getAssociatedObject(icon, &kQueueRestColorKey);
        active = objc_getAssociatedObject(icon, &kQueueActiveColorKey);
        [shown removeFromSuperview];
    }
    // Both always, nil included: going in, so each is recorded afresh (a record from an earlier time on would otherwise
    // come back); going out, so a color Spotify reset to nil meanwhile is nil again, not the clear put in its place.
    icon.foregroundColor = color;
    icon.activeForegroundColor = active;
    tintQueueStandIn(icon);
}

%hook SPTEncoreIconView
// The stand-in does not take the color at rest, only the active one; both are kept to give back.
- (void)setForegroundColor:(UIColor *)color {
    BOOL ours = shownStandIn(self) != nil;
    if (ours) objc_setAssociatedObject(self, &kQueueRestColorKey, color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(ours ? UIColor.clearColor : color);
}
- (void)setActiveForegroundColor:(UIColor *)color {
    BOOL ours = shownStandIn(self) != nil;
    if (ours) objc_setAssociatedObject(self, &kQueueActiveColorKey, color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(ours ? UIColor.clearColor : color);
    if (ours) tintQueueStandIn(self);
}
- (void)setIsActive:(BOOL)active {
    %orig;
    tintQueueStandIn(self);
}
%end

#pragma mark - the row

static UIView *connectGlyphIn(UIView *holder) {
    __block UIView *glyph = nil;
    SGForEachView(holder, ^(UIView *view) {
        if (!glyph && [view isKindOfClass:UIImageView.class] && ![view isKindOfClass:SGRGlyphView.class]
            && view.bounds.size.width > 0 && view.bounds.size.width <= kGlyphMaxWidth) glyph = view;
    });
    return glyph;
}

// Connect is Spotify's control as wide as the device's name, with the glyph near its leading edge. With the
// name hidden and the glyph in the middle, its touches would reach far past the glyph, over the queue, and
// hardly before it. So the row's view that holds it takes touches only in a square over the glyph, the size
// of the row's other two; Spotify's own views inside still handle them. The square is kept on that view, and
// its class answers from it, as it does for every other view of the class.
static char kConnectHitKey;
static NSMutableDictionary<NSString *, NSValue *> *sg_origPointInside;   // class name -> original IMP

static BOOL connectPointInside(UIView *self, SEL _cmd, CGPoint point, UIEvent *event) {
    NSValue *square = objc_getAssociatedObject(self, &kConnectHitKey);
    if (square) return CGRectContainsPoint(square.CGRectValue, point);
    // The nearest hooked class up the chain holds the original this view would have run.
    for (Class cls = self.class; cls; cls = class_getSuperclass(cls)) {
        NSValue *orig = sg_origPointInside[NSStringFromClass(cls)];
        // A subclass hooked after its parent got the parent's hook as its original; that one is skipped.
        if (orig && orig.pointerValue != (void *)connectPointInside)
            return ((BOOL (*)(UIView *, SEL, CGPoint, UIEvent *))orig.pointerValue)(self, _cmd, point, event);
    }
    return NO;
}

void SGRPlayerCoverConnect(UIView *arranged, UIView *glyph) {
    if (!arranged || !glyph) return;
    // The ordinary footer and the DJ's can hand over views of different classes; each class is hooked once.
    if (!sg_origPointInside) sg_origPointInside = [NSMutableDictionary new];
    NSString *name = NSStringFromClass(arranged.class);
    if (!sg_origPointInside[name]) {
        IMP orig = NULL;
        MSHookMessageEx(arranged.class, @selector(pointInside:withEvent:), (IMP)connectPointInside, &orig);
        sg_origPointInside[name] = [NSValue valueWithPointer:(void *)orig];
    }
    CGRect drawn = [glyph convertRect:glyph.bounds toView:arranged];
    CGRect square = CGRectMake(CGRectGetMidX(drawn) - 22, CGRectGetMidY(drawn) - 22, 44, 44);
    objc_setAssociatedObject(arranged, &kConnectHitKey, [NSValue valueWithCGRect:square], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Connect's glyph, ready to be moved: Connect laid out first, since the glyph is unsized until it is (the first time the
// player opens), and its device name hidden. The name is a MarqueeLabel on the phone's speaker and a plain Encore label
// on AirPods; Connect holds nothing else that draws text. With no glyph yet the caller leaves Connect where Spotify put
// it, and `host` looks again on the next turn of the run loop.
UIView *SGRPlayerConnectGlyphIn(UIView *host, UIView *connect) {
    [connect layoutIfNeeded];
    UIView *glyph = connectGlyphIn(connect);
    static NSUInteger lookedAgain;   // a Connect with no glyph at all is left alone after this many
    if (glyph) lookedAgain = 0;
    if (connect && !glyph && lookedAgain++ < 20) {
        __weak UIView *weakHost = host;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakHost setNeedsLayout]; });
    }
    SGForEachView(connect, ^(UIView *view) {
        if ([view isKindOfClass:UILabel.class] || [NSStringFromClass(view.class) containsString:@"MarqueeLabel"]) SGRVanish(view);
    });
    if (glyph) standInForConnect((UIImageView *)glyph);
    return glyph;
}

#pragma mark - lower down

// Moved down, the row is drawn partly below the bottom stack it is arranged in, and UIKit does not look
// into a view for a touch outside its bounds. This band over the part that hangs out hands such a touch
// to the row itself, and lets every other one through.
@interface SGRFooterReach : UIView
@property (nonatomic, weak) UIView *row;
@end

@implementation SGRFooterReach
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *row = self.row;
    // Its own band only: lifted back on top (placeReach), it is over views that take the touches elsewhere.
    if (![self pointInside:point withEvent:event] || !row.window || row.alpha < 0.01 || row.hidden) return nil;
    UIView *hit = [row hitTest:[row convertPoint:point fromView:self] withEvent:event];
    return hit == row ? nil : hit;
}
@end

// The band of `row`, in `stack`, over `band` of `player`. Spotify holds a podcast episode's player and a track's in units
// of their own, each row in a bottom stack of its own, and on every switch between them takes its views out of the player
// and puts the new kind's back on top: the bottom stack and, after it, a plain view over the strip under it, the band's
// strip (Spotify 9.2.0, music, an episode, music again). A band put in before stays under them, its touches taken by that
// view, and the band of a row that has left stays in the player. So a band whose row is no longer in the player goes,
// a row that does not hang out of its stack by a pixel has none, and a band its stack has come over goes back on top.
static void placeReach(UIView *row, UIView *stack, UIView *player, CGRect band, CGFloat scale) {
    SGRFooterReach *reach = objc_getAssociatedObject(row, &kReachKey);
    for (UIView *view in player.subviews) {
        if ([view isKindOfClass:SGRFooterReach.class] && view != reach && ![((SGRFooterReach *)view).row isDescendantOfView:player])
            [view removeFromSuperview];
    }
    if (band.size.height * scale < 1) {
        [reach removeFromSuperview];
        return;
    }
    if (!reach) {
        reach = [SGRFooterReach new];
        reach.row = row;
        objc_setAssociatedObject(row, &kReachKey, reach, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSArray<UIView *> *siblings = player.subviews;
    if (reach.superview != player) [player addSubview:reach];
    else if ([siblings indexOfObject:reach] < [siblings indexOfObject:stack]) [player bringSubviewToFront:reach];
    if (!CGRectEqualToRect(reach.frame, band)) reach.frame = band;
}

static UIViewController *unitOf(UIView *view) {
    UIResponder *next = view.nextResponder;
    return [next isKindOfClass:UIViewController.class] && ((UIViewController *)next).viewIfLoaded == view ? (UIViewController *)next : nil;
}

// The arranged view drawn right above `row` in its stack, by where the stack put them.
static UIView *rowAbove(UIView *row) {
    UIView *best = nil;
    CGFloat top = row.center.y - row.bounds.size.height / 2, bestBottom = -CGFLOAT_MAX;
    // The volume row lives in the same stack, between the controls and the footer: it is not what is above, or the
    // controls would be taken for something else whenever it ends within a point of the footer (the AI DJ's gap does).
    static Class volumeRow;
    if (!volumeRow) volumeRow = NSClassFromString(@"SGRVolumeRow");
    for (UIView *sibling in row.superview.subviews) {
        if (sibling == row || sibling.hidden || sibling.alpha < 0.01 || sibling.bounds.size.height < 1) continue;
        if (volumeRow && [sibling isKindOfClass:volumeRow]) continue;
        CGFloat bottom = sibling.center.y + sibling.bounds.size.height / 2;
        if (bottom <= top + 1 && bottom > bestBottom) {
            best = sibling;
            bestBottom = bottom;
        }
    }
    return best;
}

#pragma mark - margins and rhythm

static char kMarginInsetKey, kMarginOriginalsKey, kMarginContentKey;

// +1 for a constraint on the leading side of `view` that moves it in as its constant grows, -1 for one that moves it
// out, and on the trailing side the other way round; 0 for any other.
static CGFloat insetSign(NSLayoutConstraint *constraint, UIView *view) {
    BOOL first = constraint.firstItem == view;
    if (!first && constraint.secondItem != view) return 0;
    NSLayoutAttribute attribute = first ? constraint.firstAttribute : constraint.secondAttribute;
    CGFloat side = attribute == NSLayoutAttributeLeading || attribute == NSLayoutAttributeLeft ? 1
                 : attribute == NSLayoutAttributeTrailing || attribute == NSLayoutAttributeRight ? -1 : 0;
    return first ? side : -side;
}

// The inset goes into the constants of Spotify's constraints that hold the view's sides in its superview, so the
// constraints inside it lay its content out for the new width. Each constraint's own constant is kept to add to, and a
// constraint Spotify makes anew is taken up on the next pass. For a row pinned to the unit, its native margin is
// in the pin, not in the frame (which can still be the reused row's last adjusted frame). Where the content starts in
// the view is Spotify's only until the view is inset: the narrowed title row lays its content out anew (the title 8 pt
// in for 12 on the next pass, 9.2.0), and an inset measured from that changed pass by pass, the row left 24, 32 or
// 36 pt in by where the passes stopped (issue #35). So it is read once the view is inset and kept for as long as it is.
// A view not inset still shows Spotify's own layout and is read on every pass: a title row first read while it held
// a video podcast's thumbnail (the title 60 pt in, so no inset) is read again without it.
void SGRPlayerHoldMargin(UIView *view, CGFloat contentX) {
    UIView *unit = view.superview;
    if (!unit) return;
    NSNumber *content = objc_getAssociatedObject(view, &kMarginContentKey);
    if (!content || [objc_getAssociatedObject(view, &kMarginInsetKey) doubleValue] <= 0)
        objc_setAssociatedObject(view, &kMarginContentKey, content = @(contentX), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    contentX = content.doubleValue;
    NSMapTable<NSLayoutConstraint *, NSNumber *> *originals = objc_getAssociatedObject(view, &kMarginOriginalsKey);
    BOOL rtl = unit.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    NSNumber *inset = nil;
    for (NSLayoutConstraint *pin in unit.constraints) {
        if (!pin.active || pin.relation != NSLayoutRelationEqual || pin.multiplier != 1 ||
            pin.firstAttribute != pin.secondAttribute ||
            (pin.firstAttribute != NSLayoutAttributeLeading && pin.firstAttribute != (rtl ? NSLayoutAttributeRight : NSLayoutAttributeLeft))) continue;
        id edge = pin.firstItem == view ? pin.secondItem : pin.secondItem == view ? pin.firstItem : nil;
        CGRect anchor = unit.bounds;
        if ([edge isKindOfClass:UILayoutGuide.class] && [(UILayoutGuide *)edge owningView] == unit)
            anchor = [(UILayoutGuide *)edge layoutFrame];
        else if (edge != unit) continue;
        NSNumber *original = [originals objectForKey:pin] ?: @(pin.constant);
        CGFloat from = original.doubleValue * insetSign(pin, view)
            + (rtl ? CGRectGetMaxX(unit.bounds) - CGRectGetMaxX(anchor) : CGRectGetMinX(anchor) - CGRectGetMinX(unit.bounds));
        CGFloat wanted = SGRPlayerSideMargin - from - contentX;
        inset = @(wanted > 0 && view.bounds.size.width > 2 * wanted ? round(wanted) : 0);
        break;
    }
    // Unknown pin arrangements keep the previously measured native margin.
    NSNumber *lastInset = objc_getAssociatedObject(view, &kMarginInsetKey);
    if (!inset) inset = lastInset;
    else if (![inset isEqual:lastInset])
        objc_setAssociatedObject(view, &kMarginInsetKey, inset, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!inset) {
        CGRect frame = view.frame;
        CGFloat from = rtl ? CGRectGetMaxX(unit.bounds) - CGRectGetMaxX(frame) : CGRectGetMinX(frame) - CGRectGetMinX(unit.bounds);
        CGFloat wanted = SGRPlayerSideMargin - (from + contentX);
        inset = @(wanted > 0 && frame.size.width > 2 * wanted ? round(wanted) : 0);
        objc_setAssociatedObject(view, &kMarginInsetKey, inset, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSUInteger sides = 0;
        for (NSLayoutConstraint *constraint in unit.constraints) sides += insetSign(constraint, view) != 0;
        SGLog(@"redesign player: %@ inset %@ pt to the player's margin through %lu constraints", NSStringFromClass(view.class), inset, (unsigned long)sides);
    }
    if (!originals) {
        originals = [NSMapTable weakToStrongObjectsMapTable];
        objc_setAssociatedObject(view, &kMarginOriginalsKey, originals, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (NSLayoutConstraint *constraint in unit.constraints) {
        CGFloat sign = insetSign(constraint, view);
        if (!sign || !constraint.active) continue;
        NSNumber *original = [originals objectForKey:constraint];
        if (!original) [originals setObject:(original = @(constraint.constant)) forKey:constraint];
        CGFloat constant = original.doubleValue + sign * inset.doubleValue;
        if (constraint.constant != constant) constraint.constant = constant;
    }
}

// The Music app's rhythm in Spotify's bottom stack, by the stack's own spacing after the title row, the progress bar
// and the controls: Spotify pins the stack's bottom, so room added there raises everything over it, the title row into
// the cover's band, and the room inside the stack opens as the Music app's. Measured from where Spotify's layout puts
// each, the moves this file and PlayerLyrics.x add left out, so a pass that finds the gaps right changes nothing.
// Only in a player taller than wide with one column, and only the ordinary player's units (found by Spotify's ids);
// elsewhere, or when one is missing, Spotify's own spacing comes back.
static char kArtistKey, kSliderKey, kPlayKey, kRhythmKey;

// The arranged view of `stack` that holds `view`.
static UIView *arrangedIn(UIStackView *stack, UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        if (v.superview == stack) return [stack.arrangedSubviews containsObject:v] ? v : nil;
    }
    return nil;
}

// Where `y` of `view` is in `player`, its arranged view's transform left out.
static CGFloat untransformedY(UIStackView *stack, UIView *arranged, UIView *view, CGFloat y, UIView *player) {
    CGFloat local = [view convertPoint:CGPointMake(0, y) toView:arranged].y - CGRectGetMinY(arranged.bounds);
    CGFloat top = arranged.center.y - arranged.bounds.size.height / 2;
    return [stack convertPoint:CGPointMake(0, top + local) toView:player].y;
}

// YES when the spacing changed.
static BOOL spaceAfter(UIStackView *stack, UIView *view, CGFloat spacing) {
    if (fabs([stack customSpacingAfterView:view] - spacing) < 0.5) return NO;
    [stack setCustomSpacing:spacing afterView:view];
    NSHashTable<UIView *> *spaced = objc_getAssociatedObject(stack, &kRhythmKey);
    if (!spaced) {
        spaced = [NSHashTable weakObjectsHashTable];
        objc_setAssociatedObject(stack, &kRhythmKey, spaced, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [spaced addObject:view];
    return YES;
}

// From `gap` to `target`, by the spacing after `view`; YES when the spacing changed. The spacing the measured frames were laid out with is read from
// the frames themselves (the room between `view` and the arranged view after it), not from the stack's setting, which
// may be ahead of a layout still to come: a pass before it would add the same room again. Never under Spotify's own
// spacing, and never more than the target over it.
static BOOL closeGap(UIStackView *stack, UIView *view, CGFloat gap, CGFloat target) {
    NSArray<UIView *> *arranged = stack.arrangedSubviews;
    NSUInteger index = [arranged indexOfObject:view];
    UIView *next = nil;
    for (NSUInteger i = index + 1; index != NSNotFound && i < arranged.count && !next; i++) {
        if (!arranged[i].hidden) next = arranged[i];
    }
    if (!next) return NO;
    CGFloat laidOut = (next.center.y - next.bounds.size.height / 2) - (view.center.y + view.bounds.size.height / 2);
    return spaceAfter(stack, view, round(MIN(MAX(stack.spacing, laidOut + target - gap), stack.spacing + target)));
}

static void dropRhythm(UIStackView *stack) {
    NSHashTable<UIView *> *spaced = objc_getAssociatedObject(stack, &kRhythmKey);
    for (UIView *view in spaced.allObjects) [stack setCustomSpacing:UIStackViewSpacingUseDefault afterView:view];
    [spaced removeAllObjects];
}

// YES while the rhythm holds the stack: `rowMiddle` is where the footer row's middle ends up in `player`. `respaced`
// says whether a spacing changed, which moves the stack's views only once the player lays the stack out again.
static BOOL keepRhythm(UIStackView *stack, UIView *player, CGFloat rowMiddle, BOOL wanted, BOOL *respaced) {
    *respaced = NO;
    UIView *artist = SGRFindByIdentifier(stack, @"now-playing-subtitle-label", &kArtistKey);
    UIView *slider = SGRFindByIdentifier(stack, @"SPTNowPlayingSliderV2", &kSliderKey);
    UIView *play = SGRFindByIdentifier(stack, @"SPTNowPlayingPlayButton", &kPlayKey);
    UIView *info = arrangedIn(stack, artist), *duration = arrangedIn(stack, slider), *controls = arrangedIn(stack, play);
    NSArray<UIView *> *arranged = stack.arrangedSubviews;
    BOOL ordered = info && duration && controls && [arranged indexOfObject:info] < [arranged indexOfObject:duration]
        && [arranged indexOfObject:duration] < [arranged indexOfObject:controls];
    if (!wanted || !ordered || artist.bounds.size.height < 1 || slider.bounds.size.height < 1) {
        dropRhythm(stack);
        return NO;
    }
    CGFloat artistBottom = untransformedY(stack, info, artist, CGRectGetMaxY(artist.bounds), player);
    CGFloat bar = untransformedY(stack, duration, slider, CGRectGetMidY(slider.bounds), player);
    CGFloat playMiddle = untransformedY(stack, controls, play, CGRectGetMidY(play.bounds), player);
    CGFloat toRow = kPlayToVolume + (SGRPlayerVolumeOn() ? SGRPlayerVolumeToRow : 0);
    BOOL afterInfo = closeGap(stack, info, bar - artistBottom, kArtistToBar);
    BOOL afterBar = closeGap(stack, duration, playMiddle - bar, kBarToPlay);
    BOOL afterControls = closeGap(stack, controls, rowMiddle - playMiddle, toRow);
    *respaced = afterInfo || afterBar || afterControls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SGLog(@"redesign player: rhythm from gaps %.0f, %.0f and %.0f to the Music app's %.0f, %.0f and %.0f", bar - artistBottom,
              playMiddle - bar, rowMiddle - playMiddle, kArtistToBar, kBarToPlay, toRow);
    });
    return YES;
}

// The stack moves its views for new spacing only when the player lays it out, a pass the footer's own is part of and
// must not run again from inside: measured before it, the volume row stood against the controls' old place, over them,
// and nothing laid the footer out again (its size had not changed). So one pass of the player's, out of every layout, on
// the next turn of the run loop, and the footer placed after it against where the controls are then. That pass asks for
// none of its own (sg_rhythmSettling), whatever it finds; one is pending per player at a time.
static char kRhythmPendingKey;
static BOOL sg_rhythmSettling;

static void settleRhythm(UIView *player, UIView *row) {
    if (sg_rhythmSettling || objc_getAssociatedObject(player, &kRhythmPendingKey)) return;
    objc_setAssociatedObject(player, &kRhythmPendingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakPlayer = player, *weakRow = row;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *settledPlayer = weakPlayer, *settledRow = weakRow;
        if (!settledPlayer) return;
        objc_setAssociatedObject(settledPlayer, &kRhythmPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!settledPlayer.window || settledRow.superview.superview != settledPlayer) return;
        sg_rhythmSettling = YES;
        [settledPlayer setNeedsLayout];
        [settledPlayer layoutIfNeeded];
        SGRPlayerLowerRow(settledRow);
        sg_rhythmSettling = NO;
    });
}

void SGRPlayerLowerRow(UIView *row) {
    UIView *stack = row.superview, *player = stack.superview;
    UIWindow *window = row.window;
    if (![stack isKindOfClass:UIStackView.class] || !player || !window) return;
    // Where the stack put the row, the row's own transform left out, and where it belongs.
    CGFloat middle = [stack convertPoint:row.center toView:player].y;
    CGFloat height = player.bounds.size.height;
    CGFloat target = height - MAX(window.safeAreaInsets.bottom + kRowAboveSafeArea, kRowMinBottom);
    BOOL columns = SGRPlayerTwoColumns();
    if (columns) target = CGRectGetMaxY(SGRPlayerVisibleSafeArea(player)) - row.bounds.size.height / 2 - kRowAboveSafeArea;
    CGFloat move = round(target - middle);
    if (!columns) move = MAX(0, move);
    CGAffineTransform down = CGAffineTransformMakeTranslation(0, move);
    if (!CGAffineTransformEqualToTransform(row.transform, down)) row.transform = down;
    BOOL respaced;
    BOOL rhythm = keepRhythm((UIStackView *)stack, player, middle + move, !columns && height > player.bounds.size.width, &respaced);
    if (respaced) settleRhythm(player, row);

    // Only the controls, and only straight above: a volume row between them keeps its place and theirs.
    UIView *above = rowAbove(row);
    // The ordinary player's controls unit, or the AI DJ's head unit (DJPlayer.x), which holds the same buttons.
    NSString *unit = NSStringFromClass(unitOf(above).class);
    BOOL controls = [unit containsString:@"PlaybackControlsElementsUnit"] || [unit containsString:@"DJMHeadUnitViewController"];
    // With the volume row, the controls stay where Spotify put them and the row takes the room the footer leaves.
    // The volume row is placed against the controls where they would stand for it; one that does not show leaves them
    // following the footer as they do without it. The rhythm has placed them already.
    BOOL volume = SGRPlayerVolumeOn() && controls;
    CGFloat share = volume || rhythm ? 0 : kControlsShare;
    CGAffineTransform follow = CGAffineTransformMakeTranslation(0, controls ? round(move * share) : 0);
    if (above && controls && !CGAffineTransformEqualToTransform(above.transform, follow)) above.transform = follow;
    SGRPlayerPaintCover(stack);
    if (volume && !SGRPlayerPlaceVolume(stack, above, row, SGRPlayerSideMargin, rhythm) && !rhythm) {
        share = kControlsShare;
        follow = CGAffineTransformMakeTranslation(0, round(move * share));
        if (!CGAffineTransformEqualToTransform(above.transform, follow)) above.transform = follow;
    } else if (!volume) {
        SGRPlayerPlaceVolume(stack, nil, row, SGRPlayerSideMargin, rhythm);
    }

    CGRect stackFrame = [stack convertRect:stack.bounds toView:player];
    CGRect drawn = [row convertRect:row.bounds toView:player];
    CGFloat from = CGRectGetMaxY(stackFrame);
    CGRect band = CGRectMake(CGRectGetMinX(drawn), from, drawn.size.width, MAX(0, CGRectGetMaxY(drawn) - from));
    placeReach(row, stack, player, band, window.traitCollection.displayScale);

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SGLog(@"redesign player: footer row from %.0f to %.0f of %.0f (safe area %.0f), controls %@ %.0f, volume %@", middle, middle + move, height,
              window.safeAreaInsets.bottom, controls ? @"follow" : @"stay", controls ? round(move * share) : 0, SGRPlayerVolumeOn() ? @"on" : @"off");
    });
}

// The queue glyph of the redesign's own, where the row puts Spotify's queue button. In the two columns (PlayerLyrics.x)
// it picks the side column's queue rather than a sheet of its own: 9.1.90's iPad player has no queue button in its row,
// and one that a row does have is taken off it for as long as the glyph stands there, and given back with the one
// column. In the one column it stands only in a row Spotify gives no queue button (a Free account's, 9.1.90), the
// Music app's row having one always, and opens Playing Next (PlayerQueue.m); a row with Spotify's keeps Spotify's.
static void placeQueueGlyph(UIView *host, UIView *spotifyQueue, CGPoint center) {
    SGRGlyphButton *glyph = objc_getAssociatedObject(host, &kQueueGlyphKey);
    if (!sg_queueStoodIn) sg_queueStoodIn = [NSHashTable weakObjectsHashTable];
    BOOL columns = SGRPlayerTwoColumns();
    if (!columns) {
        for (UIView *view in sg_queueStoodIn) {
            view.alpha = 1;
            view.userInteractionEnabled = YES;
            view.accessibilityElementsHidden = NO;
        }
        [sg_queueStoodIn removeAllObjects];
    }
    if (!columns && spotifyQueue) {
        [glyph removeFromSuperview];
        return;
    }
    if (!glyph) {
        glyph = [SGRGlyphButton buttonWithSymbol:kQueueSymbol pointSize:kLyricsGlyphSize title:SGL(@"settings.player.ipad.queue", @"Queue")];
        glyph.accessibilityIdentifier = @"retrine.player.queue";
        __weak SGRGlyphButton *weakGlyph = glyph;
        glyph.onTap = ^{
            if (SGRPlayerTwoColumns()) SGRPlayerToggleQueueSide();
            else SGRPlayerShowQueue(weakGlyph);
        };
        objc_setAssociatedObject(host, &kQueueGlyphKey, glyph, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (glyph.superview != host) [host addSubview:glyph];
    glyph.bounds = CGRectMake(0, 0, kFooterPlatter, kFooterPlatter);
    glyph.center = center;
    if (columns && spotifyQueue) {
        SGRVanish(spotifyQueue);
        [sg_queueStoodIn addObject:spotifyQueue];
    }
    sg_queueGlyph = glyph;
    UIView *drawn = SGRPlayerFooterGlyph(glyph, @"queue");
    markQueueGlyph();
    SGRPressGlyph(glyph, drawn, host, kFooterPlatter, drawn == glyph.glyph ? 0 : SGRPressScale);
}

%hook _TtC20NowPlaying_ModesImpl18FooterElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *host = ((UIViewController *)self).viewIfLoaded;
    if (!host) return;
    SGRPlayerWatchLook(host);
    // The unit lays out before its row does, and the moves are measured from where the row put things.
    [SGFindRemembered(host, &kRowKey, ^BOOL(UIView *v) { return SGIsRow(v); }) layoutIfNeeded];
    CGFloat width = host.bounds.size.width, middleY = CGRectGetMidY(host.bounds);
    BOOL rtl = host.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;

    UIView *share = SGRFindByIdentifier(host, @"ShareButtonNowPlayingView", &kShareKey);
    // The arranged view goes too: a view that takes touches swallows them even with nothing on it.
    SGRVanish(share);
    SGRVanish(arrangedAround(share, host));
    // Spotify's clip button, hidden in every clean tree, would turn up where the queue moves to.
    UIView *trimmer = SGRFindByIdentifier(host, @"nowplaying-npv-media-trimmer-navigation-button", &kTrimmerKey);
    SGRVanish(trimmer);
    SGRVanish(arrangedAround(trimmer, host));
    // "From <friend>" on a track a friend shared sits in the middle of the row, over Connect, which the
    // row moves there; the Music app has no such chip.
    UIView *sharedBy = SGRFindByIdentifier(host, @"Components.UI.SharedByChip", &kSharedByKey);
    SGRVanish(sharedBy);
    SGRVanish(arrangedAround(sharedBy, host));

    UIView *queue = SGRFindByIdentifier(host, @"QueueButtonNowPlaying", &kQueueKey);
    CGPoint queueMiddle = CGPointMake(CGRectGetMidX(queue.bounds), CGRectGetMidY(queue.bounds));
    // The Agent prompt adds height below the row. The queue only moves sideways, so its y stays on the row.
    CGFloat rowY = queue.window ? round([queue convertPoint:queueMiddle toView:host].y) : middleY;
    SGRGlyphButton *lyrics = SGRPlayerLyricsGlyphIn(host);
    lyrics.bounds = CGRectMake(0, 0, 44, 44);
    lyrics.center = CGPointMake(round(width * (rtl ? kTrailing : kLeading)), rowY);
    SGRPlayerLyricsChanged();

    UIView *connect = SGRFindByIdentifier(host, @"Components.ConnectButtonOutputSwitcher", &kConnectKey);
    UIView *glyph = SGRPlayerConnectGlyphIn(host, connect);
    CGFloat connectFrom = glyph ? moveTo(arrangedAround(connect, host), glyph, CGPointMake(CGRectGetMidX(glyph.bounds), CGRectGetMidY(glyph.bounds)), host, round(width * kMiddle)) : -1;

    standInForQueue((SPTEncoreIconView *)SGRFindByIdentifier(queue, @"Encore.IconView", &kQueueIconKey));
    CGFloat queueX = round(width * (rtl ? kLeading : kTrailing));
    CGFloat queueFrom = moveTo(arrangedAround(queue, host), queue, queueMiddle, host, queueX);
    placeQueueGlyph(host, arrangedAround(queue, host), CGPointMake(queueX, rowY));

    SGRPlayerLowerRow(host);
    SGRPlayerCoverConnect(arrangedAround(connect, host), glyph);

    // The Music app's press on each of the three, its platter under the row in the unit's view. The lyrics glyph
    // sinks and dims on its own (SGRGlyphButton), Spotify's Encore glyph in its place does not and is sunk here; Connect's
    // and the queue's glyphs are Spotify's image views.
    UIView *lyricsDrawn = SGRPlayerFooterGlyph(lyrics, kLyricsEncore);
    SGRPressGlyph(lyrics, lyricsDrawn, host, kFooterPlatter, lyricsDrawn == lyrics.glyph ? 0 : SGRPressScale);
    if (connect && glyph) SGRPressGlyph(connect, glyph, host, kFooterPlatter, SGRPressScale);
    UIView *queueGlyph = connectGlyphIn(queue);
    if (queue) SGRPressGlyph(queue, queueGlyph ?: queue, host, kFooterPlatter, queueGlyph ? SGRPressScale : 0);

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SGLog(@"redesign player: footer lyrics at %.0f,%.0f (unit middle %.0f), connect %.0f (%@) to %.0f, queue %.0f to %.0f, share %@", lyrics.center.x, lyrics.center.y, middleY,
              connectFrom, glyph ? @"glyph" : @"button", round(width * kMiddle), queueFrom, queueX, share ? @"gone" : @"not found");
    });
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC20NowPlaying_ModesImpl18FooterElementsUnit", @"SPTEncoreIconView"]);
}
