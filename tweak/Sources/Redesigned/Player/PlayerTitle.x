// The song's title and artist as the redesign shows them: without the extras Simplify song titles takes off, and
// in the user's language when Translate song titles has a translation in (Shared/Lyrics, Shared/LyricsTranslation),
// in the Music app's type: the title 20 pt semibold over the artist 20 pt regular in the secondary color, and 17 over
// 17 while the lyrics have the player (Spotify's were 24 bold over 16). Spotify's own two labels on the player
// (now-playing-title-label, now-playing-subtitle-label, PlayerLyrics.x's tree; in 9.1.90 each an Encore marquee view
// drawing through a UILabel inside it, which is the one taken) are given a subclass of their own class that draws the
// shown text, font and color whenever Spotify sets its own, plain or attributed, the way key-value observing subclasses
// an object: no other label in the app is touched, and each still reads as its class.
//
// The row as the Music app lays it out (issue #27). Spotify's track info (9.1.90 phone tree, .mixdog/review-shots/
// phone-v100/trees/player-off-full-tree.txt:1856; 9.2.0, design/spotify-920/device/920-track-more-tree.txt:491) is one
// arranged view of the row's UIStackView, beside the add button's and the X's slots, which PlayerMenu.m puts away by
// alpha with the ⋯ standing in the add button's: the arranged view is given the room up to the ⋯ by a custom spacing
// after it, so the title and the artist reach the ⋯ and the marquee scrolls or ends there. With Star add button on the
// add button's slot stays, drawing the star, the ⋯ stands in the row's end after it, and the title reaches the star. Under the title, a
// UIStackView of badges leads the artist's line; in it a UIView holds each explicit mark, Components.UI.ExplicitIcon
// (a square "19" in Korea, "E" elsewhere) and Components.UI.19andOverIcon (a circled "19"), which Spotify shows or
// hides by the holder's hidden flag. The holders are kept hidden (each given a subclass of its own class whose
// setHidden: records Spotify's wish), the artist starts under the title when no other badge is left, and one mark is
// drawn after the title, the Music app's: the symbol for Spotify's mark ("19.circle.fill", "e.square.fill") in the
// secondary color, a little more than the title's cap height, centered on it and half its size after it, where it
// stays when the title is too long for the row, the title then ending that much sooner. It carries the shown
// mark's accessibility, and its identifier, so Hide explicit badge (Kit/SGRExplicitBadge.x) clears it too.
// A button of Spotify's arranged after the title (an episode's skip ad pill, the AI DJ's) stays beside it, the title
// ending Spotify's spacing and the mark's room short of it; the ⋯ standing in the row's end where the add button's slot
// is gone (an episode's row while the pill is up) has the row's arranged views end before it, by the row's trailing
// layout margin (issue #28).
// Beside the lyrics' thumbnail the arranged view is slid toward the trailing controls (PlayerLyrics.x), and the same
// spacing narrows it by the slide and a gap -- the row's trailing layout margin where nothing is arranged after it --
// so the title and the artist scroll or end, and the mark stands, short of them or of the row's end. The
// row is placed again whenever the title's container lays out (its class subclassed the same way), so the mark follows
// a width Spotify changes on its own, as when an episode's thumbnail comes in before the title.
#import <objc/runtime.h>
#import <objc/message.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRRefinements.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Fonts/Fonts.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"
#import "Shared/Player/PlayerState.h"
#import "Headers/SPTPlayer.h"
#import "Player.h"

static char kOriginalKey, kRoleKey, kWantsHiddenKey, kMarkKey, kSpacingKey, kMarginsKey, kTitleHoldKey, kAddKey;
// Spotify's add button, whose slot in the title row PlayerMenu.m gives the ⋯, or leaves to the star.
static NSString *const kAddButtonID = @"Components.UI.AddToButton";
// Spotify's own class's setText:, setFont:, setTextColor: and a mark holder's setHidden: for each subclass made, by
// the subclass and the selector. Found by the class the subclass was made of, never by the view's class at the time
// of the call: key-value observing can put a subclass of its own above this one, and the class above would then be
// this one, and the call would come back here forever.
static NSMutableDictionary<NSString *, NSValue *> *sg_setters;
static BOOL sg_simplify, sg_on, sg_placeQueued;
static __weak UILabel *sg_titleLabel, *sg_artistLabel;
// The views of Spotify's that carry the two ids: the marquees, or the labels themselves.
static __weak UIView *sg_titleView, *sg_artistView;
static NSString *const kLabelPrefix = @"SGRShownTitle_", *const kHolderPrefix = @"SGRHeldMark_", *const kContainerPrefix = @"SGRTitleRow_";
static BOOL sg_placing;
static NSString *const kExplicitID = @"Components.UI.ExplicitIcon", *const kAgeID = @"Components.UI.19andOverIcon";
// The Music app's mark beside a 20 pt title (design/issue27/IMG_2566.png): a circle from the title's cap height to
// its baseline and a little over (47 px against 45), half its width after the title's last letter (23 px).
static const CGFloat kMarkSidePerCapHeight = 1.1, kMarkGapPerSide = 0.5;
static const CGFloat kSlidGap = 12;  // between the title slid beside the lyrics' thumbnail and the trailing controls
static CGFloat sg_slide;             // how far the lyrics slide the title toward the trailing controls, 0 when they do not

// The one mark after the title.
@interface SGRTitleMark : UIImageView
@end
@implementation SGRTitleMark
@end

static void placeRow(void);

// The Music app's sizes: Title 3 in the player, Headline and Body beside the lyrics' thumbnail (PlayerLyrics.x), the
// two column player keeping the player's. Capped where the player's row still holds two lines of it. In the family the
// app draws in: the system font, which Fonts.x draws in the chosen one, unless Spotify's is drawn (Shared/Fonts,
// SGAppFontDrawn); then the family of `given`, the font Spotify set, at the Music app's size and weight.
static UIFont *shownFont(BOOL title, UIFont *given) {
    BOOL lyrics = SGRPlayerLyricsOpen() && !SGRPlayerTwoColumns();
    UIFontTextStyle style = lyrics ? (title ? UIFontTextStyleHeadline : UIFontTextStyleBody) : UIFontTextStyleTitle3;
    UIFontWeight weight = title ? UIFontWeightSemibold : UIFontWeightRegular;
    UIFont *system = SGCategoryCappedFont(style, weight, UIContentSizeCategoryExtraExtraExtraLarge);
    NSString *family = given.familyName;
    if (SGAppFontDrawn() != SGAppFontSpotify || !family.length) return system;
    UIFontDescriptor *descriptor = [UIFontDescriptor fontDescriptorWithFontAttributes:@{
        UIFontDescriptorFamilyAttribute: family,
        UIFontDescriptorTraitsAttribute: @{UIFontWeightTrait: @(weight)},
    }];
    return [UIFont fontWithDescriptor:descriptor size:system.pointSize];
}

static NSString *setterKey(Class class, SEL selector) {
    return [NSString stringWithFormat:@"%@ %@", NSStringFromClass(class), NSStringFromSelector(selector)];
}

// Spotify's implementation of `_cmd` for this view, from the nearest subclass of ours up its classes.
static IMP spotifys(UIView *view, SEL selector) {
    for (Class class = object_getClass(view); class; class = class_getSuperclass(class)) {
        NSValue *setter = sg_setters[setterKey(class, selector)];
        if (setter) return (IMP)setter.pointerValue;
    }
    return class_getMethodImplementation(UILabel.class, selector);
}

static BOOL isTitle(UILabel *label) {
    return [objc_getAssociatedObject(label, &kRoleKey) boolValue];
}

NSString *SGRShownTitle(NSString *trackID, NSString *title, NSString *artist, NSString **shownArtist) {
    NSString *translatedArtist = nil;
    NSString *translated = trackID ? SGLyricsTranslatedTitle(trackID, title, artist, &translatedArtist) : nil;
    NSString *shown = translated.length ? translated : title;
    if (sg_simplify && shown.length) shown = SGLyricsSimplifiedTitle(shown);
    if (shownArtist) *shownArtist = translatedArtist.length ? translatedArtist : artist;
    return shown;
}

static NSString *idOf(SPTPlayerTrack *track) {
    id uri = track.URI;
    NSString *text = [uri isKindOfClass:NSURL.class] ? ((NSURL *)uri).absoluteString : [uri description];
    return [text hasPrefix:@"spotify:track:"] ? [text substringFromIndex:@"spotify:track:".length] : nil;
}

// What the label draws for the text Spotify gave it; nil to draw Spotify's. Only the playing track's own title
// and artist are changed: an ad, a podcast or the DJ's words are left as they are.
static NSString *shownFor(BOOL title, NSString *text) {
    SPTPlayerTrack *track = SGPlayerState().track;
    if (!text.length || !track) return nil;
    if (![text isEqualToString:title ? track.trackTitle : track.artistName]) return nil;
    NSString *artist = nil;
    NSString *shown = SGRShownTitle(idOf(track), track.trackTitle, track.artistName, &artist);
    NSString *out = title ? shown : artist;
    return out.length && ![out isEqualToString:text] ? out : nil;
}

// The row is placed again once the run loop turns: the mark follows a title changed or a mark shown or hidden.
static void placeSoon(void) {
    if (sg_placeQueued) return;
    sg_placeQueued = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        sg_placeQueued = NO;
        placeRow();
    });
}

static void setShownText(UILabel *self, SEL _cmd, NSString *text) {
    NSString *shown = sg_on ? shownFor(isTitle(self), text) : nil;
    objc_setAssociatedObject(self, &kOriginalKey, text, OBJC_ASSOCIATION_COPY_NONATOMIC);
    ((void (*)(id, SEL, NSString *))spotifys(self, _cmd))(self, _cmd, shown ?: text);
    if (isTitle(self)) placeSoon();
}

// Spotify's attributes carry its font and color, so ours go over them once the text is in.
static void setShownAttributedText(UILabel *self, SEL _cmd, NSAttributedString *text) {
    BOOL title = isTitle(self);
    NSString *shown = sg_on ? shownFor(title, text.string) : nil;
    objc_setAssociatedObject(self, &kOriginalKey, text.string, OBJC_ASSOCIATION_COPY_NONATOMIC);
    NSDictionary *attributes = text.length ? [text attributesAtIndex:0 effectiveRange:NULL] : @{};
    NSAttributedString *drawn = shown ? [[NSAttributedString alloc] initWithString:shown attributes:attributes] : text;
    ((void (*)(id, SEL, NSAttributedString *))spotifys(self, _cmd))(self, _cmd, drawn);
    SEL font = @selector(setFont:), color = @selector(setTextColor:);
    UIFont *given = [attributes[NSFontAttributeName] isKindOfClass:UIFont.class] ? attributes[NSFontAttributeName] : self.font;
    ((void (*)(id, SEL, UIFont *))spotifys(self, font))(self, font, shownFont(title, given));
    if (!title) ((void (*)(id, SEL, UIColor *))spotifys(self, color))(self, color, SGRSecondary());
    if (title) placeSoon();
}

static void setShownFont(UILabel *self, SEL _cmd, UIFont *font) {
    ((void (*)(id, SEL, UIFont *))spotifys(self, _cmd))(self, _cmd, shownFont(isTitle(self), font));
}

// The artist in the secondary color; the title as Spotify paints it.
static void setShownColor(UILabel *self, SEL _cmd, UIColor *color) {
    ((void (*)(id, SEL, UIColor *))spotifys(self, _cmd))(self, _cmd, isTitle(self) ? color : SGRSecondary());
}

// Whether Spotify asked for the mark holder to be hidden; its own flag until it is held.
static BOOL wantsHidden(UIView *holder) {
    NSNumber *wish = objc_getAssociatedObject(holder, &kWantsHiddenKey);
    return wish ? wish.boolValue : holder.hidden;
}

// A held mark's holder stays hidden whatever Spotify asks, and the one mark after the title follows the wish.
static void setHeldHidden(UIView *self, SEL _cmd, BOOL hidden) {
    BOOL changed = wantsHidden(self) != hidden;
    objc_setAssociatedObject(self, &kWantsHiddenKey, @(hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ((void (*)(id, SEL, BOOL))spotifys(self, _cmd))(self, _cmd, YES);
    if (changed) placeSoon();
}

// The title's container laid out again, its width changed by Spotify (an episode's own thumbnail coming into the row)
// or the lyrics' slide: the row is placed again in the same pass, before it is drawn.
static void layoutTitleContainer(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))spotifys(self, _cmd))(self, _cmd);
    placeRow();
}

typedef struct { SEL selector; IMP ours; } SGROverride;

// `original` subclassed under `prefix` with `overrides` in place of its own methods, made once per class Spotify uses.
static Class subclassOf(Class original, NSString *prefix, const SGROverride *overrides, size_t count) {
    NSString *name = [prefix stringByAppendingString:NSStringFromClass(original)];
    Class made = NSClassFromString(name);
    if (made) return made;
    made = objc_allocateClassPair(original, name.UTF8String, 0);
    if (!made) return nil;
    if (!sg_setters) sg_setters = [NSMutableDictionary dictionary];
    for (size_t i = 0; i < count; i++) {
        Method method = class_getInstanceMethod(original, overrides[i].selector);
        sg_setters[setterKey(made, overrides[i].selector)] = [NSValue valueWithPointer:(void *)method_getImplementation(method)];
        class_addMethod(made, overrides[i].selector, overrides[i].ours, method_getTypeEncoding(method));
    }
    // The view still answers with Spotify's class, as one key-value observing has subclassed does.
    Class (^asked)(id) = ^Class(id me) { return original; };
    class_addMethod(made, @selector(class), imp_implementationWithBlock(asked), "#@:");
    objc_registerClassPair(made);
    return made;
}

// Whether `view` already runs as one of the subclasses made under `prefix`.
static BOOL madeUnder(UIView *view, NSString *prefix) {
    for (Class class = object_getClass(view); class; class = class_getSuperclass(class)) {
        if ([NSStringFromClass(class) hasPrefix:prefix]) return YES;
    }
    return NO;
}

static void adopt(UILabel *label, BOOL title) {
    if (![label isKindOfClass:UILabel.class]) return;
    if (!madeUnder(label, kLabelPrefix)) {
        SGROverride setters[] = {
            {@selector(setText:), (IMP)setShownText}, {@selector(setAttributedText:), (IMP)setShownAttributedText},
            {@selector(setFont:), (IMP)setShownFont}, {@selector(setTextColor:), (IMP)setShownColor},
        };
        Class shown = subclassOf(object_getClass(label), kLabelPrefix, setters, sizeof(setters) / sizeof(*setters));
        if (!shown) return;
        objc_setAssociatedObject(label, &kOriginalKey, label.text, OBJC_ASSOCIATION_COPY_NONATOMIC);
        object_setClass(label, shown);
    }
    objc_setAssociatedObject(label, &kRoleKey, @(title), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [label setText:objc_getAssociatedObject(label, &kOriginalKey)];
    [label setFont:label.font];
    [label setTextColor:label.textColor];
}

static void refresh(void) {
    UILabel *title = sg_titleLabel, *artist = sg_artistLabel;
    if (title) [title setText:objc_getAssociatedObject(title, &kOriginalKey)];
    if (artist) [artist setText:objc_getAssociatedObject(artist, &kOriginalKey)];
}

void SGRShownTitleRestyle(void) {
    for (UILabel *label in @[sg_titleLabel ?: (id)NSNull.null, sg_artistLabel ?: (id)NSNull.null]) {
        if ([label isKindOfClass:UILabel.class] && ![label.font isEqual:shownFont(isTitle(label), label.font)]) [label setFont:label.font];
    }
    placeRow();
}

// The label that draws for a view of Spotify's id: the view itself, or the UILabel an Encore marquee draws through.
static UILabel *drawingLabel(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) return (UILabel *)view;
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:UILabel.class]) return (UILabel *)sub;
    }
    return nil;
}

#pragma mark - the row

// Where Spotify's layout puts `view` in its superview, a transform of the lyrics' (PlayerLyrics.x) or this file's left out.
static CGRect untransformed(UIView *view) {
    CGSize size = view.bounds.size;
    return CGRectMake(view.center.x - size.width / 2, view.center.y - size.height / 2, size.width, size.height);
}

// Spotify's mark under `root` with the id, never the one drawn here, which carries the same id.
static UIView *spotifyMark(UIView *root, NSString *identifier) {
    if ([root isKindOfClass:SGRTitleMark.class]) return nil;
    if ([root.accessibilityIdentifier isEqualToString:identifier]) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = spotifyMark(sub, identifier);
        if (found) return found;
    }
    return nil;
}

// The view arranged in a stack view that holds `view`, under `root`; nil when none does.
static UIView *arrangedHolder(UIView *view, UIView *root) {
    for (UIView *v = view; v && v != root; v = v.superview) {
        if ([v.superview isKindOfClass:UIStackView.class] && [((UIStackView *)v.superview).arrangedSubviews containsObject:v]) return v;
    }
    return nil;
}

// The Music app's symbol for the mark Spotify writes: a number in a circle, a letter in a square; nil for any other.
static UIImage *markGlyph(NSString *text) {
    if (!text.length) return nil;
    BOOL number = [text rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound;
    NSString *name = [NSString stringWithFormat:number ? @"%@.circle.fill" : @"%@.square.fill", text.lowercaseString];
    return [UIImage systemImageNamed:name];
}

static CGFloat markSide(UIFont *font) {
    return font.capHeight * kMarkSidePerCapHeight;
}

// How far below the label's top its line's baseline is drawn: the label centers the line text layout gives its text,
// whose baseline is not the font's ascender (UIKit rounds the line).
static CGFloat baselineOffset(UILabel *label) {
    NSTextStorage *storage = [[NSTextStorage alloc] initWithAttributedString:label.attributedText];
    NSLayoutManager *layout = [NSLayoutManager new];
    NSTextContainer *box = [[NSTextContainer alloc] initWithSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
    box.lineFragmentPadding = 0;
    [layout addTextContainer:box];
    [storage addLayoutManager:layout];
    if (!layout.numberOfGlyphs) return label.font.ascender;
    CGRect line = [layout lineFragmentUsedRectForGlyphAtIndex:0 effectiveRange:NULL];
    return (label.bounds.size.height - line.size.height) / 2 + [layout locationForGlyphAtIndex:0].y;
}

// Holds the row's arranged views `hold` in from its trailing edge beyond where Spotify's margins end them, by the row's
// trailing layout margin; 0 puts Spotify's margin arrangement back. YES when the row's margins changed.
static BOOL holdTrailing(UIStackView *row, CGFloat hold) {
    NSArray *spotifys = objc_getAssociatedObject(row, &kMarginsKey);
    if (hold < 0.25) {
        if (!spotifys) return NO;
        row.layoutMarginsRelativeArrangement = [spotifys[0] boolValue];
        row.directionalLayoutMargins = [spotifys[1] directionalEdgeInsetsValue];
        row.insetsLayoutMarginsFromSafeArea = [spotifys[2] boolValue];
        objc_setAssociatedObject(row, &kMarginsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return YES;
    }
    if (!spotifys) {
        spotifys = @[@(row.layoutMarginsRelativeArrangement), [NSValue valueWithDirectionalEdgeInsets:row.directionalLayoutMargins],
                     @(row.insetsLayoutMarginsFromSafeArea)];
        objc_setAssociatedObject(row, &kMarginsKey, spotifys, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BOOL relative = [spotifys[0] boolValue];
    NSDirectionalEdgeInsets margins = relative ? [spotifys[1] directionalEdgeInsetsValue] : NSDirectionalEdgeInsetsZero;
    margins.trailing += hold;
    if (fabs(row.directionalLayoutMargins.trailing - margins.trailing) < 0.25 && row.layoutMarginsRelativeArrangement) return NO;
    if (!relative) {
        row.insetsLayoutMarginsFromSafeArea = NO;
        row.layoutMarginsRelativeArrangement = YES;
    }
    row.directionalLayoutMargins = margins;
    return YES;
}

// The ⋯ (PlayerMenu.m): the nearest view on the title's trailing side that is still to be seen and is not arranged; nil
// where there is none (the AI DJ's row).
static UIView *moreIn(UIStackView *row, UIView *element, BOOL rtl) {
    NSArray<UIView *> *arranged = row.arrangedSubviews;
    CGRect own = untransformed(element);
    UIView *more = nil;
    for (UIView *view in row.subviews) {
        if ([arranged containsObject:view] || view.hidden || view.alpha < 0.01 || view.bounds.size.width < 1) continue;
        CGRect frame = view.frame;
        if (!(rtl ? CGRectGetMaxX(frame) < CGRectGetMaxX(own) : CGRectGetMinX(frame) > CGRectGetMinX(own))) continue;
        if (!more || (rtl ? CGRectGetMaxX(frame) > CGRectGetMaxX(more.frame) : CGRectGetMinX(frame) < CGRectGetMinX(more.frame))) more = view;
    }
    return more;
}

// Spotify's add button's arranged slot while Spotify shows it, nil when it is gone. PlayerMenu.m, after the title's
// layout, puts it away for the ⋯ standing in it, or with Star add button on keeps the star in it and the ⋯ in the row's
// end. Read from the slot rather than from where the ⋯ was drawn last, which is a pass behind Spotify bringing the
// slot back or taking it away.
static UIView *addSlotIn(UIStackView *row) {
    UIView *slot = SGRFindByIdentifier(row, kAddButtonID, &kAddKey);
    while (slot && slot.superview != row) slot = slot.superview;
    return slot && !slot.hidden ? slot : nil;
}

// The title row as the Music app's: the title, any button of Spotify's arranged after it (an episode's skip ad pill,
// the AI DJ's) and the ⋯ (PlayerMenu.m) side by side, never over one another.
// The ⋯ standing in the row's end (a row without the add button, an episode's while its skip ad pill is up, or any row
// with Star add button on, the star kept in the add button's slot) has the row's arranged views end before it by the
// row's trailing margin. The title's arranged view then reaches the ⋯ or the star where it is the nearest view on its
// trailing side, by a custom spacing after it, or the margin where nothing is arranged
// after the title; ends Spotify's spacing short of an arranged view of Spotify's seen first (the pill); and in either,
// `markRoom` sooner when the title is too long to leave the mark room. Slid by the lyrics, it reaches the nearest view
// on its trailing side, else the row's end, less the slide and kSlidGap. Where none of these asks for room, Spotify's
// spacing and margins are put back.
static void widenRow(UIView *titleView, UILabel *title, CGFloat markRoom) {
    UIView *element = arrangedHolder(titleView, nil);
    UIStackView *row = (UIStackView *)element.superview;
    if (!row || row.axis != UILayoutConstraintAxisHorizontal) return;
    BOOL rtl = row.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    NSArray<UIView *> *arranged = row.arrangedSubviews;
    UIView *next = nil;
    for (NSUInteger i = [arranged indexOfObject:element] + 1; i < arranged.count && !next; i++) {
        if (!arranged[i].hidden) next = arranged[i];
    }
    // The add button's slot, where the ⋯ or the star stands: the title reaches it, the ⋯ there counted though put away.
    UIView *more = moreIn(row, element, rtl), *addSlot = more ? addSlotIn(row) : nil;
    // The ⋯ in the row's end takes its own width there.
    CGFloat moreRoom = more && (!addSlot || SGRStarAddOn()) ? more.bounds.size.width : 0;
    // What stands after the title placed first: the title's own hold kept only while nothing is arranged after it.
    CGFloat titleHold = next ? 0 : [objc_getAssociatedObject(row, &kTitleHoldKey) doubleValue];
    if (holdTrailing(row, moreRoom + titleHold)) [row layoutIfNeeded];

    CGRect own = untransformed(element);
    UIView *edgeView = nil;
    // The row's own end when nothing is seen on the title's trailing side.
    CGFloat edge = rtl ? CGRectGetMinX(row.bounds) : CGRectGetMaxX(row.bounds);
    // The ⋯ counted where the menu puts it this pass, its slot (put away, alpha 0) or the row's end, not where it is.
    for (UIView *view in row.subviews) {
        if (view == element || view == more || view.hidden || (view.alpha < 0.01 && view != addSlot) || view.bounds.size.width < 1) continue;
        CGRect frame = view.frame;
        BOOL trailing = rtl ? CGRectGetMaxX(frame) < CGRectGetMaxX(own) : CGRectGetMinX(frame) > CGRectGetMinX(own);
        CGFloat x = rtl ? CGRectGetMaxX(frame) : CGRectGetMinX(frame);
        if (trailing && (rtl ? x > edge : x < edge)) {
            edgeView = view;
            edge = x;
        }
    }
    CGFloat moreEnd = rtl ? CGRectGetMinX(row.bounds) + moreRoom : CGRectGetMaxX(row.bounds) - moreRoom;
    if (moreRoom > 0 && (rtl ? moreEnd > edge : moreEnd < edge)) {
        edgeView = more;
        edge = moreEnd;
    }
    NSNumber *spotifys = objc_getAssociatedObject(element, &kSpacingKey);
    if (!spotifys) {
        spotifys = @([row customSpacingAfterView:element]);
        objc_setAssociatedObject(element, &kSpacingKey, spotifys, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BOOL spotifysView = edgeView && edgeView != addSlot && [arranged containsObject:edgeView];
    CGFloat spotifysGap = spotifys.doubleValue == UIStackViewSpacingUseDefault ? row.spacing : spotifys.doubleValue;
    CGFloat stop = sg_slide ? sg_slide + kSlidGap : spotifysView ? spotifysGap : 0;
    CGFloat reach = (rtl ? CGRectGetMaxX(own) - edge : edge - CGRectGetMinX(own)) - stop;
    CGFloat inset = own.size.width - titleView.bounds.size.width;
    BOOL crowded = markRoom > 0 && title.intrinsicContentSize.width + markRoom > reach - inset;
    BOOL bounded = sg_slide || crowded || (edgeView && !spotifysView);
    // Where the title's arranged view is to end, from its leading edge and what stands after it, neither of which the
    // spacing after it or the title's hold moves: each pass sets the same values, never one rounded from the last.
    CGFloat room = reach - (crowded ? markRoom : 0);
    CGFloat end = rtl ? CGRectGetMaxX(own) - room : CGRectGetMinX(own) + room;
    CGFloat spacing = spotifys.doubleValue;
    if (bounded && next) spacing = rtl ? end - CGRectGetMaxX(next.frame) : CGRectGetMinX(next.frame) - end;
    // The last arranged view ends at the ⋯ or the row's end (the margin above), less the hold.
    CGFloat hold = bounded && !next ? stop + (crowded ? markRoom : 0) : 0;
    BOOL changed = holdTrailing(row, moreRoom + hold);
    CGFloat current = [row customSpacingAfterView:element];
    if (spacing == spotifys.doubleValue ? current != spacing : fabs(current - spacing) >= 0.25) {
        [row setCustomSpacing:spacing afterView:element];
        changed = YES;
    }
    objc_setAssociatedObject(row, &kTitleHoldKey, hold ? @(hold) : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (changed) [row layoutIfNeeded];
}

// The mark `title` ends with, in its container: after its last letter, or after the marquee's end when the title is
// longer than it is, centered on the letters' cap height.
static void placeMark(SGRTitleMark *mark, UIView *titleView, UILabel *title) {
    UIView *container = mark.superview;
    [container layoutIfNeeded];
    BOOL rtl = container.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGRect box = untransformed(titleView);
    CGRect label = title == titleView ? box : [title.superview convertRect:title.frame toView:container];
    UIFont *font = title.font;
    CGFloat side = markSide(font), gap = side * kMarkGapPerSide, text = title.intrinsicContentSize.width;
    BOOL longer = text > box.size.width + 0.5;
    CGFloat end = rtl ? (longer ? CGRectGetMinX(box) : MAX(CGRectGetMinX(box), CGRectGetMaxX(label) - text))
                      : (longer ? CGRectGetMaxX(box) : MIN(CGRectGetMaxX(box), CGRectGetMinX(label) + text));
    CGFloat baseline = CGRectGetMinY(label) + baselineOffset(title);
    CGRect frame = CGRectMake(rtl ? end - gap - side : end + gap, baseline - font.capHeight / 2 - side / 2, side, side);
    if (!CGRectEqualToRect(mark.frame, frame)) mark.frame = frame;
    UIImageSymbolConfiguration *size = [UIImageSymbolConfiguration configurationWithPointSize:side];
    if (![mark.preferredSymbolConfiguration isEqual:size]) mark.preferredSymbolConfiguration = size;
    if (![mark.tintColor isEqual:SGRSecondary()]) mark.tintColor = SGRSecondary();
}

static void placeRowNow(void) {
    UIView *titleView = sg_titleView, *artistView = sg_artistView;
    UILabel *title = sg_titleLabel;
    UIView *container = titleView.superview;
    if (!title || !container) return;
    if (!madeUnder(container, kContainerPrefix)) {
        SGROverride laying[] = {{@selector(layoutSubviews), (IMP)layoutTitleContainer}};
        Class watched = subclassOf(object_getClass(container), kContainerPrefix, laying, 1);
        if (watched) object_setClass(container, watched);
    }
    // Spotify's marks, the circled one first: the shown one is drawn and both holders stay hidden.
    NSMutableArray<UIView *> *holders = [NSMutableArray array];
    UIView *shown = nil;
    UIImage *glyph = nil;
    for (NSString *identifier in @[kAgeID, kExplicitID]) {
        UIView *spotify = spotifyMark(container, identifier);
        UIView *holder = arrangedHolder(spotify, container);
        UIImage *drawn = markGlyph(drawingLabel(spotify).text);
        if (!holder) continue;
        if (!drawn) {
            static BOOL logged;
            if (!logged) SGLog(@"redesign player: no symbol for Spotify's mark \"%@\", which stays as Spotify draws it", drawingLabel(spotify).text);
            logged = YES;
            continue;
        }
        if (!madeUnder(holder, kHolderPrefix)) {
            SGROverride hiding[] = {{@selector(setHidden:), (IMP)setHeldHidden}};
            Class held = subclassOf(object_getClass(holder), kHolderPrefix, hiding, 1);
            if (!held) continue;
            BOOL wish = holder.hidden;
            object_setClass(holder, held);
            holder.hidden = wish;
        }
        [holders addObject:holder];
        if (!shown && !wantsHidden(holder)) {
            shown = spotify;
            glyph = drawn;
        }
    }
    SGRTitleMark *mark = objc_getAssociatedObject(container, &kMarkKey);
    if (!mark && shown) {
        mark = [SGRTitleMark new];
        mark.contentMode = UIViewContentModeScaleAspectFit;
        objc_setAssociatedObject(container, &kMarkKey, mark, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (mark && mark.superview != container) [container insertSubview:mark aboveSubview:titleView];
    if (mark.hidden != !shown) mark.hidden = !shown;
    if (shown) {
        if (![mark.image isEqual:glyph]) mark.image = glyph;
        mark.isAccessibilityElement = shown.isAccessibilityElement;
        mark.accessibilityLabel = shown.accessibilityLabel;
        mark.accessibilityTraits = shown.accessibilityTraits;
        if (![mark.accessibilityIdentifier isEqualToString:kExplicitID]) mark.accessibilityIdentifier = kExplicitID;
    }
    // The artist starts under the title once no other badge leads its line.
    UIStackView *badges = (UIStackView *)holders.firstObject.superview;
    if (badges && artistView.superview == container) {
        BOOL others = NO;
        for (UIView *badge in badges.arrangedSubviews) others |= !badge.hidden && badge.alpha > 0.01;
        BOOL rtl = container.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
        CGRect from = untransformed(artistView), to = untransformed(titleView);
        CGFloat dx = others ? 0 : (rtl ? CGRectGetMaxX(to) - CGRectGetMaxX(from) : CGRectGetMinX(to) - CGRectGetMinX(from));
        CGAffineTransform move = CGAffineTransformMakeTranslation(dx, 0);
        if (!CGAffineTransformEqualToTransform(artistView.transform, move)) artistView.transform = move;
    }
    BOOL drawn = shown && !SGFlag(SGRKeyHideExplicit, NO);
    CGFloat side = markSide(title.font);
    widenRow(titleView, title, drawn ? side + side * kMarkGapPerSide : 0);
    if (shown) placeMark(mark, titleView, title);
}

// Once at a time: placing the row lays the container out, which would place it again.
static void placeRow(void) {
    if (sg_placing) return;
    sg_placing = YES;
    placeRowNow();
    sg_placing = NO;
}

void SGRShownTitleSlide(CGFloat slide) {
    sg_slide = slide;
    placeRow();
}

void SGRShownTitleWatch(UIView *unit) {
    if (!unit) return;
    sg_titleView = SGRFindByIdentifier(unit, @"now-playing-title-label", NULL);
    sg_artistView = SGRFindByIdentifier(unit, @"now-playing-subtitle-label", NULL);
    UILabel *title = drawingLabel(sg_titleView);
    UILabel *artist = drawingLabel(sg_artistView);
    if ([title isKindOfClass:UILabel.class] && sg_titleLabel != title) {
        sg_titleLabel = title;
        adopt(title, YES);
    }
    if ([artist isKindOfClass:UILabel.class] && sg_artistLabel != artist) {
        sg_artistLabel = artist;
        adopt(artist, NO);
    }
    // A Dynamic Type change or the two columns coming or going reach the type on the row's next pass.
    SGRShownTitleRestyle();
}

static void readTitleSettings(void) {
    sg_simplify = SGFlag(SGKeyLyricsSimplifyTitles, NO);
    sg_on = sg_simplify || SGFlag(SGKeyLyricsTranslateTitles, NO);
}

%ctor {
    if (!SGRedesignedUI()) return;
    readTitleSettings();
    for (NSString *name in @[SGSimplifyTitlesDidChangeNotification, SGTranslatedTitleDidChangeNotification,
                             SGTitleTranslationSettingsDidChangeNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{
                BOOL wasOn = sg_on;
                readTitleSettings();
                if (wasOn || sg_on) refresh();
            });
        }];
    }
    if (sg_on) SGLog(@"redesign player: titles shown %@%@", sg_simplify ? @"simplified" : @"as they are", SGFlag(SGKeyLyricsTranslateTitles, NO) ? @", translated" : @"");
}
