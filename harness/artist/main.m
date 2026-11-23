// A mock of Spotify's artist page under its own class names and accessibility identifiers, built from
// trees/clean/artist/01.txt and 05.txt (recorded 2026-09-16), so Redesigned/Artist can be laid out and looked
// at on the Mac. `collapsed` on the launch line shows the header scrolled into its 100pt bar; `late` holds
// the Follow button's word and then the photo back, one after the other, the way a page opened for the first
// time gets them -- each has to reach the redesign on its own (issue #52), and the artwork view carries
// Encore's Swift class name so that it can only be watched the way the phone makes the Kit watch it.
// The follow state comes from a mock of Spotify's collection platform under its real class and selector
// names: `none` at once, or in `late` a second in; Following, as saved, after the tap made at 2.5 s.
#import <UIKit/UIKit.h>
#import "../harness-fail.h"
#import "../album/motion-visibility.h"
#import "../album/hero-veil-check.h"
#import "Redesigned/Kit/SGRHeaderInfo.h"

#pragma mark - Spotify's classes, by name

@interface _TtC32CreativeWorkPlatform_TemplateKit12TemplateView : UIView @end
@implementation _TtC32CreativeWorkPlatform_TemplateKit12TemplateView @end

@interface _TtC32CreativeWorkPlatform_TemplateKit28CreativeWorkTemplateListView : UIView @end
@implementation _TtC32CreativeWorkPlatform_TemplateKit28CreativeWorkTemplateListView @end

// TemplateKit's private HeaderContainer; the redesign finds it by the words in its name.
@interface MockTemplateKitHeaderContainer : UIView @end
@implementation MockTemplateKitHeaderContainer @end

@interface _TtC35CreativeWorkPlatform_ImageHeaderKit15ImageHeaderView : UIView @end
@implementation _TtC35CreativeWorkPlatform_ImageHeaderKit15ImageHeaderView @end

@interface MockHeaderForegroundView : UIView @end
@implementation MockHeaderForegroundView @end

@interface MockGradientView : UIView @end
@implementation MockGradientView @end

@interface _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView : UIView @end
@implementation _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView @end

@interface _TtCOOOE16PodcastUI_ECMKitO19LegacyUI_ECMCoreKit10Components18TabsSectionHeading2UI7Private9TabButton : UIView @end
@implementation _TtCOOOE16PodcastUI_ECMKitO19LegacyUI_ECMCoreKit10Components18TabsSectionHeading2UI7Private9TabButton @end

// The list's cell. Spotify's sizes itself from its element; the mock answers the height it was built for.
@interface _TtC12Element_List18CollectionViewCell : UICollectionViewCell
@property (nonatomic) CGFloat natural;
@end
@implementation _TtC12Element_List18CollectionViewCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewLayoutAttributes *result = [attributes copy];
    result.size = CGSizeMake(attributes.size.width, self.natural);
    return result;
}
@end

@interface MockButton : UIControl @end
@implementation MockButton @end

// The collection platform as 9.1.78 has it: SPTCollectionPlatformState is an option set (saved 1, banned 2,
// none 4), and the provider answers subscribeCollectionStateForURL:completion: with a token to cancel.
@interface SPTCollectionPlatformState : NSObject
@property (nonatomic, readonly) NSInteger rawValue;
@end
@implementation SPTCollectionPlatformState
- (instancetype)initWithRawValue:(NSInteger)raw {
    if ((self = [super init])) _rawValue = raw;
    return self;
}
+ (instancetype)saved { return [[self alloc] initWithRawValue:1]; }
+ (instancetype)banned { return [[self alloc] initWithRawValue:2]; }
+ (instancetype)none { return [[self alloc] initWithRawValue:4]; }
- (BOOL)contains:(SPTCollectionPlatformState *)other { return (_rawValue & other.rawValue) == other.rawValue; }
@end

@interface MockRequestToken : NSObject
@property (nonatomic, copy) void (^onCancel)(void);
@end
@implementation MockRequestToken
- (void)cancel {
    NSLog(@"[harness] collection subscription canceled");
    if (self.onCancel) self.onCancel();
}
@end

@interface _TtC23Collection_PlatformImpl35CollectionPlatformStateProviderImpl : NSObject
@property (nonatomic) NSInteger raw;
@property (nonatomic, strong) NSMutableArray *subscribers;
- (void)push:(NSInteger)raw;
@end
@implementation _TtC23Collection_PlatformImpl35CollectionPlatformStateProviderImpl
- (id)subscribeCollectionStateForURL:(NSURL *)url completion:(void (^)(SPTCollectionPlatformState *, NSError *))completion {
    if (!self.subscribers) self.subscribers = [NSMutableArray array];
    void (^copied)(SPTCollectionPlatformState *, NSError *) = [completion copy];
    [self.subscribers addObject:copied];
    NSLog(@"[harness] subscribed for %@", url);
    if (self.raw) completion([[SPTCollectionPlatformState alloc] initWithRawValue:self.raw], nil);
    MockRequestToken *token = [MockRequestToken new];
    __weak typeof(self) weakSelf = self;
    token.onCancel = ^{ [weakSelf.subscribers removeObject:copied]; };
    return token;
}
// As the collection does it: off the main thread.
- (void)push:(NSInteger)raw {
    self.raw = raw;
    for (void (^completion)(SPTCollectionPlatformState *, NSError *) in [self.subscribers copy]) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            completion([[SPTCollectionPlatformState alloc] initWithRawValue:raw], nil);
        });
    }
}
@end
typedef _TtC23Collection_PlatformImpl35CollectionPlatformStateProviderImpl MockStateProvider;

@interface SPTCollectionPlatformImplementation : NSObject
@property (nonatomic, strong) MockStateProvider *stateProvider;
@end
@implementation SPTCollectionPlatformImplementation @end

static SPTCollectionPlatformImplementation *sgh_platform;

// The page's controller, which Spotify's answer spt_pageURI with the artist's URI.
@interface MockArtistPageController : UIViewController @end
@implementation MockArtistPageController
- (NSURL *)spt_pageURI { return [NSURL URLWithString:@"spotify:artist:7n2wHs1TKAczGzO7Dd2rGr"]; }
@end

// Encore's image view, the one every picture Spotify loads arrives in (01.txt:48). Its name is the point of
// the mock: a Swift one, which the Kit refuses to give an instance its own subclass of, so the harness
// watches the photo the way the phone has to -- through an override on the class.
@interface _TtC19LegacyUI_ECMCoreKitP33_3DFE6A8953CA91BDEBA7A38450631F5815EncoreImageView : UIImageView @end
@implementation _TtC19LegacyUI_ECMCoreKitP33_3DFE6A8953CA91BDEBA7A38450631F5815EncoreImageView @end

#pragma mark - building the tree

static UIView *box(UIView *parent, Class cls, CGRect frame, NSString *identifier) {
    UIView *view = [[cls alloc] initWithFrame:frame];
    view.accessibilityIdentifier = identifier;
    [parent addSubview:view];
    return view;
}

static UILabel *label(UIView *parent, CGRect frame, NSString *text, CGFloat size, UIColor *color, NSString *identifier) {
    UIView *encore = box(parent, UIView.class, frame, identifier);
    UILabel *inner = [[UILabel alloc] initWithFrame:encore.bounds];
    inner.text = text;
    inner.font = [UIFont boldSystemFontOfSize:size];
    inner.textColor = color;
    inner.accessibilityIdentifier = [identifier stringByAppendingString:@"-internal"];
    [encore addSubview:inner];
    return inner;
}

// A portrait: warm light from the top left over a dark ground, a head and shoulders.
static UIImage *photo(void) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(213, 213)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGFloat components[] = {0.78, 0.52, 0.38, 1, 0.18, 0.12, 0.14, 1};
        CGGradientRef gradient = CGGradientCreateWithColorComponents(space, components, NULL, 2);
        CGContextDrawLinearGradient(c, gradient, CGPointZero, CGPointMake(213, 213), 0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        [[UIColor colorWithRed:0.35 green:0.24 blue:0.22 alpha:1] setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(72, 40, 70, 84)] fill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(36, 128, 142, 120) cornerRadius:50] fill];
    }];
}

static UIImageView *glyph(UIView *button, NSString *symbol, CGFloat inset) {
    UIImageView *image = [[UIImageView alloc] initWithFrame:CGRectInset(button.bounds, inset, inset)];
    image.image = [UIImage systemImageNamed:symbol];
    image.tintColor = UIColor.whiteColor;
    [button addSubview:image];
    return image;
}

#pragma mark - the list

// What each cell of the Music list holds, top to bottom (05.txt): its identifier and its height.
static NSArray<NSArray *> *musicList(void) {
    NSMutableArray *items = [NSMutableArray array];
    void (^section)(NSString *, NSArray *) = ^(NSString *heading, NSArray *content) {
        [items addObject:@[@"", @16]];
        [items addObject:@[@"Components.UI.SectionHeadingHome", @36.67, heading]];
        [items addObjectsFromArray:content];
    };
    NSArray *tracks = @[@[@"Components.UI.RetrievalRowElementUI", @64, @"Stitches"], @[@"Components.UI.RetrievalRowElementUI", @64, @"Treat You Better"],
                        @[@"Components.UI.RetrievalRowElementUI", @64, @"Mercy"], @[@"Components.UI.RetrievalRowElementUI", @64, @"There's Nothing Holdin' Me Back"]];
    [items addObject:@[@"Components.UI.SectionHeadingHome", @36.67, @"Popular"]];
    [items addObjectsFromArray:tracks];
    section(@"Artist pick", @[@[@"Components.UI.PinnedItemUI", @120]]);
    section(@"Popular Releases", @[@[@"Components.UI.RetrievalRowElementUI", @104, @"Shawn"], @[@"Components.UI.RetrievalRowElementUI", @104, @"Wonder"]]);
    section(@"Music videos", @[@[@"Components.UI.MusicVideoShelfHeader", @224]]);
    section(@"Watch more from Shawn Mendes", @[@[@"WatchFeedCarouselEntryPointElement", @208]]);
    section(@"About", @[@[@"Components.UI.CreatorBiographyCard", @180]]);
    section(@"Fans Also Like", @[@[@"Components.UI.HomeCard", @178]]);
    return items;
}

@interface SGRListSource : NSObject <UICollectionViewDataSource>
@property (nonatomic, copy) NSArray<NSArray *> *items;
@end

@implementation SGRListSource
- (NSInteger)collectionView:(UICollectionView *)view numberOfItemsInSection:(NSInteger)section {
    return self.items.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)view cellForItemAtIndexPath:(NSIndexPath *)path {
    _TtC12Element_List18CollectionViewCell *cell = [view dequeueReusableCellWithReuseIdentifier:@"cell" forIndexPath:path];
    for (UIView *old in cell.contentView.subviews) [old removeFromSuperview];
    NSArray *item = self.items[path.item];
    NSString *kind = item[0];
    CGFloat height = [item[1] doubleValue];
    cell.natural = height;
    // Left unpainted: on the phone the repaint hook clears the base surface, which the harness does not compile.
    cell.backgroundColor = UIColor.clearColor;
    UIView *content = box(cell.contentView, UIView.class, CGRectMake(0, 0, view.bounds.size.width, height), nil);
    if (!kind.length) return cell;
    UIView *element = box(content, UIView.class, content.bounds, kind);
    CGFloat W = view.bounds.size.width;
    if ([kind isEqualToString:@"Components.UI.SectionHeadingHome"]) {
        label(element, CGRectMake(16, 8, W - 32, 22), item[2], 19, UIColor.whiteColor, @"Encore.Label");
    } else if ([kind isEqualToString:@"Components.UI.RetrievalRowElementUI"]) {
        UIView *art = box(element, UIView.class, CGRectMake(16, 8, height - 16, height - 16), nil);
        art.backgroundColor = [UIColor colorWithRed:0.45 green:0.35 blue:0.30 alpha:1];
        art.layer.cornerRadius = 4;
        label(element, CGRectMake(height + 8, height / 2 - 18, W - height - 40, 18), item[2], 14, UIColor.whiteColor, @"EncoreConsumerMobile.View.Granular.Title");
        UILabel *sub = label(element, CGRectMake(height + 8, height / 2 + 2, W - height - 40, 16), @"Shawn Mendes", 12,
                             [UIColor colorWithWhite:1 alpha:0.6], @"EncoreConsumerMobile.View.Granular.Subtitle");
        sub.font = [UIFont systemFontOfSize:12];
    } else if ([kind isEqualToString:@"Components.UI.HomeCard"]) {
        // A carousel: its own collection painted the AMOLED black, and a page-wide fade, as on the phone.
        element.backgroundColor = UIColor.blackColor;
        UIView *fade = box(element, MockGradientView.class, element.bounds, nil);
        fade.backgroundColor = [UIColor colorWithWhite:0 alpha:0.8];
        UICollectionViewCell *card = [[UICollectionViewCell alloc] initWithFrame:CGRectMake(16, 4, 153, height - 8)];
        card.backgroundColor = UIColor.blackColor;
        [element addSubview:card];
    } else {
        UIView *card = box(element, UIView.class, CGRectMake(16, 4, W - 32, height - 8), nil);
        card.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1];
        card.layer.cornerRadius = 8;
        label(card, CGRectMake(12, 12, W - 60, 18), [kind componentsSeparatedByString:@"."].lastObject, 13,
              [UIColor colorWithWhite:1 alpha:0.7], @"Encore.Label");
    }
    return cell;
}
@end

#pragma mark - the row's Play

#import "listeners-check.h"

static BOOL sameColor(UIColor *a, UIColor *b) {
    CGFloat ar, ag, ab, aa, br, bg, bb, ba;
    if (![a getRed:&ar green:&ag blue:&ab alpha:&aa] || ![b getRed:&br green:&bg blue:&bb alpha:&ba]) return NO;
    return fabs(ar - br) < 0.002 && fabs(ag - bg) < 0.002 && fabs(ab - bb) < 0.002 && fabs(aa - ba) < 0.002;
}

// `verify-play`: the row's Play as the two settings have it. -spotifyglass.redesign.artist.roundPlay YES: a 64pt circle
// centered on the page with its glyph alone in its middle and its word what VoiceOver reads, shuffle and Follow 44pt
// either side of it, 20pt off and level with its middle. Unset: the capsule, 48pt tall and at least 148 wide, the
// buttons 48pt and 16pt off. White either way; the glyph and the word in the page's color, or with
// -spotifyglass.redesign.playInPageColour NO in the accent -- Spotify's green #1ED760 here, the harness having no
// accent of its own -- three colors none of which is another. Round with -spotifyglass.redesign.artist.cutOutPlay YES
// too: the glyph unpainted, cut out of the circle by its mask, which is white, or with -spotifyglass.redesign.accentPlay
// YES the accent.
static void verifyPlay(UIView *root) {
    // A pass of the header after the photo's color has landed, as the phone has once the page lays out again.
    UIView *header = veilFind(root, @"_TtC35CreativeWorkPlatform_ImageHeaderKit15ImageHeaderView");
    [header setNeedsLayout];
    [header layoutIfNeeded];
    UIView *info = veilFind(root, @"SGRHeaderInfo"), *hero = veilFind(root, @"SGRArtistHero");
    [info layoutIfNeeded];
    UIControl *play = [info valueForKey:@"play"];
    UIView *shuffle = [info valueForKey:@"shuffle"], *follow = [info valueForKey:@"trailing"];
    UILabel *word = nil;
    UIImageView *glyph = nil;
    for (UIView *v in play.subviews) {
        if ([v isKindOfClass:UILabel.class]) word = (UILabel *)v;
        if ([v isKindOfClass:UIImageView.class]) glyph = (UIImageView *)v;
    }
    HARNESS_CHECK(play && shuffle && follow && word && glyph && glyph.image);
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    BOOL round = [defaults boolForKey:@"spotifyglass.redesign.artist.roundPlay"];
    BOOL pageColor = ![defaults objectForKey:@"spotifyglass.redesign.playInPageColour"] || [defaults boolForKey:@"spotifyglass.redesign.playInPageColour"];
    BOOL cut = round && [defaults boolForKey:@"spotifyglass.redesign.artist.cutOutPlay"];
    BOOL accentFill = cut && [defaults boolForKey:@"spotifyglass.redesign.accentPlay"];
    CGFloat width = info.bounds.size.width, side = round ? 44 : 48, gap = round ? 20 : 16;
    HARNESS_CHECK(fabs(CGRectGetMidX(play.frame) - width / 2) < 0.5);
    HARNESS_CHECK(CGSizeEqualToSize(shuffle.bounds.size, CGSizeMake(side, side)) && CGSizeEqualToSize(follow.bounds.size, CGSizeMake(side, side)));
    HARNESS_CHECK(fabs(CGRectGetMinX(play.frame) - CGRectGetMaxX(shuffle.frame) - gap) < 0.5);
    HARNESS_CHECK(fabs(CGRectGetMinX(follow.frame) - CGRectGetMaxX(play.frame) - gap) < 0.5);
    HARNESS_CHECK(fabs(CGRectGetMidY(shuffle.frame) - CGRectGetMidY(play.frame)) < 0.5);
    HARNESS_CHECK(fabs(CGRectGetMidY(follow.frame) - CGRectGetMidY(play.frame)) < 0.5);
    if (round) {
        HARNESS_CHECK(CGSizeEqualToSize(play.bounds.size, CGSizeMake(64, 64)) && fabs(play.layer.cornerRadius - 32) < 0.5);
        HARNESS_CHECK(word.hidden && !glyph.hidden);
        HARNESS_CHECK(fabs(CGRectGetMidX(glyph.frame) - 32) < 0.5 && fabs(CGRectGetMidY(glyph.frame) - 32) < 0.5);
    } else {
        HARNESS_CHECK(play.bounds.size.height == 48 && play.bounds.size.width >= 148 && !word.hidden);
    }
    // One accessibility element, a button named with Spotify's word.
    HARNESS_CHECK(play.isAccessibilityElement && (play.accessibilityTraits & UIAccessibilityTraitButton));
    HARNESS_CHECK([play.accessibilityLabel isEqualToString:@"Play"]);
    UIColor *white = UIColor.whiteColor, *accent = [UIColor colorWithRed:0x1E / 255.0 green:0xD7 / 255.0 blue:0x60 / 255.0 alpha:1];
    UIColor *page = [hero valueForKey:@"fieldColor"];
    HARNESS_CHECK(page && !sameColor(page, white) && !sameColor(page, accent) && !sameColor(white, accent));
    HARNESS_CHECK(sameColor(play.backgroundColor, accentFill ? accent : white));
    // Cut out: the glyph drawn by the hole in the capsule's own mask, not painted (cutout-check.sh reads the pixels).
    HARNESS_CHECK(cut == (play.layer.mask != nil) && glyph.alpha == (cut ? 0 : 1));
    if (cut) {
        NSLog(@"[harness] PASS artist play round cut out of %@: %@", accentFill ? @"the accent" : @"white", NSStringFromCGRect(play.frame));
        NSLog(@"[harness] SHOT artist-play-cutout-%@", accentFill ? @"accent" : @"white");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ exit(0); });
        return;
    }
    UIColor *content = pageColor ? page : accent;
    if (!sameColor(glyph.tintColor, content) || (!round && !sameColor(word.textColor, content)))
        HARNESS_FAIL(@"Play's glyph %@ and word %@, not %@", glyph.tintColor, word.textColor, content);
    NSLog(@"[harness] PASS artist play %@ in %@: %@, fill white, glyph %@", round ? @"round" : @"capsule",
          pageColor ? @"the page's color" : @"the accent", NSStringFromCGRect(play.frame), content);
    NSLog(@"[harness] SHOT artist-play-%@", round ? @"round-accent" : @"capsule-page");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ exit(0); });
}

#pragma mark - the name

static void verifyCentred(NSString *what, UIView *view, CGFloat width) {
    if (fabs(CGRectGetMidX(view.frame) - width / 2) > 0.5)
        HARNESS_FAIL(@"%@ at %@, not centred on the page %.0fpt across", what, NSStringFromCGRect(view.frame), width);
}

static void verifyCentredText(NSString *what, UILabel *label, CGFloat width) {
    if (label.textAlignment != NSTextAlignmentCenter) HARNESS_FAIL(@"%@ aligned %ld, not centred", what, (long)label.textAlignment);
    verifyCentred(what, label, width);
}

// `verify-title`: the artist's name the Music app's way on iOS 26 -- Large Title bold (capped at Extra Large), centred on
// the page, the listeners line centred under it, both clear of the row under them; a name too long for a line wraps
// centred, in two lines at most; a logo standing for the name is centred in its place, the listeners line still centred
// under it. The same right to left (-AppleTextDirection YES -NSForceRightToLeftWritingDirection YES on the launch line,
// which `rtl` asserts the page took). HARNESS_ARTIST names the artist. "[harness] SHOT artist-title" comes before the
// checks, 1.5 s ahead of them, for title-check.py's screenshot; then a PASS line and exit 0, or a FAIL and exit 1.
static void verifyTitle(UIView *root, BOOL rtl) {
    UIView *header = veilFind(root, @"_TtC35CreativeWorkPlatform_ImageHeaderKit15ImageHeaderView");
    [header setNeedsLayout];
    [header layoutIfNeeded];
    SGRHeaderInfo *info = (SGRHeaderInfo *)veilFind(root, @"SGRHeaderInfo");
    [info layoutIfNeeded];
    NSLog(@"[harness] SHOT artist-title");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [info layoutIfNeeded];
        UILabel *title = [info valueForKey:@"_title"], *listeners = [info valueForKey:@"_length"];
        UIView *play = [info valueForKey:@"play"], *shuffle = [info valueForKey:@"shuffle"], *follow = [info valueForKey:@"trailing"];
        NSString *name = NSProcessInfo.processInfo.environment[@"HARNESS_ARTIST"] ?: @"Shawn Mendes";
        CGFloat width = info.bounds.size.width;
        HARNESS_CHECK(info && play && shuffle && follow);
        HARNESS_CHECK([title.text isEqualToString:name] && !title.hidden && !listeners.hidden);
        HARNESS_CHECK((info.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft) == rtl);

        UIContentSizeCategory now = UIApplication.sharedApplication.preferredContentSizeCategory;
        UIContentSizeCategory capped = UIContentSizeCategoryCompareToCategory(now, UIContentSizeCategoryExtraLarge) == NSOrderedDescending
            ? UIContentSizeCategoryExtraLarge : now;
        CGFloat large = [UIFont preferredFontForTextStyle:UIFontTextStyleLargeTitle
                            compatibleWithTraitCollection:[UITraitCollection traitCollectionWithPreferredContentSizeCategory:capped]].pointSize;
        CGFloat weight = [[title.font.fontDescriptor objectForKey:UIFontDescriptorTraitsAttribute][UIFontWeightTrait] doubleValue];
        if (fabs(title.font.pointSize - large) > 0.01 || weight < UIFontWeightBold - 0.01)
            HARNESS_FAIL(@"the name is %.1fpt weight %.2f, not Large Title bold at %@ (%.1fpt)", title.font.pointSize, weight, capped, large);

        verifyCentredText(@"the name", title, width);
        verifyCentredText(@"the listeners line", listeners, width);
        // Wrapped, not cut, up to its two lines; a name one line can't hold takes more than one.
        CGFloat needed = ceil([title sizeThatFits:CGSizeMake(title.bounds.size.width, CGFLOAT_MAX)].height);
        if (title.bounds.size.height < needed - 0.5) HARNESS_FAIL(@"the name is %.1fpt high, its lines %.1fpt", title.bounds.size.height, needed);
        BOOL wraps = [title.text sizeWithAttributes:@{NSFontAttributeName: title.font}].width > title.bounds.size.width;
        HARNESS_CHECK(title.numberOfLines == 2 && wraps == (title.bounds.size.height > title.font.lineHeight * 1.5));
        CGFloat row = MIN(CGRectGetMinY(play.frame), MIN(CGRectGetMinY(shuffle.frame), CGRectGetMinY(follow.frame)));
        HARNESS_CHECK(CGRectGetMaxY(title.frame) <= CGRectGetMinY(listeners.frame) + 0.5);
        if (CGRectGetMaxY(listeners.frame) > row + 0.5)
            HARNESS_FAIL(@"the listeners line ends at %.1f, inside the row from %.1f", CGRectGetMaxY(listeners.frame), row);
        CGRect named = title.frame;

        // A logo arriving for the name: in the name's place, centred, the listeners line still centred under it.
        UIImage *logo = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(600, 200)] imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [UIColor.whiteColor setFill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 600, 200) cornerRadius:40] fill];
        }];
        [info showTitleImage:logo];
        [info layoutIfNeeded];
        UIView *picture = [info valueForKey:@"_logo"];
        HARNESS_CHECK(!picture.hidden && picture.frame.size.width > 0 && picture.frame.size.width < width);
        verifyCentred(@"the logo", picture, width);
        verifyCentredText(@"the listeners line under the logo", listeners, width);
        HARNESS_CHECK(CGRectGetMaxY(picture.frame) <= CGRectGetMinY(listeners.frame) + 0.5);
        NSLog(@"[harness] PASS artist title%@ \"%@\": %@ centred (%@), logo %@ centred, listeners %@ under it", rtl ? @" rtl" : @"", name,
              NSStringFromCGRect(named), wraps ? @"wrapped" : @"one line", NSStringFromCGRect(picture.frame),
              NSStringFromCGRect(listeners.frame));
        exit(0);
    });
}

#pragma mark - the page

@interface SGRHarnessDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) SGRListSource *source;
@property (nonatomic, strong) UICollectionViewDiffableDataSource *listenersSource;
@end

@implementation SGRHarnessDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    CGFloat W = self.window.bounds.size.width, H = self.window.bounds.size.height;
    BOOL collapsed = [NSProcessInfo.processInfo.arguments containsObject:@"collapsed"];
    BOOL late = [NSProcessInfo.processInfo.arguments containsObject:@"late"];
    sgh_platform = [SPTCollectionPlatformImplementation new];
    sgh_platform.stateProvider = [MockStateProvider new];
    if (!late) sgh_platform.stateProvider.raw = 4;
    // Some part of Spotify reaches for the provider before the page does.
    (void)sgh_platform.stateProvider;

    UIViewController *root = [MockArtistPageController new];
    root.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.07 alpha:1];
    self.window.rootViewController = root;

    UIView *page = box(root.view, _TtC32CreativeWorkPlatform_TemplateKit12TemplateView.class, CGRectMake(0, 0, W, H), @"creator-page");
    // The fixture combines PCFF's scrolling owner and its mirrored content host in one view.
    UIScrollView *scroll = (UIScrollView *)box(page, UIScrollView.class, page.bounds, @"PCFFTabLayoutViewController.overlayScrollView");
    scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    UIView *stack = box(scroll, UIView.class, CGRectMake(0, 0, W, 3000), nil);

    // the header, 568pt with the headline
    UIView *container = box(stack, MockTemplateKitHeaderContainer.class, CGRectMake(0, 0, W, 568), nil);
    UIView *element = box(container, UIView.class, collapsed ? CGRectMake(0, 468, W, 100) : container.bounds, nil);
    UIView *header = box(element, _TtC35CreativeWorkPlatform_ImageHeaderKit15ImageHeaderView.class, element.bounds, nil);

    UIView *clip = box(header, UIView.class, CGRectMake(0, 0, W, collapsed ? 0 : 424.67), nil);
    clip.clipsToBounds = YES;
    UIView *artwork = box(clip, UIView.class, CGRectMake(-11.33, 0, 424.67, 424.67), @"Components.Header.UI.ArtworkImage");
    UIImageView *picture = [[_TtC19LegacyUI_ECMCoreKitP33_3DFE6A8953CA91BDEBA7A38450631F5815EncoreImageView alloc]
                            initWithFrame:artwork.bounds];
    if (!late) picture.image = photo();
    picture.accessibilityIdentifier = @"Components.Header.UI.ArtworkImage.ImageView";
    [artwork addSubview:picture];
    UIView *wash = box(clip, MockGradientView.class, CGRectMake(-11.33, 310.67, 424.67, 257.33), nil);
    wash.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];

    UIView *titleBox = box(header, UIView.class, CGRectMake(16, 334.67, 370, 54), nil);
    label(titleBox, CGRectMake(0, 0, 370, 54), NSProcessInfo.processInfo.environment[@"HARNESS_ARTIST"] ?: @"Shawn Mendes", 45, UIColor.whiteColor, @"Encore.AdaptiveTitle");
    UIView *badge = box(header, UIStackView.class, CGRectMake(16, 390.67, 114.67, 24), @"ImageHeaderView.VerifiedBadge");
    label(badge, CGRectMake(20, 4, 94, 15), @"Verified by Spotify", 11, UIColor.whiteColor, @"Encore.Label");
    UIView *meta = box(header, UIView.class, CGRectMake(16, 432.67, 370, 15.33), nil);
    label(meta, CGRectMake(0, 0, 314, 15.33), @"58,4M monthly listeners", 11, [UIColor colorWithWhite:1 alpha:0.7],
          @"Components.Header.UI.Metadata");

    UIView *row = box(header, UIStackView.class, CGRectMake(4, 456, 394, 48), nil);
    UIView *follow = box(row, MockButton.class, CGRectMake(70, 8, 66, 32), @"Curation.FollowButtonElementKit.FollowButton");
    follow.accessibilityLabel = @"Follow";
    follow.layer.borderColor = UIColor.grayColor.CGColor;
    follow.layer.borderWidth = 1;
    follow.layer.cornerRadius = 16;
    UILabel *followWord = label(follow, CGRectMake(16, 8, 40, 16), late ? @"" : @"Follow", 11, UIColor.whiteColor, @"Encore.Label");
    if (late) follow.accessibilityLabel = nil;
    [(UIControl *)follow addTarget:self action:@selector(toggleFollow:) forControlEvents:UIControlEventTouchUpInside];
    glyph(box(row, MockButton.class, CGRectMake(148, 0, 48, 48), @"Components.UI.ContextMenuButton-7n2wHs1TKAczGzO7Dd2rGr"), @"ellipsis", 12);
    glyph(box(row, MockButton.class, CGRectMake(278, 0, 48, 48), @"Components.UI.ShuffleButton"), @"shuffle", 12);
    UIView *play = box(row, _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView.class, CGRectMake(334, 0, 48, 48), @"header-play-button");
    UIControl *condensed = (UIControl *)box(play, MockButton.class, play.bounds, nil);
    condensed.accessibilityLabel = @"Play";
    UIImageView *disc = glyph(condensed, @"play.fill", 0);
    disc.contentMode = UIViewContentModeCenter;
    disc.backgroundColor = [UIColor colorWithRed:0.12 green:0.84 blue:0.38 alpha:1];
    disc.layer.cornerRadius = 24;
    disc.clipsToBounds = YES;

    UIView *headline = box(header, UIStackView.class, CGRectMake(0, 504, W, 64), nil);
    UIView *banner = box(headline, UIView.class, CGRectMake(16, 16, W - 32, 40), @"Components.UI.ArtistHeadline");
    banner.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
    label(banner, CGRectMake(40, 12, 280, 16), @"Pre-save the upcoming album", 11, UIColor.whiteColor, @"Encore.Label");

    UIView *foreground = box(header, MockHeaderForegroundView.class, CGRectMake(0, 0, W, 0), nil);
    UIView *bar = box(foreground, UIView.class, CGRectMake(0, 0, W, 100), nil);
    bar.hidden = !collapsed;
    UIView *barGradient = box(bar, MockGradientView.class, bar.bounds, nil);
    barGradient.backgroundColor = [UIColor colorWithWhite:0.03 alpha:1];
    UILabel *barName = label(bar, CGRectMake(80, 62, 242, 20), @"Shawn Mendes", 13, UIColor.whiteColor, @"Encore.Label");
    barName.textAlignment = NSTextAlignmentCenter;

    // the tabs and, under them, the Music list
    UIView *tabs = box(stack, UIView.class, CGRectMake(0, 568, W, 2400), @"PCFFTabLayoutViewController.tabsViewAccessibilityID");
    UIView *strip = box(tabs, UIView.class, CGRectMake(0, 0, W, 44), @"Components.UI.TabsSectionHeading");
    for (int i = 0; i < 3; i++) {
        UIView *tab = box(strip, _TtCOOOE16PodcastUI_ECMKitO19LegacyUI_ECMCoreKit10Components18TabsSectionHeading2UI7Private9TabButton.class,
                          CGRectMake(16 + i * 64, 6, 56, 32), nil);
        label(tab, tab.bounds, @[@"Music", @"Video", @"Merch"][i], 13, UIColor.whiteColor, @"Encore.Label");
    }
    UIScrollView *pages = (UIScrollView *)box(tabs, UIScrollView.class, CGRectMake(0, 44, W, 2356), nil);
    UIView *listView = box(pages, _TtC32CreativeWorkPlatform_TemplateKit28CreativeWorkTemplateListView.class, pages.bounds, nil);
    listView.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.07 alpha:1];
    UICollectionViewFlowLayout *flow = [UICollectionViewFlowLayout new];
    flow.minimumLineSpacing = 0;
    flow.estimatedItemSize = CGSizeMake(W, 60);
    UICollectionView *list = [[UICollectionView alloc] initWithFrame:listView.bounds collectionViewLayout:flow];
    list.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.07 alpha:1];
    list.scrollEnabled = NO;
    [list registerClass:_TtC12Element_List18CollectionViewCell.class forCellWithReuseIdentifier:@"cell"];
    self.source = [SGRListSource new];
    BOOL checkListeners = [NSProcessInfo.processInfo.arguments containsObject:@"verify-listeners"];
    BOOL reloadSections = [NSProcessInfo.processInfo.arguments containsObject:@"reload-sections"];
    self.source.items = reloadSections ? @[
        @[@"", @16],
        @[@"Components.UI.SectionHeadingHome", @36, @"Videos"],
        @[@"Components.UI.MusicVideoShelfHeader", @224]
    ] : checkListeners ? listenersItems(NO) : musicList();
    if (checkListeners) {
        CGRect frame = list.frame;
        frame.size.height = 180;
        list.frame = frame;
    }
    [listView addSubview:list];
    if (checkListeners) {
        // Match Element_List's real data-source boundary, including UIKit's
        // retained-cell reconfiguration (which does not call prepareForReuse).
        self.listenersSource = [[UICollectionViewDiffableDataSource alloc] initWithCollectionView:list
            cellProvider:^UICollectionViewCell *(UICollectionView *view, NSIndexPath *path, id item) {
                return [self.source collectionView:view cellForItemAtIndexPath:path];
            }];
        NSDiffableDataSourceSnapshot *snapshot = [NSDiffableDataSourceSnapshot new];
        [snapshot appendSectionsWithIdentifiers:@[@0]];
        NSMutableArray *items = [NSMutableArray array];
        for (NSUInteger item = 0; item < self.source.items.count; item++) [items addObject:@(item)];
        [snapshot appendItemsWithIdentifiers:items];
        [self.listenersSource applySnapshotUsingReloadData:snapshot completion:nil];
    } else {
        list.dataSource = self.source;
    }
    scroll.contentSize = CGSizeMake(W, 3000);
    if (collapsed) scroll.contentOffset = CGPointMake(0, 468);

    [self.window makeKeyAndVisible];

    if (checkListeners) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            verifyListeners(root, header, list, self.source);
        });
        return YES;
    }

    if (reloadSections) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [list layoutIfNeeded];
            for (NSInteger item = 0; item < 3; item++) {
                UICollectionViewLayoutAttributes *a = [list layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:item inSection:0]];
                HARNESS_CHECK(a && a.size.height == 0);
            }
            self.source.items = @[
                @[@"", @16],
                @[@"Components.UI.SectionHeadingHome", @36, @"Popular"],
                @[@"Components.UI.RetrievalRowElementUI", @64, @"Kept song"]
            ];
            [list reloadData];
            [list layoutIfNeeded];
            NSArray<NSNumber *> *heights = @[@16, @36, @64];
            for (NSInteger item = 0; item < 3; item++) {
                UICollectionViewLayoutAttributes *a = [list layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:item inSection:0]];
                HARNESS_CHECK(a && a.size.height == heights[item].doubleValue);
            }
            NSLog(@"[harness] PASS reloaded artist content and its heading/spacer keep their natural heights");
            exit(0);
        });
        return YES;
    }

    // `logo`: an artist's logo arriving with the page on screen, at 2.5 s, and taken away again at 4.5 s (run
    // with `-spotifyglass.redesign.artist.logo NO` so Apple Music's own does not arrive too). The logo and the
    // name cross over while the block makes room, the logo starting from the name's place.
    if ([NSProcessInfo.processInfo.arguments containsObject:@"logo"]) {
        UIView *rootView = root.view;
        __block UIView *info = nil;
        UIImage *logo = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(600, 200)] imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [UIColor.whiteColor setFill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 600, 200) cornerRadius:40] fill];
        }];
        void (^report)(NSString *) = ^(NSString *when) {
            UIView *picture = [info valueForKey:@"_logo"], *title = [info valueForKey:@"_title"];
            NSLog(@"[harness] logo %@: logo %@ alpha %.2f hidden %d at %@ (fading %@, moving %@), name alpha %.2f at %@", when,
                  [(UIImageView *)picture image] ? @"drawn" : @"empty", picture.alpha, picture.hidden, NSStringFromCGRect(picture.frame),
                  [picture.layer animationForKey:@"opacity"] ? @"yes" : @"no", [picture.layer animationForKey:@"position"] ? @"yes" : @"no",
                  title.alpha, NSStringFromCGRect(title.frame));
        };
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:rootView];
            while (queue.count && !info) {
                UIView *v = queue.firstObject;
                [queue removeObjectAtIndex:0];
                if ([NSStringFromClass(v.class) isEqualToString:@"SGRHeaderInfo"]) info = v;
                [queue addObjectsFromArray:v.subviews];
            }
            report(@"before");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [info performSelector:NSSelectorFromString(@"showTitleImage:") withObject:logo];
            report(@"arriving");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ report(@"arrived"); });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [info performSelector:NSSelectorFromString(@"showTitleImage:") withObject:nil];
                report(@"leaving");
            });
#pragma clang diagnostic pop
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ report(@"gone"); });
        });
    }

    // What the redesign's Follow draws: nothing before the state, then the glyph for it. A tap on it at
    // 2.5 s, which Spotify answers with Following.
    for (NSNumber *when in @[@0.5, @1.5, @2.5, @3.0]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(when.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSMutableArray *lines = [NSMutableArray array];
            UIControl *tapped = nil;
            NSMutableArray *queue = [NSMutableArray arrayWithObject:container];
            while (queue.count) {
                UIView *v = queue.firstObject;
                [queue removeObjectAtIndex:0];
                [queue addObjectsFromArray:v.subviews];
                if (![NSStringFromClass(v.class) isEqualToString:@"SGRMirrorButton"] || v.frame.origin.x < 200) continue;
                tapped = (UIControl *)v;
                NSMutableArray *drawn = [NSMutableArray array];
                for (UIView *sub in v.subviews) {
                    if (sub.hidden || sub.alpha < 0.01) continue;
                    NSString *what = NSStringFromClass(sub.class);
                    if ([sub isKindOfClass:UILabel.class]) what = [NSString stringWithFormat:@"\"%@\"", ((UILabel *)sub).text];
                    else if ([sub isKindOfClass:UIImageView.class]) {
                        NSString *symbol = [((UIImageView *)sub).image.description componentsSeparatedByString:@"symbol(system: "].lastObject;
                        what = [NSString stringWithFormat:@"%@ in %@", [symbol componentsSeparatedByString:@")"].firstObject,
                                ((UIImageView *)sub).tintColor];
                    }
                    [drawn addObject:what];
                }
                [lines addObject:[NSString stringWithFormat:@"%@ touches %d a11y \"%@\" draws %@", NSStringFromCGRect(v.frame),
                                  v.userInteractionEnabled, v.accessibilityLabel, [drawn componentsJoinedByString:@", "]]];
            }
            NSLog(@"[harness] follow at %.1fs: %@", when.doubleValue, [lines componentsJoinedByString:@" | "]);
            if (when.doubleValue == 2.5) [tapped sendActionsForControlEvents:UIControlEventTouchUpInside];
        });
    }

    // The photo and the follow state land after the header has laid out, and neither lays it out again.
    if (late) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            followWord.text = @"Follow";
            follow.accessibilityLabel = @"Follow";
            [sgh_platform.stateProvider push:4];
            NSLog(@"[harness] late: the follow state is in Spotify's collection now");
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            picture.image = photo();
            NSLog(@"[harness] late: the photo is in Spotify's header now");
        });
    }

    // What the Music list came to once every cell answered for itself and the dropped headings were asked
    // again: each cell's kind and height, top to bottom.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSMutableArray *lines = [NSMutableArray array];
        for (NSUInteger i = 0; i < self.source.items.count; i++) {
            UICollectionViewLayoutAttributes *a = [list layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:0]];
            NSArray *item = self.source.items[i];
            NSString *name = item.count > 2 ? item[2] : [item[0] length] ? [item[0] componentsSeparatedByString:@"."].lastObject : @"spacer";
            [lines addObject:[NSString stringWithFormat:@"%@ %.0f", name, a.size.height]];
        }
        NSLog(@"[harness] Music list: %@", [lines componentsJoinedByString:@" | "]);
        UICollectionViewCell *carousel = (UICollectionViewCell *)[list cellForItemAtIndexPath:[NSIndexPath indexPathForItem:self.source.items.count - 1 inSection:0]];
        UIView *band = carousel.contentView.subviews.firstObject.subviews.firstObject;
        UIView *fade = band.subviews.firstObject;
        UIView *card = band.subviews.lastObject;
        NSLog(@"[harness] carousel bg %@, fade masked %d, card bg %@", band.backgroundColor, fade.layer.mask != nil, card.backgroundColor);
        NSLog(@"[harness] strip a=%.2f, pages moved %.0f, list bg %@", strip.alpha, pages.transform.ty, list.backgroundColor);
        // ⋯ is pinned to the page now, not to the header's container, so it holds its place as the page
        // scrolls and the header collapses (issue #57), and it is the back button's 44pt glass.
        UIView *pinned = nil;
        for (UIView *sub in page.subviews) {
            if ([NSStringFromClass(sub.class) isEqualToString:@"SGRMirrorButton"]) pinned = sub;
        }
        NSLog(@"[harness] pinned more: %@ on the page, a=%.2f",
              pinned ? NSStringFromCGRect(pinned.frame) : @"MISSING", pinned.alpha);
    });
    UIView *rootView = root.view;
    motionVisibilityCheck(rootView, YES);
    if ([NSProcessInfo.processInfo.arguments containsObject:@"verify-play"])
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ verifyPlay(rootView); });
    if ([NSProcessInfo.processInfo.arguments containsObject:@"verify-title"]) {
        BOOL rtl = [NSProcessInfo.processInfo.arguments containsObject:@"rtl"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ verifyTitle(rootView, rtl); });
    }
    // `veil` / `veil-off` (../album/hero-veil-check.h): the page scrolled by its own scroll view, the header's container
    // in it.
    NSString *veil = veilMode();
    if (veil) veilRun(rootView, @"artist", veil, NO, YES, 3.5, nil, ^(CGFloat d) { scroll.contentOffset = CGPointMake(0, d); });
    return YES;
}

// Spotify's Follow turns into Following, which the redesign's word has to follow.
- (void)toggleFollow:(UIControl *)follow {
    UILabel *word = nil;
    NSMutableArray *queue = [NSMutableArray arrayWithObject:follow];
    while (queue.count && !word) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([v isKindOfClass:UILabel.class]) word = (UILabel *)v;
        [queue addObjectsFromArray:v.subviews];
    }
    word.text = [word.text isEqualToString:@"Follow"] ? @"Following" : @"Follow";
    follow.accessibilityLabel = word.text;
    [sgh_platform.stateProvider push:[word.text isEqualToString:@"Following"] ? 1 : 4];
    NSLog(@"[harness] Spotify's Follow fired, now \"%@\"", word.text);
}

@end

// Before every %ctor, so the redesign's gate reads on.
__attribute__((constructor(101))) static void sgr_harnessDefaults(void) {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"spotifyglass.redesign"];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGRHarnessDelegate.class));
    }
}
