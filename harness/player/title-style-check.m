// The player's title and artist styling (PlayerTitle.x, compiled through Logos) on labels shaped as Spotify's: the title
// a marquee view drawing through a UILabel inside it (9.1.90's Encore marquee), the artist a label. Spotify's setters
// are called as Spotify calls them, with a stand-in for its family (Georgia), and the type is read off the labels.
// Then the title row as 9.2.0 builds it (runRow): the title reaching the ⋯ and one explicit mark after it, closed and
// slid beside the lyrics' thumbnail as PlayerLyrics.x moves it.
#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "Shared/Fonts/Fonts.h"
#import "Shared/Player/PlayerState.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Player/Player.h"
#import "../harness-fail.h"

@implementation SPTPlayerTrack
@end
@implementation SPTPlayerState
@end

static SGAppFont drawn = SGAppFontSystem;
static BOOL lyricsOpen, starAdd;
static int checked, failed;

SGAppFont SGAppFontDrawn(void) { return drawn; }
BOOL SGRStarAddOn(void) { return starAdd; }
BOOL SGRedesignedUI(void) { return YES; }
BOOL SGFlag(NSString *key, BOOL fallback) { return fallback; }
NSInteger SGInt(NSString *key, NSInteger fallback) { return fallback; }
void SGPresentDark(UIViewController *controller) {}
UIColor *SGRAccentColor(void) { return nil; }
SPTPlayerState *SGPlayerState(void) { return nil; }
BOOL SGRPlayerLyricsOpen(void) { return lyricsOpen; }
BOOL SGRPlayerTwoColumns(void) { return NO; }
NSString *SGLyricsTranslatedTitle(NSString *trackID, NSString *title, NSString *artist, NSString **artistOut) { return nil; }
NSString *SGLyricsSimplifiedTitle(NSString *title) { return title; }
NSNotificationName const SGTranslatedTitleDidChangeNotification = @"title-style.translated";
NSNotificationName const SGTitleTranslationSettingsDidChangeNotification = @"title-style.settings";
NSNotificationName const SGSimplifyTitlesDidChangeNotification = @"title-style.simplify";
UIView *SGRFindByIdentifier(UIView *root, NSString *identifier, const void *cacheKey) {
    if ([root.accessibilityIdentifier isEqualToString:identifier]) return root;
    for (UIView *child in root.subviews) {
        UIView *found = SGRFindByIdentifier(child, identifier, cacheKey);
        if (found) return found;
    }
    return nil;
}

static void check(BOOL ok, NSString *what) {
    checked++;
    if (!ok) failed++;
    printf("%s %s\n", ok ? "PASS" : "FAIL", what.UTF8String);
    fflush(stdout);
}
static CGFloat weightOf(UIFont *font) {
    return [[font.fontDescriptor objectForKey:UIFontDescriptorTraitsAttribute][UIFontWeightTrait] doubleValue];
}
// The height a fresh label gives the same text in `font`: what the row's layout must make room for.
static CGFloat heightFor(NSString *text, UIFont *font) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = font;
    return label.intrinsicContentSize.height;
}

// Spotify's Encore marquee as the trees show it: a clipping view drawing through a UILabel sized to its text, at the
// leading end while the text fits.
@interface MarqueeMock : UIView
@property (nonatomic, strong) UILabel *label;
@end
@implementation MarqueeMock
- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.label.intrinsicContentSize;
    BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGFloat x = rtl && size.width < self.bounds.size.width ? self.bounds.size.width - size.width : 0;
    self.label.frame = CGRectMake(x, (self.bounds.size.height - size.height) / 2, size.width, size.height);
}
@end

// The information unit's title row as Spotify 9.2.0 builds it (design/spotify-920/device/920-track-more-tree.txt:476-528)
// in the redesign's 32 pt margins: a row stack of the track info, Spotify's X (24 pt) and add button (48 pt) 12 pt
// apart, both put away by alpha with the ⋯ standing in the add button's slot (PlayerMenu.m), or with Star add button on
// the add button's kept for the star and the ⋯ standing in the row's end; in the track info the
// title marquee over a stack of badges leading the artist marquee 8 pt after it, the two explicit marks each in a
// 12 pt holder Spotify hides or shows.
typedef struct {
    UIView *unit, *thumb, *element, *container, *more, *ageHolder, *explicitHolder, *speed, *addSlot, *pill;
    UIStackView *row, *badges;
    MarqueeMock *title, *artist;
} Row;

static NSArray<UIView *> *allViews(UIView *root) {
    NSMutableArray *views = [NSMutableArray arrayWithObject:root];
    for (UIView *child in root.subviews) [views addObjectsFromArray:allViews(child)];
    return views;
}

static UIView *markHolder(NSString *identifier) {
    UIView *holder = [UIView new], *mark = [UIView new];
    UILabel *text = [UILabel new];
    mark.accessibilityIdentifier = identifier;
    mark.isAccessibilityElement = YES;
    mark.accessibilityLabel = @"19";
    text.text = @"19";
    text.font = [UIFont systemFontOfSize:8];
    mark.frame = text.frame = CGRectMake(0, 0, 12, 12);
    [mark addSubview:text];
    [holder addSubview:mark];
    [holder.widthAnchor constraintEqualToConstant:12].active = YES;
    holder.hidden = YES;
    return holder;
}

static MarqueeMock *marquee(NSString *identifier, NSString *text, UIFont *font) {
    MarqueeMock *view = [MarqueeMock new];
    view.accessibilityIdentifier = identifier;
    view.clipsToBounds = YES;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.label = [UILabel new];
    view.label.text = text;
    view.label.font = font;
    [view addSubview:view.label];
    return view;
}

// The trailing ends a title row is seen with: the ⋯ in Spotify's put away add button's slot; no add button, Spotify's
// slots hidden and the ⋯ standing in the row's end (PlayerMenu.m's fallback, as for a local file); the AI DJ's, no ⋯
// and a 48 pt button of Spotify's arranged after the title; nothing at all after the title; and an episode's with
// Spotify's skip ad pill up (SkipAdButtonProps, arranged between the title and the X's slot, 9.2.0 tree), the add
// button's slot after it holding the ⋯, or hidden with the ⋯ in the row's end (issue #28's iPad); and Star add
// button's, the add button's slot drawing the star with Spotify's X put away and the ⋯ in the row's end (issue #44).
typedef NS_ENUM(NSInteger, RowShape) { RowAddSlot, RowNoAddSlot, RowDJ, RowBare, RowPill, RowPillNoAdd, RowStar };
static NSString *const kShapeNames[] = {@"with the ⋯ in the add button's slot", @"without an add button", @"of the AI DJ",
                                        @"with nothing after the title", @"with the skip pill and the ⋯ in the add button's slot",
                                        @"with the skip pill and no add button", @"with the star and the ⋯ in the row's end"};
// The pill as 9.2.0 draws "건너뛰기": a 16 pt icon, the word and 13 pt insets (design/issue28/IMG_0116.png, 91 pt).
static const CGFloat kPillWidth = 91;

static Row buildRow(UIWindow *window, NSString *title, BOOL rtl, RowShape shape, NSString *artistText) {
    Row r = {0};
    r.unit = [[UIView alloc] initWithFrame:CGRectMake(0, 200, 402, 64)];
    r.row = [[UIStackView alloc] initWithFrame:CGRectMake(32, 8, 338, 48)];
    r.row.spacing = 12;
    r.element = [UIView new];
    [r.element setContentHuggingPriority:UILayoutPriorityDefaultLow - 1 forAxis:UILayoutConstraintAxisHorizontal];
    [r.element setContentCompressionResistancePriority:UILayoutPriorityDefaultLow - 1 forAxis:UILayoutConstraintAxisHorizontal];
    UIView *banSlot = [UIView new];
    r.addSlot = [UIView new];
    [banSlot.widthAnchor constraintEqualToConstant:24].active = YES;
    [r.addSlot.widthAnchor constraintEqualToConstant:48].active = YES;
    banSlot.alpha = 0;
    r.addSlot.alpha = shape == RowDJ || shape == RowStar ? 1 : 0;
    banSlot.hidden = shape != RowAddSlot && shape != RowPill && shape != RowStar;
    r.addSlot.hidden = shape == RowNoAddSlot || shape == RowBare || shape == RowPillNoAdd;
    if (shape != RowDJ) {
        UIView *add = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 48, 48)];
        add.accessibilityIdentifier = @"Components.UI.AddToButton";
        [r.addSlot addSubview:add];
    }
    // An episode's own 48 pt thumbnail, which Spotify shows before the title on its own (9.2.0, a video episode).
    r.thumb = [UIView new];
    [r.thumb.widthAnchor constraintEqualToConstant:48].active = YES;
    r.thumb.hidden = YES;
    r.pill = [UIView new];
    r.pill.backgroundColor = UIColor.darkGrayColor;
    [r.pill.widthAnchor constraintEqualToConstant:kPillWidth].active = YES;
    r.pill.hidden = shape != RowPill && shape != RowPillNoAdd;
    for (UIView *view in @[r.thumb, r.element, r.pill, banSlot, r.addSlot]) [r.row addArrangedSubview:view];
    r.container = [UIView new];
    r.container.translatesAutoresizingMaskIntoConstraints = NO;
    [r.element addSubview:r.container];
    UIFont *spotifyTitle = [UIFont fontWithName:@"Georgia-Bold" size:24], *spotifyArtist = [UIFont fontWithName:@"Georgia" size:16];
    r.title = marquee(@"now-playing-title-label", title, spotifyTitle);
    r.artist = marquee(@"now-playing-subtitle-label", artistText, spotifyArtist);
    r.badges = [UIStackView new];
    r.badges.spacing = 2;
    r.badges.translatesAutoresizingMaskIntoConstraints = NO;
    r.ageHolder = markHolder(@"Components.UI.19andOverIcon");
    r.explicitHolder = markHolder(@"Components.UI.ExplicitIcon");
    r.speed = [UIView new];
    [r.speed.widthAnchor constraintEqualToConstant:12].active = YES;
    r.speed.hidden = YES;
    for (UIView *view in @[r.explicitHolder, r.ageHolder, r.speed]) [r.badges addArrangedSubview:view];
    for (UIView *view in @[r.title, r.badges, r.artist]) [r.container addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [r.container.leadingAnchor constraintEqualToAnchor:r.element.leadingAnchor],
        [r.container.trailingAnchor constraintEqualToAnchor:r.element.trailingAnchor],
        [r.container.topAnchor constraintEqualToAnchor:r.element.topAnchor],
        [r.container.bottomAnchor constraintEqualToAnchor:r.element.bottomAnchor],
        [r.title.leadingAnchor constraintEqualToAnchor:r.container.leadingAnchor],
        [r.title.trailingAnchor constraintEqualToAnchor:r.container.trailingAnchor],
        [r.title.topAnchor constraintEqualToAnchor:r.container.topAnchor],
        [r.title.heightAnchor constraintEqualToConstant:28],
        [r.badges.leadingAnchor constraintEqualToAnchor:r.container.leadingAnchor],
        [r.badges.topAnchor constraintEqualToAnchor:r.title.bottomAnchor],
        [r.badges.heightAnchor constraintEqualToConstant:20],
        [r.artist.leadingAnchor constraintEqualToAnchor:r.badges.trailingAnchor constant:8],
        [r.artist.trailingAnchor constraintEqualToAnchor:r.container.trailingAnchor],
        [r.artist.topAnchor constraintEqualToAnchor:r.title.bottomAnchor],
        [r.artist.heightAnchor constraintEqualToConstant:20],
    ]];
    [r.unit addSubview:r.row];
    [window addSubview:r.unit];
    if (rtl) {
        for (UIView *view in allViews(r.unit)) view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    }
    [r.row layoutIfNeeded];
    if (shape == RowDJ || shape == RowBare) return r;
    UIButton *more = [UIButton buttonWithType:UIButtonTypeSystem];
    CGRect bounds = r.row.bounds;
    more.frame = !r.addSlot.hidden && shape != RowStar ? r.addSlot.frame : CGRectMake(rtl ? 0 : CGRectGetMaxX(bounds) - 48, 0, 48, 48);
    [r.row addSubview:more];
    r.more = more;
    return r;
}

static UIView *drawnMark(Row r) {
    for (UIView *view in r.container.subviews) {
        if ([NSStringFromClass(view.class) isEqualToString:@"SGRTitleMark"]) return view;
    }
    return nil;
}

static NSUInteger marksSeen(Row r) {
    NSUInteger seen = 0;
    for (UIView *view in allViews(r.container)) {
        BOOL mark = [NSStringFromClass(view.class) isEqualToString:@"SGRTitleMark"]
            || [view.accessibilityIdentifier hasPrefix:@"Components.UI.19andOverIcon"] || [view.accessibilityIdentifier hasPrefix:@"Components.UI.ExplicitIcon"];
        BOOL shown = YES;
        for (UIView *v = view; v && v != r.unit; v = v.superview) shown &= !v.hidden && v.alpha > 0.01;
        if (mark && shown && view.bounds.size.width > 0 && view.window) seen++;
    }
    return seen;
}

static CGRect inRow(Row r, UIView *view) {
    return [view.superview convertRect:view.frame toView:r.row];
}

// The ink of the title's first letter, drawn by the label itself: its cap top and baseline in the container.
static void capOf(Row r, CGFloat *top, CGFloat *bottom) {
    UILabel *label = r.title.label;
    CGFloat scale = 3;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = scale;
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:label.bounds.size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [label.layer renderInContext:context.CGContext];
    }];
    CGImageRef cg = image.CGImage;
    size_t w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
    uint8_t *pixels = calloc(w * h, 4);
    CGContextRef context = CGBitmapContextCreate(pixels, w, h, 8, w * 4, CGColorSpaceCreateDeviceRGB(), (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(context, CGRectMake(0, 0, w, h), cg);
    long first = -1, last = -1;
    for (size_t y = 0; y < h; y++) {
        for (size_t x = 0; x < (size_t)(10 * scale) && x < w; x++) {
            if (pixels[(y * w + x) * 4 + 3] > 128) {
                if (first < 0) first = (long)y;
                last = (long)y;
                break;
            }
        }
    }
    CGContextRelease(context);
    free(pixels);
    CGFloat origin = [label.superview convertPoint:label.frame.origin toView:r.container].y;
    *top = origin + first / scale;
    *bottom = origin + (last + 1) / scale;
}

// Until the work queued on the main queue so far has run, however busy the Mac is.
static void settle(void) {
    __block BOOL reached = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ reached = YES; });
    while (!reached) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

// The lyrics coming (`slide` > 0) or going as PlayerLyrics.x moves the row: the type for them, then the title's
// arranged view slid toward the ⋯ by the thumbnail's 72 pt and its 16 pt gap, mirrored right to left.
static const CGFloat kLyricsSlide = 72 + 16;
static void slideRow(Row r, CGFloat slide) {
    lyricsOpen = slide > 0;
    SGRShownTitleRestyle();
    SGRShownTitleSlide(slide);
    BOOL rtl = r.row.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    r.element.transform = CGAffineTransformMakeTranslation(rtl ? -slide : slide, 0);
    settle();
}

// Whether all of `view` is drawn: no view or mask over it up to the window cuts any of it.
static BOOL shownWhole(UIView *view) {
    for (UIView *v = view.superview; v; v = v.superview) {
        CGRect in = [view convertRect:view.bounds toView:v];
        if ((v.clipsToBounds || !v.superview) && !CGRectContainsRect(CGRectInset(v.bounds, -0.5, -0.5), in)) return NO;
        if (v.layer.mask && !CGRectContainsRect(CGRectInset(v.layer.mask.frame, -0.5, -0.5), in)) return NO;
    }
    return YES;
}

static void runRow(UIWindow *window) {
    drawn = SGAppFontSystem;
    lyricsOpen = NO;
    // A plain song with a short title: the title's view reaches the ⋯, over Spotify's X and the add button's gap.
    Row r = buildRow(window, @"Whiplash - Remastered", NO, RowAddSlot, @"Metallica");
    CGRect addSlot = inRow(r, r.addSlot);
    SGRShownTitleWatch(r.unit);
    settle();
    check(fabs(CGRectGetMaxX(inRow(r, r.element)) - CGRectGetMinX(r.more.frame)) < 0.5 && CGRectEqualToRect(inRow(r, r.addSlot), addSlot),
          [NSString stringWithFormat:@"the title's view ends at the ⋯ (%.1f, ⋯ at %.1f; Spotify's ended at 242)",
           CGRectGetMaxX(inRow(r, r.element)), CGRectGetMinX(r.more.frame)]);
    check(marksSeen(r) == 0, @"a song that is not explicit shows no mark");

    // Explicit: Spotify shows both of its marks, as in IMG_2565.
    r.ageHolder.hidden = NO;
    r.explicitHolder.hidden = NO;
    settle();
    UIView *mark = drawnMark(r);
    check(marksSeen(r) == 1 && mark && !mark.hidden, [NSString stringWithFormat:@"an explicit song shows one mark (%lu)", (unsigned long)marksSeen(r)]);
    check(r.ageHolder.hidden && r.explicitHolder.hidden, @"Spotify's two marks before the artist are gone");
    check([mark.accessibilityLabel isEqualToString:@"19"] && mark.isAccessibilityElement, @"VoiceOver reads the mark as Spotify's");
    check([((UIImageView *)mark).image isEqual:[UIImage systemImageNamed:@"19.circle.fill"]] && [mark.tintColor isEqual:SGRSecondary()],
          @"the mark is the circled 19 in the secondary color");
    CGRect title = [r.title.superview convertRect:r.title.frame toView:r.container];
    CGFloat textEnd = CGRectGetMinX(title) + r.title.label.intrinsicContentSize.width;
    CGFloat side = mark.frame.size.width, gap = CGRectGetMinX(mark.frame) - textEnd;
    // Apple's at a 20 pt title: 15.7 pt wide, 7.7 pt after the title (IMG_2566).
    check(side > 15 && side < 16.5 && gap > 7 && gap < 8.5,
          [NSString stringWithFormat:@"the mark is as big and as far from the title as the Music app's (%.1f wide, %.1f after)", side, gap]);
    CGFloat capTop, baseline;
    capOf(r, &capTop, &baseline);
    check(fabs(CGRectGetMidY(mark.frame) - (capTop + baseline) / 2) < 0.75,
          [NSString stringWithFormat:@"the mark is centered on the title's letters (%.2f, letters %.2f-%.2f)", CGRectGetMidY(mark.frame), capTop, baseline]);
    CGRect artist = [r.container convertRect:r.artist.bounds fromView:r.artist];
    check(fabs(CGRectGetMinX(artist) - CGRectGetMinX(title)) < 0.5, [NSString stringWithFormat:@"the artist starts under the title (%.1f)", CGRectGetMinX(artist)]);
    r.ageHolder.hidden = NO;
    settle();
    check(r.ageHolder.hidden && marksSeen(r) == 1, @"Spotify showing its mark again leaves the one mark");

    // Another badge before the artist keeps the artist after it.
    r.speed.hidden = NO;
    SGRShownTitleWatch(r.unit);
    artist = [r.container convertRect:r.artist.bounds fromView:r.artist];
    check(CGRectGetMinX(artist) > CGRectGetMinX(title) + 12, @"the artist stays after another badge");
    r.speed.hidden = YES;
    SGRShownTitleWatch(r.unit);

    // The lyrics' smaller title takes a smaller mark, still right after a title that fits beside the thumbnail.
    slideRow(r, kLyricsSlide);
    CGFloat small = mark.frame.size.width;
    check(small < side && fabs(small / r.title.label.font.capHeight - side / [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold].capHeight) < 0.01,
          [NSString stringWithFormat:@"with the lyrics open the mark keeps to the 17 pt title (%.1f)", small]);
    r.title.label.text = @"Whiplash";
    settle();
    textEnd = CGRectGetMinX(title) + r.title.label.intrinsicContentSize.width;
    check(marksSeen(r) == 1 && shownWhole(mark) && fabs(CGRectGetMinX(mark.frame) - textEnd - small / 2) < 0.5
          && r.title.label.intrinsicContentSize.width <= r.title.bounds.size.width,
          [NSString stringWithFormat:@"with the lyrics open a short title keeps its whole text and the mark right after it (%.1f after)",
           CGRectGetMinX(mark.frame) - textEnd]);
    r.title.label.text = @"Whiplash - Remastered";
    slideRow(r, 0);

    // Not explicit again.
    r.ageHolder.hidden = YES;
    r.explicitHolder.hidden = YES;
    settle();
    check(marksSeen(r) == 0 && fabs(CGRectGetMaxX(inRow(r, r.element)) - CGRectGetMinX(r.more.frame)) < 0.5, @"the next song, not explicit, has no mark");
    [r.unit removeFromSuperview];

    // A long 19+ title, Spotify showing both of its marks: the marquee ends a mark's room before the ⋯ and the one
    // circled mark stays in that room.
    r = buildRow(window, @"Holy Wars... The Punishment Due (Remastered 2004)", NO, RowAddSlot, @"Metallica");
    r.explicitHolder.hidden = NO;
    r.ageHolder.hidden = NO;
    SGRShownTitleWatch(r.unit);
    settle();
    mark = drawnMark(r);
    CGRect markInRow = inRow(r, mark), marqueeInRow = inRow(r, r.title);
    check(marksSeen(r) == 1 && [((UIImageView *)mark).image isEqual:[UIImage systemImageNamed:@"19.circle.fill"]] && shownWhole(mark)
          && CGRectGetMaxX(markInRow) <= CGRectGetMinX(r.more.frame) + 0.5 && CGRectGetMaxX(markInRow) > CGRectGetMinX(r.more.frame) - 1
          && fabs(CGRectGetMinX(markInRow) - CGRectGetMaxX(marqueeInRow) - mark.frame.size.width / 2) < 0.5,
          [NSString stringWithFormat:@"a long title with both of Spotify's marks ends before one circled mark, the mark before the ⋯ (marquee to %.1f, mark %.1f-%.1f, ⋯ at %.1f)",
           CGRectGetMaxX(marqueeInRow), CGRectGetMinX(markInRow), CGRectGetMaxX(markInRow), CGRectGetMinX(r.more.frame)]);
    CGRect closedMark = markInRow;
    // The lyrics open: the slid title is narrowed by as much, so the mark is whole and 12 pt short of the ⋯.
    slideRow(r, kLyricsSlide);
    markInRow = inRow(r, mark);
    marqueeInRow = inRow(r, r.title);
    CGFloat stop = CGRectGetMinX(r.more.frame) - 12;
    check(marksSeen(r) == 1 && [((UIImageView *)mark).image isEqual:[UIImage systemImageNamed:@"19.circle.fill"]] && shownWhole(mark)
          && CGRectGetMaxX(markInRow) <= stop + 0.5 && CGRectGetMaxX(markInRow) > stop - 1
          && fabs(CGRectGetMinX(markInRow) - CGRectGetMaxX(marqueeInRow) - mark.frame.size.width / 2) < 0.5,
          [NSString stringWithFormat:@"with the lyrics open the long title ends before the one circled mark, whole and short of the ⋯ (marquee to %.1f, mark %.1f-%.1f, ⋯ at %.1f)",
           CGRectGetMaxX(marqueeInRow), CGRectGetMinX(markInRow), CGRectGetMaxX(markInRow), CGRectGetMinX(r.more.frame)]);
    slideRow(r, 0);
    markInRow = inRow(r, mark);
    check(fabs(CGRectGetMaxX(markInRow) - CGRectGetMaxX(closedMark)) < 0.5 && fabs(CGRectGetMinY(markInRow) - CGRectGetMinY(closedMark)) < 0.5,
          [NSString stringWithFormat:@"the lyrics closed, the mark is back where it was (%.1f, was %.1f)", CGRectGetMaxX(markInRow), CGRectGetMaxX(closedMark)]);
    // Spotify's own thumbnail coming in before the title narrows it in a layout of the row alone.
    r.thumb.hidden = NO;
    [r.row layoutIfNeeded];
    markInRow = inRow(r, mark);
    marqueeInRow = inRow(r, r.title);
    check(CGRectGetMinX(marqueeInRow) > 59 && CGRectGetMaxX(markInRow) <= CGRectGetMinX(r.more.frame) + 0.5
          && fabs(CGRectGetMinX(markInRow) - CGRectGetMaxX(marqueeInRow) - mark.frame.size.width / 2) < 0.5,
          [NSString stringWithFormat:@"an episode's thumbnail coming in keeps the mark after the title and before the ⋯ (marquee %.1f-%.1f, mark to %.1f, ⋯ at %.1f)",
           CGRectGetMinX(marqueeInRow), CGRectGetMaxX(marqueeInRow), CGRectGetMaxX(markInRow), CGRectGetMinX(r.more.frame)]);
    r.thumb.hidden = YES;
    [r.row layoutIfNeeded];
    r.explicitHolder.hidden = YES;
    r.ageHolder.hidden = YES;
    settle();
    check(fabs(CGRectGetMaxX(inRow(r, r.title)) - CGRectGetMinX(r.more.frame)) < 0.5, @"a long title with no mark reaches the ⋯");

    // The row starting 24 pt in rather than 32 (after an episode or an ad turns into a song): the title still reaches
    // the ⋯ and the mark stays after it, short of the ⋯.
    r.explicitHolder.hidden = NO;
    settle();
    r.row.frame = CGRectMake(24, 8, 346, 48);
    [r.row layoutIfNeeded];
    r.more.frame = r.addSlot.frame;
    SGRShownTitleWatch(r.unit);
    settle();
    markInRow = inRow(r, mark);
    marqueeInRow = inRow(r, r.title);
    check(marksSeen(r) == 1 && CGRectGetMinX(inRow(r, r.element)) < 0.5
          && CGRectGetMaxX(markInRow) <= CGRectGetMinX(r.more.frame) + 0.5 && CGRectGetMaxX(markInRow) > CGRectGetMinX(r.more.frame) - 1
          && fabs(CGRectGetMinX(markInRow) - CGRectGetMaxX(marqueeInRow) - mark.frame.size.width / 2) < 0.5,
          [NSString stringWithFormat:@"a row starting at 24 pt keeps the mark after the title and before the ⋯ (marquee to %.1f, mark %.1f-%.1f, ⋯ at %.1f)",
           CGRectGetMaxX(marqueeInRow), CGRectGetMinX(markInRow), CGRectGetMaxX(markInRow), CGRectGetMinX(r.more.frame)]);
    [r.unit removeFromSuperview];

    // Right to left: all of it mirrored.
    r = buildRow(window, @"Whiplash - Remastered", YES, RowAddSlot, @"Metallica");
    r.explicitHolder.hidden = NO;
    SGRShownTitleWatch(r.unit);
    settle();
    mark = drawnMark(r);
    title = [r.title.superview convertRect:r.title.frame toView:r.container];
    CGFloat textStart = CGRectGetMaxX(title) - r.title.label.intrinsicContentSize.width;
    artist = [r.container convertRect:r.artist.bounds fromView:r.artist];
    check(fabs(CGRectGetMinX(inRow(r, r.element)) - CGRectGetMaxX(r.more.frame)) < 0.5
          && fabs(textStart - CGRectGetMaxX(mark.frame) - mark.frame.size.width / 2) < 0.5
          && fabs(CGRectGetMaxX(artist) - CGRectGetMaxX(title)) < 0.5,
          [NSString stringWithFormat:@"right to left the title reaches the ⋯ on the left, the mark is left of it and the artist under it (element from %.1f, ⋯ to %.1f)",
           CGRectGetMinX(inRow(r, r.element)), CGRectGetMaxX(r.more.frame)]);
    [r.unit removeFromSuperview];

    // Right to left, a long 19+ title with the lyrics open: slid left toward the ⋯, it ends right of the one mark.
    r = buildRow(window, @"Holy Wars... The Punishment Due (Remastered 2004)", YES, RowAddSlot, @"Metallica");
    r.explicitHolder.hidden = NO;
    r.ageHolder.hidden = NO;
    SGRShownTitleWatch(r.unit);
    settle();
    mark = drawnMark(r);
    slideRow(r, kLyricsSlide);
    markInRow = inRow(r, mark);
    marqueeInRow = inRow(r, r.title);
    stop = CGRectGetMaxX(r.more.frame) + 12;
    check(marksSeen(r) == 1 && shownWhole(mark) && CGRectGetMinX(markInRow) >= stop - 0.5 && CGRectGetMinX(markInRow) < stop + 1
          && fabs(CGRectGetMinX(marqueeInRow) - CGRectGetMaxX(markInRow) - mark.frame.size.width / 2) < 0.5,
          [NSString stringWithFormat:@"right to left with the lyrics open the long title ends right of the whole mark, short of the ⋯ (mark %.1f-%.1f, marquee from %.1f, ⋯ to %.1f)",
           CGRectGetMinX(markInRow), CGRectGetMaxX(markInRow), CGRectGetMinX(marqueeInRow), CGRectGetMaxX(r.more.frame)]);
    slideRow(r, 0);
    markInRow = inRow(r, mark);
    check(fabs(CGRectGetMinX(markInRow) - CGRectGetMaxX(r.more.frame)) < 1,
          [NSString stringWithFormat:@"right to left, the lyrics closed, the mark is back beside the ⋯ (%.1f)", CGRectGetMinX(markInRow)]);
    [r.unit removeFromSuperview];
}

// Every row shape in both directions, a long 19+ title over a long artist: with the lyrics open the title, its one mark
// and the artist all end 12 pt short of whatever is on the title's trailing side (the ⋯, Spotify's button) or of the
// row's end, the mark after the title; closed again, the row is as it was.
static void runShapes(UIWindow *window) {
    for (RowShape shape = RowAddSlot; shape <= RowBare; shape++) {
        for (int direction = 0; direction < 2; direction++) {
            BOOL rtl = direction == 1;
            Row r = buildRow(window, @"Holy Wars... The Punishment Due (Remastered 2004)", rtl, shape,
                             @"Megadeth, Dave Mustaine, David Ellefson, Marty Friedman, Nick Menza");
            r.explicitHolder.hidden = NO;
            r.ageHolder.hidden = NO;
            CGRect spotifys = inRow(r, r.element);
            SGRShownTitleWatch(r.unit);
            settle();
            CGRect closed = inRow(r, r.element);
            // Where the title must stop: the ⋯, Spotify's button after it, or the row's end.
            UIView *after = r.more ?: (shape == RowDJ ? r.addSlot : nil);
            CGRect afterFrame = after ? inRow(r, after) : CGRectNull;
            CGFloat stop = after ? (rtl ? CGRectGetMaxX(afterFrame) : CGRectGetMinX(afterFrame))
                                 : (rtl ? CGRectGetMinX(r.row.bounds) : CGRectGetMaxX(r.row.bounds));
            NSString *name = [NSString stringWithFormat:@"%@ %@", kShapeNames[shape], rtl ? @"right to left" : @"left to right"];
            if (shape != RowAddSlot) {
                // Closed, the long title and its mark end at the ⋯, Spotify's 12 pt short of its button, or at the row's end.
                CGFloat closedStop = shape == RowDJ ? (rtl ? stop + 12 : stop - 12) : stop;
                CGRect title = inRow(r, r.title), markFrame = inRow(r, drawnMark(r)), artist = inRow(r, r.artist);
                BOOL clear = YES;
                for (NSValue *frame in @[[NSValue valueWithCGRect:title], [NSValue valueWithCGRect:markFrame], [NSValue valueWithCGRect:artist]]) {
                    clear &= rtl ? CGRectGetMinX(frame.CGRectValue) >= closedStop - 0.5 : CGRectGetMaxX(frame.CGRectValue) <= closedStop + 0.5;
                }
                check(clear && shownWhole(drawnMark(r)) && (rtl ? CGRectGetMinX(closed) >= CGRectGetMinX(spotifys) - 0.5 : CGRectGetMaxX(closed) <= CGRectGetMaxX(spotifys) + 0.5),
                      [NSString stringWithFormat:@"the closed row %@ ends its title, mark and artist by %.1f "
                       "(title %.1f-%.1f, mark %.1f-%.1f, artist %.1f-%.1f)", name, closedStop, CGRectGetMinX(title), CGRectGetMaxX(title),
                       CGRectGetMinX(markFrame), CGRectGetMaxX(markFrame), CGRectGetMinX(artist), CGRectGetMaxX(artist)]);
            }
            slideRow(r, kLyricsSlide);
            UIView *mark = drawnMark(r);
            CGRect title = inRow(r, r.title), markFrame = inRow(r, mark), artist = inRow(r, r.artist);
            CGFloat limit = rtl ? stop + 12 : stop - 12;
            BOOL inside = YES;
            for (NSValue *frame in @[[NSValue valueWithCGRect:title], [NSValue valueWithCGRect:markFrame], [NSValue valueWithCGRect:artist]]) {
                inside &= rtl ? CGRectGetMinX(frame.CGRectValue) >= limit - 0.5 : CGRectGetMaxX(frame.CGRectValue) <= limit + 0.5;
            }
            CGFloat after_ = rtl ? CGRectGetMinX(title) - CGRectGetMaxX(markFrame) : CGRectGetMinX(markFrame) - CGRectGetMaxX(title);
            check(marksSeen(r) == 1 && shownWhole(mark) && inside && fabs(after_ - markFrame.size.width / 2) < 0.5,
                  [NSString stringWithFormat:@"with the lyrics open the row %@ ends its title, mark and artist 12 pt short of %.1f "
                   "(title %.1f-%.1f, mark %.1f-%.1f, artist %.1f-%.1f)", name, stop, CGRectGetMinX(title), CGRectGetMaxX(title),
                   CGRectGetMinX(markFrame), CGRectGetMaxX(markFrame), CGRectGetMinX(artist), CGRectGetMaxX(artist)]);
            slideRow(r, 0);
            check(CGRectEqualToRect(inRow(r, r.element), closed),
                  [NSString stringWithFormat:@"the lyrics closed, the row %@ is as it was (%@)", name, NSStringFromCGRect(inRow(r, r.element))]);
            [r.unit removeFromSuperview];
        }
    }
}

// PlayerMenu.m's SGRPlayerMenuInTitleRow, run after the title's layout: the row laid out, then the ⋯ in the add
// button's slot while Spotify shows it, else in the row's 48 pt end.
static void placeMore(Row r) {
    [r.row layoutIfNeeded];
    BOOL rtl = r.row.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGRect bounds = r.row.bounds;
    r.more.frame = !r.addSlot.hidden && r.addSlot.bounds.size.width >= 1 ? r.addSlot.frame
        : CGRectMake(rtl ? CGRectGetMinX(bounds) : CGRectGetMaxX(bounds) - 48, CGRectGetMidY(bounds) - 24, 48, 48);
}

// The edges of `frame` in the row's trailing direction: where it starts and where it ends.
static CGFloat leadOf(CGRect frame, BOOL rtl) { return rtl ? -CGRectGetMaxX(frame) : CGRectGetMinX(frame); }
static CGFloat trailOf(CGRect frame, BOOL rtl) { return rtl ? -CGRectGetMinX(frame) : CGRectGetMaxX(frame); }

// An episode's row with Spotify's skip ad pill up, in both directions, a long 19+ title and both of Spotify's marks:
// the title, its mark and the artist end Spotify's 12 pt spacing short of the pill, the pill ends where the ⋯ starts
// and the ⋯ in the row; each stays to be seen. The pill gone, the row is the one without it, and the pill stays hidden.
static void runPill(UIWindow *window) {
    for (RowShape shape = RowPill; shape <= RowPillNoAdd; shape++) {
        for (int direction = 0; direction < 2; direction++) {
            BOOL rtl = direction == 1;
            NSString *titleText = @"Second Date Update: Haunted House Hero (Halloween Special)";
            NSString *artistText = @"Brooke and Jeffrey: Second Date Update";
            Row plain = buildRow(window, titleText, rtl, shape == RowPill ? RowAddSlot : RowNoAddSlot, artistText);
            plain.explicitHolder.hidden = plain.ageHolder.hidden = NO;
            SGRShownTitleWatch(plain.unit);
            settle();
            CGRect plainElement = inRow(plain, plain.element);
            [plain.unit removeFromSuperview];

            Row r = buildRow(window, titleText, rtl, shape, artistText);
            r.explicitHolder.hidden = r.ageHolder.hidden = NO;
            SGRShownTitleWatch(r.unit);
            settle();
            NSString *name = [NSString stringWithFormat:@"%@ %@", kShapeNames[shape], rtl ? @"right to left" : @"left to right"];
            UIView *mark = drawnMark(r);
            CGRect title = inRow(r, r.title), markFrame = inRow(r, mark), artist = inRow(r, r.artist);
            CGRect pill = inRow(r, r.pill), more = inRow(r, r.more), bounds = r.row.bounds;
            CGFloat pillStart = leadOf(pill, rtl);
            BOOL beforePill = YES;
            for (NSValue *frame in @[[NSValue valueWithCGRect:title], [NSValue valueWithCGRect:markFrame], [NSValue valueWithCGRect:artist]]) {
                beforePill &= trailOf(frame.CGRectValue, rtl) <= pillStart - 12 + 0.5;
            }
            check(marksSeen(r) == 1 && shownWhole(mark) && beforePill && trailOf(title, rtl) < leadOf(markFrame, rtl),
                  [NSString stringWithFormat:@"the row %@ ends its title, then its one mark, and the artist 12 pt before the pill at %.1f "
                   "(title %.1f-%.1f, mark %.1f-%.1f, artist %.1f-%.1f)", name, CGRectGetMinX(pill), CGRectGetMinX(title), CGRectGetMaxX(title),
                   CGRectGetMinX(markFrame), CGRectGetMaxX(markFrame), CGRectGetMinX(artist), CGRectGetMaxX(artist)]);
            check(pill.size.width == kPillWidth && trailOf(pill, rtl) <= leadOf(more, rtl) + 0.5
                  && CGRectContainsRect(CGRectInset(bounds, -0.5, -0.5), more) && CGRectContainsRect(bounds, pill),
                  [NSString stringWithFormat:@"the row %@ has the whole pill end where the ⋯ starts, both in the row (pill %@, ⋯ %@)", name,
                   NSStringFromCGRect(pill), NSStringFromCGRect(more)]);
            r.pill.hidden = YES;
            [r.row layoutIfNeeded];
            settle();
            SGRShownTitleRestyle();
            settle();
            check(r.pill.hidden && CGRectEqualToRect(inRow(r, r.element), plainElement),
                  [NSString stringWithFormat:@"the pill gone, the row %@ is the one without it and the pill stays hidden (%@, without it %@)", name,
                   NSStringFromCGRect(inRow(r, r.element)), NSStringFromCGRect(plainElement)]);
            [r.unit removeFromSuperview];
            if (shape != RowPillNoAdd) continue;

            // Spotify takes the pill away and brings the add button's slot back in one pass: the title's layout, which
            // runs before the ⋯ moves into the slot, already ends the title, its mark and the artist before the slot.
            r = buildRow(window, titleText, rtl, shape, artistText);
            r.explicitHolder.hidden = r.ageHolder.hidden = NO;
            SGRShownTitleWatch(r.unit);
            settle();
            r.pill.hidden = YES;
            r.addSlot.hidden = NO;
            [r.unit layoutIfNeeded];
            placeMore(r);
            mark = drawnMark(r);
            title = inRow(r, r.title), markFrame = inRow(r, mark), artist = inRow(r, r.artist), more = inRow(r, r.more);
            BOOL beforeMore = YES;
            for (NSValue *frame in @[[NSValue valueWithCGRect:title], [NSValue valueWithCGRect:markFrame], [NSValue valueWithCGRect:artist]]) {
                beforeMore &= trailOf(frame.CGRectValue, rtl) <= leadOf(more, rtl) + 0.5;
            }
            check(marksSeen(r) == 1 && shownWhole(mark) && beforeMore && CGRectEqualToRect(more, inRow(r, r.addSlot)),
                  [NSString stringWithFormat:@"the pill going as the add button's slot comes back in the same pass %@, the title, mark and "
                   "artist end before the ⋯ moved into the slot (title %.1f-%.1f, mark %.1f-%.1f, artist %.1f-%.1f, ⋯ %@)",
                   rtl ? @"right to left" : @"left to right", CGRectGetMinX(title), CGRectGetMaxX(title), CGRectGetMinX(markFrame),
                   CGRectGetMaxX(markFrame), CGRectGetMinX(artist), CGRectGetMaxX(artist), NSStringFromCGRect(more)]);
            [r.unit removeFromSuperview];
        }
    }
}

// Star add button on (issue #44), in both directions: Spotify's add button stays in its slot, drawing the star, and the
// ⋯ stands in the row's end, the row's arranged views ending before it, so the star and the ⋯ sit side by side in the
// row; a short title's view reaches the star; a long 19+ title, its one mark and the artist end at the star, and 12 pt
// short of it with the lyrics open; closed again, the row is as it was.
static void runStar(UIWindow *window) {
    starAdd = YES;
    for (int direction = 0; direction < 2; direction++) {
        BOOL rtl = direction == 1;
        NSString *name = rtl ? @"right to left" : @"left to right";
        Row r = buildRow(window, @"Whiplash - Remastered", rtl, RowStar, @"Metallica");
        SGRShownTitleWatch(r.unit);
        settle();
        CGRect star = inRow(r, r.addSlot), more = inRow(r, r.more), bounds = r.row.bounds;
        CGRect inBounds = CGRectInset(bounds, -0.5, -0.5);
        check(r.addSlot.alpha == 1 && star.size.width == 48 && trailOf(star, rtl) <= leadOf(more, rtl) + 0.5
              && fabs(trailOf(more, rtl) - trailOf(bounds, rtl)) < 0.5 && CGRectContainsRect(inBounds, star) && CGRectContainsRect(inBounds, more),
              [NSString stringWithFormat:@"with Star add button %@ the star's slot ends where the ⋯ in the row's end starts (star %@, ⋯ %@)",
               name, NSStringFromCGRect(star), NSStringFromCGRect(more)]);
        CGRect element = inRow(r, r.element);
        check(fabs(trailOf(element, rtl) - leadOf(star, rtl)) < 0.5,
              [NSString stringWithFormat:@"with Star add button %@ a short title's view reaches the star (%@, star %@)", name,
               NSStringFromCGRect(element), NSStringFromCGRect(star)]);
        [r.unit removeFromSuperview];

        r = buildRow(window, @"Holy Wars... The Punishment Due (Remastered 2004)", rtl, RowStar,
                     @"Megadeth, Dave Mustaine, David Ellefson, Marty Friedman, Nick Menza");
        r.explicitHolder.hidden = r.ageHolder.hidden = NO;
        SGRShownTitleWatch(r.unit);
        settle();
        CGRect closed = inRow(r, r.element);
        UIView *mark = drawnMark(r);
        star = inRow(r, r.addSlot);
        for (int open = 0; open < 2; open++) {
            if (open) slideRow(r, kLyricsSlide);
            CGFloat limit = leadOf(star, rtl) - (open ? 12 : 0);
            CGRect title = inRow(r, r.title), markFrame = inRow(r, mark), artist = inRow(r, r.artist);
            BOOL before = YES;
            for (NSValue *frame in @[[NSValue valueWithCGRect:title], [NSValue valueWithCGRect:markFrame], [NSValue valueWithCGRect:artist]]) {
                before &= trailOf(frame.CGRectValue, rtl) <= limit + 0.5;
            }
            check(marksSeen(r) == 1 && shownWhole(mark) && before && trailOf(markFrame, rtl) > limit - 1
                  && fabs(leadOf(markFrame, rtl) - trailOf(title, rtl) - markFrame.size.width / 2) < 0.5,
                  [NSString stringWithFormat:@"with Star add button %@%@ the long title, then its one mark, and the artist end %@the star "
                   "(title %.1f-%.1f, mark %.1f-%.1f, artist %.1f-%.1f, star %@)", name, open ? @" and the lyrics open" : @"",
                   open ? @"12 pt short of " : @"at ", CGRectGetMinX(title), CGRectGetMaxX(title), CGRectGetMinX(markFrame),
                   CGRectGetMaxX(markFrame), CGRectGetMinX(artist), CGRectGetMaxX(artist), NSStringFromCGRect(star)]);
        }
        slideRow(r, 0);
        check(CGRectEqualToRect(inRow(r, r.element), closed) && CGRectEqualToRect(inRow(r, r.addSlot), star),
              [NSString stringWithFormat:@"with Star add button %@, the lyrics closed, the row is as it was (%@)", name, NSStringFromCGRect(inRow(r, r.element))]);
        [r.unit removeFromSuperview];
    }
    starAdd = NO;
}

static void run(UIWindow *window) {
    NSString *titleText = @"밤양갱", *artistText = @"비비 (BIBI)";
    UIFont *spotifyTitle = [UIFont fontWithName:@"Georgia-Bold" size:24], *spotifyArtist = [UIFont fontWithName:@"Georgia" size:16];
    UIView *unit = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 402, 120)];
    UIView *marquee = [[UIView alloc] initWithFrame:CGRectMake(32, 0, 338, 40)];
    marquee.accessibilityIdentifier = @"now-playing-title-label";
    UILabel *title = [UILabel new], *artist = [UILabel new];
    artist.accessibilityIdentifier = @"now-playing-subtitle-label";
    [marquee addSubview:title];
    [unit addSubview:marquee];
    [unit addSubview:artist];
    [window addSubview:unit];
    title.text = titleText;
    title.font = spotifyTitle;
    artist.text = artistText;
    artist.font = spotifyArtist;
    artist.textColor = UIColor.whiteColor;

    SGRShownTitleWatch(unit);
    UIFont *sfTitle = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold], *sfArtist = [UIFont systemFontOfSize:20];
    check(title.font.pointSize == 20 && fabs(weightOf(title.font) - UIFontWeightSemibold) < 0.01
          && [title.font.familyName isEqualToString:sfTitle.familyName],
          [NSString stringWithFormat:@"the marquee's title label takes 20 pt semibold in the system family (%@ %.1f)", title.font.fontName, title.font.pointSize]);
    check(artist.font.pointSize == 20 && fabs(weightOf(artist.font) - UIFontWeightRegular) < 0.01 && [artist.textColor isEqual:SGRSecondary()],
          [NSString stringWithFormat:@"the artist takes 20 pt regular in the secondary color (%@ %.1f)", artist.font.fontName, artist.font.pointSize]);
    title.font = spotifyTitle;
    artist.textColor = UIColor.whiteColor;
    check(title.font.pointSize == 20 && [artist.textColor isEqual:SGRSecondary()], @"Spotify's own font and color set again leave the Music app's type");
    title.attributedText = [[NSAttributedString alloc] initWithString:titleText attributes:@{NSFontAttributeName: spotifyTitle}];
    check([title.text isEqualToString:titleText] && title.font.pointSize == 20 && fabs(weightOf(title.font) - UIFontWeightSemibold) < 0.01,
          @"Korean text set with Spotify's attributes keeps its words and takes the Music app's type");
    CGFloat height = title.intrinsicContentSize.height;
    check(fabs(height - heightFor(titleText, sfTitle)) < 0.5 && height < heightFor(titleText, spotifyTitle),
          [NSString stringWithFormat:@"the title's intrinsic height is the 20 pt line's (%.1f, Spotify's %.1f)", height, heightFor(titleText, spotifyTitle)]);
    check(fabs(artist.intrinsicContentSize.height - heightFor(artistText, sfArtist)) < 0.5, @"the artist's intrinsic height is the 20 pt line's");

    lyricsOpen = YES;
    SGRShownTitleRestyle();
    check(title.font.pointSize == 17 && artist.font.pointSize == 17 && fabs(weightOf(title.font) - UIFontWeightSemibold) < 0.01,
          @"with the lyrics open the title and artist are 17 over 17");
    lyricsOpen = NO;
    SGRShownTitleRestyle();
    check(title.font.pointSize == 20 && artist.font.pointSize == 20, @"with the lyrics closed they are 20 again");

    // Spotify's font drawn: the labels keep the family Spotify gives them.
    drawn = SGAppFontSpotify;
    title.font = spotifyTitle;
    artist.font = spotifyArtist;
    check([title.font.familyName isEqualToString:@"Georgia"] && [artist.font.familyName isEqualToString:@"Georgia"]
          && title.font.pointSize == 20 && artist.font.pointSize == 20,
          [NSString stringWithFormat:@"with Spotify's font chosen the labels keep Spotify's family at 20 pt (%@, %@)", title.font.fontName, artist.font.fontName]);
    [unit removeFromSuperview];
    runRow(window);
    runShapes(window);
    runPill(window);
    runStar(window);
    printf("title style checks: %d of %d right -- %s\n", checked - failed, checked, failed ? "FAIL" : "PASS");
    fflush(stdout);
    exit(failed ? 1 : 0);
}

@interface TitleStyleApp : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation TitleStyleApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    // From a timer, not the main queue: the checks turn the run loop for the row's work queued on the main queue.
    [NSTimer scheduledTimerWithTimeInterval:0 repeats:NO block:^(NSTimer *timer) { run(self.window); }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        HARNESS_FAIL(@"title style checks did not finish");
    });
    return YES;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(TitleStyleApp.class)); }
}
