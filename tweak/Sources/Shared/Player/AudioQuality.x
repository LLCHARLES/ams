// The audio quality badge and its details (AudioQuality.h). No hooks: the looks place the badge, and the player's
// reports come through PlayerState.x.
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "AudioQuality.h"
#import "PlayerEvents.h"
#import "PlayerState.h"

// The Music app's badge: semibold caption type in a capsule, a glyph before Lossless (before every tier in the redesign).
static const CGFloat kFontSize = 11, kFontMax = 15, kPadX = 7, kPadY = 2, kGlyphGap = 3;
// The redesign's, measured on the Music app's player (iOS 26, 3x): regular type in a rounded rectangle 18.3 pt tall
// with 4.6 pt corners, lit by adding light to what is behind it: 17 of 255 for the fill, 107 more for the ink.
// Increase Contrast draws it over the backdrop in the label colors instead, as the native look's.
// The ink is lifted from 107 to 0.40 (102 of 255), the same as the times' (SGRRestyle.m), and the type from regular to
// semibold, the times' too: the two read alike. Over a light backdrop the redesign raises both again, and draws them
// plain where plusL cannot see what is behind (SGAudioQualitySetRedesignedInk).
static const CGFloat kRedesignPadY = 2.6, kRedesignCornerShare = 0.25, kRedesignFillLight = 17 / 255.0, kRedesignInkLight = 0.40;
// Kept clear between the badge and either time, and around the badge for a finger.
static const CGFloat kTimeGap = 8, kTouchOutset = 4;
static const NSTimeInterval kFade = 0.25;
static const CGFloat kPanelWidth = 280, kPanelMargin = 16, kPanelRowGap = 10;
// The redesign's summary: the glyph over the tier, its rate under it, then the sentence and the footnote.
static const CGFloat kSummaryGlyphSize = 28, kSummaryMarginX = 20, kSummaryMarginY = 18;
static const CGFloat kSummaryGlyphGap = 8, kSummaryRateGap = 2, kSummaryTextGap = 12, kSummaryFootGap = 10;

// What the badge shows for the song playing, all zero while it shows nothing.
typedef struct {
    SGAudioTier tier;
    SGAudioSource source;
    long long playingHz, hardwareHz;
    BOOL resampled;
} SGQualityShown;

static BOOL sg_on;
static SGQualityShown sg_shown;
// The track sg_shown is for, nil while it shows nothing.
static NSString *sg_shownTrack;
// The duration units laid out while the switch is on, and every badge made, to hide when it goes off.
static NSHashTable<UIView *> *sg_units;
static NSHashTable<UIView *> *sg_badges;
static NSString *sg_loggedFacts;
static char kBadgeKey, kTakeKey, kRemainingKey, kTakeLabelKey;

static void checkDetails(void);

static BOOL sameShown(SGQualityShown a, SGQualityShown b) {
    return a.tier == b.tier && a.source == b.source && a.playingHz == b.playingHz && a.hardwareHz == b.hardwareHz
        && a.resampled == b.resampled;
}

#pragma mark - Spotify's report

static long long integerIn(id object, NSString *key) {
    if (![object respondsToSelector:NSSelectorFromString(key)]) return 0;
    id value = [object valueForKey:key];
    return [value isKindOfClass:NSNumber.class] ? [value longLongValue] : 0;
}

// Every field of the report once per change, so the values a song really plays at are in the log.
static void logFacts(NSString *uri, id quality) {
    NSMutableArray<NSString *> *facts = [NSMutableArray arrayWithObject:uri ?: @"no track"];
    for (NSString *key in @[@"bitrateLevel", @"hifiStatus", @"strategy", @"fileOrigin", @"playingSampleRateHz",
                            @"hardwareSampleRateHz", @"isResampled", @"qualityRestrictionReason"]) {
        id value = [quality respondsToSelector:NSSelectorFromString(key)] ? [quality valueForKey:key] : nil;
        [facts addObject:[NSString stringWithFormat:@"%@ %@", key, value ?: @"-"]];
    }
    NSString *line = [facts componentsJoinedByString:@", "];
    if ([line isEqualToString:sg_loggedFacts]) return;
    sg_loggedFacts = line;
    SGLog(@"audio quality: %@", line);
}

static void update(SPTPlayerState *state) {
    SGQualityShown shown = {0};
    NSString *track = nil;
    if (sg_on && state) {
        id quality = [state respondsToSelector:NSSelectorFromString(@"playbackQuality")] ? [state valueForKey:@"playbackQuality"] : nil;
        NSString *uri = SGURIString(state.track.URI);
        logFacts(uri, quality);
        shown.tier = SGAudioTierShown(YES, SGPlayerPlaybackIsLocal(), uri, integerIn(quality, @"bitrateLevel"));
        if (shown.tier != SGAudioTierNone) {
            track = uri;
            shown.source = SGAudioSourceForStrategy(integerIn(quality, @"strategy"));
            shown.playingHz = integerIn(quality, @"playingSampleRateHz");
            shown.hardwareHz = integerIn(quality, @"hardwareSampleRateHz");
            shown.resampled = integerIn(quality, @"isResampled") != 0;
        }
    }
    if (sameShown(shown, sg_shown) && (track == sg_shownTrack || [track isEqualToString:sg_shownTrack])) return;
    sg_shown = shown;
    sg_shownTrack = [track copy];
    checkDetails();
    for (UIView *unit in sg_units.allObjects) [unit setNeedsLayout];
}

static void hideBadge(UIView *badge);

// Every view controller's view on screen that holds the player's times: the looks place the badge from those units'
// layout, which a unit laid out before the switch came on does not run again by itself.
static void layOutUnitsOnScreen(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            SGForEachView(window, ^(UIView *view) {
                if (![view.accessibilityIdentifier isEqualToString:@"now-playing-time-take-label"]) return;
                for (UIView *v = view.superview; v; v = v.superview) {
                    if ([v.nextResponder isKindOfClass:UIViewController.class]) {
                        [v setNeedsLayout];
                        break;
                    }
                }
            });
        }
    }
}

void SGAudioQualitySettingChanged(void) {
    BOOL on = SGFlag(SGKeyPlayerAudioQuality, NO);
    if (on == sg_on) return;
    sg_on = on;
    update(SGPlayerState());
    if (on) {
        layOutUnitsOnScreen();
        return;
    }
    // Off, the looks' layout passes return at once, so the badges go here and the units are forgotten.
    for (UIView *badge in sg_badges.allObjects) hideBadge(badge);
    [sg_units removeAllObjects];
}

@interface SGAudioQualityWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGAudioQualityWatcher
- (void)playerStateDidReport:(SPTPlayerState *)state {
    update(state);
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
}
@end

#pragma mark - the details

static NSString *yesNo(BOOL yes) {
    return yes ? SGL(@"player.audio_quality.yes", @"Yes") : SGL(@"player.audio_quality.no", @"No");
}

// The details follow the song they were opened for while it plays (a rate Spotify reports late fills in) and are
// dismissed once they no longer describe it (SGAudioQualityDetailsStay).
@interface SGAudioQualityPanel : UIViewController
@property (nonatomic, copy, readonly) NSString *track;
@property (nonatomic, weak, readonly) UIView *badge;
// The redesign's summary rather than the native look's rows.
- (instancetype)initWithTrack:(NSString *)track badge:(UIView *)badge redesigned:(BOOL)redesigned;
- (void)showQuality:(SGQualityShown)shown;
- (void)close;
@end

static __weak SGAudioQualityPanel *sg_panel;

@implementation SGAudioQualityPanel {
    SGQualityShown _shown;
    UIStackView *_stack;
    BOOL _redesigned;
}

- (instancetype)initWithTrack:(NSString *)track badge:(UIView *)badge redesigned:(BOOL)redesigned {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    _track = [track copy];
    _badge = badge;
    _shown = sg_shown;
    _redesigned = redesigned;
    return self;
}

- (void)showQuality:(SGQualityShown)shown {
    if (sameShown(shown, _shown)) return;
    _shown = shown;
    if (self.isViewLoaded) [self fill];
}

- (void)close {
    if (self.presentingViewController && !self.isBeingDismissed) [self dismissViewControllerAnimated:YES completion:nil];
}

// A name on the leading side and its value on the trailing one; a row whose value Spotify did not report is left out.
- (UIView *)rowNamed:(NSString *)name value:(NSString *)value {
    if (!value) return nil;
    UILabel *nameLabel = [UILabel new], *valueLabel = [UILabel new];
    nameLabel.text = name;
    nameLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    nameLabel.textColor = UIColor.secondaryLabelColor;
    valueLabel.text = value;
    valueLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]];
    valueLabel.textColor = UIColor.labelColor;
    valueLabel.textAlignment = NSTextAlignmentNatural;
    for (UILabel *label in @[nameLabel, valueLabel]) {
        label.adjustsFontForContentSizeCategory = YES;
        label.numberOfLines = 0;
    }
    [valueLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [nameLabel setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[nameLabel, valueLabel]];
    row.spacing = kPanelMargin;
    row.alignment = UIStackViewAlignmentFirstBaseline;
    row.isAccessibilityElement = YES;
    row.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", name, value];
    return row;
}

- (void)fill {
    for (UIView *row in _stack.arrangedSubviews) [row removeFromSuperview];
    if (_redesigned) {
        [self fillSummary];
    } else {
        for (UIView *row in [self rows]) [_stack addArrangedSubview:row];
        [_stack setCustomSpacing:kPanelRowGap + 4 afterView:_stack.arrangedSubviews.firstObject];
    }
    CGSize size = [_stack systemLayoutSizeFittingSize:CGSizeMake(kPanelWidth, 0)
                        withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    self.preferredContentSize = CGSizeMake(kPanelWidth, ceil(size.height));
}

- (NSArray<UIView *> *)rows {
    UILabel *title = [UILabel new];
    title.text = SGL(@"player.audio_quality.title", @"Audio Quality");
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    title.textColor = UIColor.labelColor;
    title.adjustsFontForContentSizeCategory = YES;
    title.accessibilityTraits = UIAccessibilityTraitHeader;
    BOOL rates = _shown.playingHz > 0 && _shown.hardwareHz > 0;
    NSMutableArray<UIView *> *rows = [NSMutableArray arrayWithObject:title];
    for (UIView *row in @[
        [self rowNamed:SGL(@"player.audio_quality.quality", @"Quality") value:SGAudioTierName(_shown.tier)] ?: NSNull.null,
        [self rowNamed:SGL(@"player.audio_quality.playing_rate", @"Sample rate") value:SGAudioSampleRateText(_shown.playingHz)] ?: NSNull.null,
        [self rowNamed:SGL(@"player.audio_quality.hardware_rate", @"Output") value:SGAudioSampleRateText(_shown.hardwareHz)] ?: NSNull.null,
        [self rowNamed:SGL(@"player.audio_quality.resampled", @"Resampled") value:rates ? yesNo(_shown.resampled) : nil] ?: NSNull.null,
        [self rowNamed:SGL(@"player.audio_quality.source", @"Source") value:SGAudioSourceName(_shown.source)] ?: NSNull.null,
    ]) {
        if ([row isKindOfClass:UIView.class]) [rows addObject:row];
    }
    return rows;
}

static UILabel *summaryLabel(NSString *text, UIFontTextStyle style, UIFontWeight weight, UIColor *color) {
    UILabel *label = [UILabel new];
    label.text = text;
    UIFont *base = [UIFont systemFontOfSize:[UIFont preferredFontForTextStyle:style compatibleWithTraitCollection:
        [UITraitCollection traitCollectionWithPreferredContentSizeCategory:UIContentSizeCategoryLarge]].pointSize weight:weight];
    label.font = [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:base];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = color;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    return label;
}

// The redesign's: the waveform over the tier's name, its rate, a sentence on what it is and a footnote, centered, in
// the primary, secondary and tertiary label colors (vibrant over the popover's glass).
- (void)fillSummary {
    SGAudioTier tier = _shown.tier;
    UIImageSymbolConfiguration *size = [UIImageSymbolConfiguration configurationWithPointSize:kSummaryGlyphSize weight:UIImageSymbolWeightMedium];
    UIImageView *glyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"waveform" withConfiguration:size]];
    glyph.tintColor = UIColor.labelColor;
    glyph.contentMode = UIViewContentModeCenter;
    glyph.isAccessibilityElement = NO;
    UILabel *title = summaryLabel(SGAudioTierBadgeName(tier), UIFontTextStyleTitle3, UIFontWeightBold, UIColor.labelColor);
    title.accessibilityTraits = UIAccessibilityTraitHeader;
    UILabel *rate = summaryLabel(SGAudioTierRateText(tier, _shown.playingHz), UIFontTextStyleSubheadline, UIFontWeightMedium, UIColor.secondaryLabelColor);
    UILabel *summary = summaryLabel(SGAudioTierSummary(tier), UIFontTextStyleSubheadline, UIFontWeightRegular, UIColor.secondaryLabelColor);
    UILabel *footnote = summaryLabel(SGAudioTierFootnote(tier), UIFontTextStyleFootnote, UIFontWeightRegular, UIColor.tertiaryLabelColor);
    for (UIView *view in @[glyph, title, rate, summary, footnote]) [_stack addArrangedSubview:view];
    [_stack setCustomSpacing:kSummaryGlyphGap afterView:glyph];
    [_stack setCustomSpacing:kSummaryRateGap afterView:title];
    [_stack setCustomSpacing:kSummaryTextGap afterView:rate];
    [_stack setCustomSpacing:kSummaryFootGap afterView:summary];
}

- (void)loadView {
    _stack = [UIStackView new];
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.spacing = kPanelRowGap;
    _stack.layoutMargins = _redesigned ? UIEdgeInsetsMake(kSummaryMarginY, kSummaryMarginX, kSummaryMarginY, kSummaryMarginX)
                                       : UIEdgeInsetsMake(kPanelMargin, kPanelMargin, kPanelMargin, kPanelMargin);
    _stack.layoutMarginsRelativeArrangement = YES;
    _stack.backgroundColor = UIColor.clearColor;
    self.view = _stack;
    [self fill];
}
@end

// Whether the badge the details point at is placed and drawn (defined with the badge).
static BOOL badgeShown(UIView *badge);

static void checkDetails(void) {
    SGAudioQualityPanel *panel = sg_panel;
    if (!panel) return;
    if (SGAudioQualityDetailsStay(panel.track, sg_shownTrack, sg_shown.tier, badgeShown(panel.badge))) [panel showQuality:sg_shown];
    else [panel close];
}

#pragma mark - the badge

@class SGAudioQualityBadge;

// The badge's tap. The unit after the times (the controls) overlaps the bottom of their row and lies over it, so a
// touch on the badge lands in that unit's view: the tap sits on the view holding both units, which sees every touch
// in either, and takes only the ones on a badge that draws. The badge itself takes no touches, and the tap cancels
// none of the views under it.
@interface SGAudioQualityTap : UITapGestureRecognizer <UIGestureRecognizerDelegate>
@property (nonatomic, weak) SGAudioQualityBadge *badge;
@end

// Drawn rather than built of labels: a look that walks the time unit's labels (the native look's time font) leaves it be.
@interface SGAudioQualityBadge : UIView
@property (nonatomic) SGAudioTier tier;
// The redesign's words and glyph (AudioQuality.h), set before the tier.
@property (nonatomic) BOOL redesigned;
// The redesign's ink, fill and whether plusL carries them, as it works them out from the backdrop behind the badge
// (SGAudioQualitySetRedesignedInk); until then the standard ones.
@property (nonatomic) CGFloat inkAlpha, fillAlpha;
@property (nonatomic) BOOL plain;
// Placed, faded in and fitting between the times.
@property (nonatomic) BOOL shown;
@property (nonatomic, strong) SGAudioQualityTap *tap;
- (void)sg_open;
@end

@implementation SGAudioQualityTap
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    SGAudioQualityBadge *badge = self.badge;
    return badgeShown(badge) && [badge pointInside:[touch locationInView:badge] withEvent:nil];
}

- (void)sg_tapped {
    [self.badge sg_open];
}
@end

@implementation SGAudioQualityBadge

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.opaque = NO;
    self.backgroundColor = UIColor.clearColor;
    self.contentMode = UIViewContentModeRedraw;
    self.userInteractionEnabled = NO;
    // The player is dark under either look, whatever the system's style.
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityHint = SGL(@"player.audio_quality.hint", @"Shows the details");
    _tap = [[SGAudioQualityTap alloc] initWithTarget:nil action:nil];
    [_tap addTarget:_tap action:@selector(sg_tapped)];
    _tap.delegate = _tap;
    _tap.badge = self;
    _tap.cancelsTouchesInView = NO;
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    // The player closing takes the badge out of the window, and its details with it.
    if (!self.window) checkDetails();
}

- (void)setShown:(BOOL)shown {
    _shown = shown;
    self.isAccessibilityElement = shown;
    self.accessibilityElementsHidden = !shown;
}

- (BOOL)accessibilityActivate {
    [self sg_open];
    return YES;
}

- (void)setTier:(SGAudioTier)tier {
    if (tier == _tier) return;
    _tier = tier;
    NSString *name = self.text;
    self.accessibilityLabel = name ? [NSString stringWithFormat:SGL(@"player.audio_quality.accessibility", @"Audio quality, %@"), name] : nil;
    [self setNeedsDisplay];
}

- (NSString *)text {
    return _redesigned ? SGAudioTierBadgeName(_tier) : SGAudioTierName(_tier);
}

- (UIFont *)font {
    UIFontWeight weight = UIFontWeightSemibold;
    return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption2] scaledFontForFont:[UIFont systemFontOfSize:kFontSize weight:weight]
                                                                       maximumPointSize:kFontMax compatibleWithTraitCollection:self.traitCollection];
}

// The redesign's light added to the backdrop, unless Increase Contrast asks for the label colors' more opaque look.
- (BOOL)lit {
    return _redesigned && self.traitCollection.accessibilityContrast != UIAccessibilityContrastHigh;
}

// Whether the light is added to the backdrop (plusL) rather than drawn as a plain white of the same result.
- (BOOL)adds {
    return self.lit && !_plain;
}

- (void)setInk:(CGFloat)ink fill:(CGFloat)fill plain:(BOOL)plain {
    if (ink == _inkAlpha && fill == _fillAlpha && plain == _plain) return;
    _inkAlpha = ink;
    _fillAlpha = fill;
    _plain = plain;
    [self updateCompositing];
    [self setNeedsDisplay];
}

- (void)setRedesigned:(BOOL)redesigned {
    _redesigned = redesigned;
    [self updateCompositing];
}

- (void)updateCompositing {
    self.layer.compositingFilter = self.adds ? @"plusL" : nil;
}

// The redesign's before every tier, the native look's before the lossless ones only.
- (UIImage *)glyphIn:(UIFont *)font {
    if (_tier == SGAudioTierNone || (!_redesigned && !SGAudioTierIsLossless(_tier))) return nil;
    return [UIImage systemImageNamed:@"waveform" withConfiguration:[UIImageSymbolConfiguration configurationWithFont:font scale:UIImageSymbolScaleSmall]];
}

- (CGSize)sizeThatFits:(CGSize)size {
    UIFont *font = self.font;
    UIImage *glyph = [self glyphIn:font];
    CGFloat text = [self.text ?: @"" sizeWithAttributes:@{NSFontAttributeName: font}].width;
    CGFloat glyphWidth = glyph ? glyph.size.width + kGlyphGap : 0;
    if (!_redesigned) return CGSizeMake(ceil(2 * kPadX + glyphWidth + text), ceil(font.lineHeight + 2 * kPadY));
    // On the screen's pixels rather than whole points, which would add up to a point to the measured height.
    CGFloat scale = MAX(self.traitCollection.displayScale, 1);
    return CGSizeMake(ceil(2 * kPadX + glyphWidth + text), round((font.lineHeight + 2 * kRedesignPadY) * scale) / scale);
}

- (void)drawRect:(CGRect)rect {
    CGRect bounds = self.bounds;
    UITraitCollection *traits = self.traitCollection;
    BOOL lit = self.lit;
    CGContextRef context = UIGraphicsGetCurrentContext();
    UIColor *ink = lit ? [UIColor colorWithWhite:1 alpha:_inkAlpha > 0 ? _inkAlpha : kRedesignInkLight] : [UIColor.secondaryLabelColor resolvedColorWithTraitCollection:traits];
    UIColor *fill = lit ? [UIColor colorWithWhite:1 alpha:_fillAlpha > 0 ? _fillAlpha : kRedesignFillLight] : [UIColor.quaternaryLabelColor resolvedColorWithTraitCollection:traits];
    [fill setFill];
    if (_redesigned) {
        // Circular corners: the Music app's edge follows a circle's, not UIBezierPath's continuous curve.
        CGFloat radius = bounds.size.height * kRedesignCornerShare;
        CGPathRef shape = CGPathCreateWithRoundedRect(bounds, radius, radius, NULL);
        CGContextAddPath(context, shape);
        CGContextFillPath(context);
        CGPathRelease(shape);
    } else {
        [[UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:bounds.size.height / 2] fill];
    }
    // The ink adds its light to the fill's, as the Music app's does over its own.
    CGBlendMode inkBlend = self.adds ? kCGBlendModePlusLighter : kCGBlendModeNormal;
    CGContextSetBlendMode(context, inkBlend);

    UIFont *font = self.font;
    NSString *text = self.text ?: @"";
    NSDictionary *attributes = @{NSFontAttributeName: font, NSForegroundColorAttributeName: ink};
    CGSize textSize = [text sizeWithAttributes:attributes];
    UIImage *glyph = [self glyphIn:font];
    CGFloat glyphWidth = glyph ? glyph.size.width + kGlyphGap : 0;
    CGFloat x = round(CGRectGetMidX(bounds) - (glyphWidth + textSize.width) / 2);
    BOOL rightToLeft = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGFloat glyphX = rightToLeft ? x + textSize.width + kGlyphGap : x, textX = rightToLeft ? x : x + glyphWidth;
    if (glyph) {
        CGRect glyphRect = CGRectMake(glyphX, CGRectGetMidY(bounds) - glyph.size.height / 2, glyph.size.width, glyph.size.height);
        [[glyph imageWithTintColor:ink renderingMode:UIImageRenderingModeAlwaysOriginal] drawInRect:glyphRect
                                                                                          blendMode:inkBlend alpha:1];
    }
    [text drawAtPoint:CGPointMake(textX, CGRectGetMidY(bounds) - font.lineHeight / 2) withAttributes:attributes];
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return CGRectContainsPoint(CGRectInset(self.bounds, -kTouchOutset, -kTouchOutset), point);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (previous.accessibilityContrast != self.traitCollection.accessibilityContrast) {
        [self updateCompositing];
        [self setNeedsDisplay];
    }
    if (![previous.preferredContentSizeCategory isEqualToString:self.traitCollection.preferredContentSizeCategory]) {
        [self setNeedsDisplay];
        [self.superview setNeedsLayout];
    }
}

- (void)sg_open {
    if (!badgeShown(self) || sg_shown.tier == SGAudioTierNone || sg_panel) return;
    SGAudioQualityPanel *panel = [[SGAudioQualityPanel alloc] initWithTrack:sg_shownTrack badge:self redesigned:_redesigned];
    sg_panel = panel;
    SGPresentPopover(panel, self);
}
@end

static BOOL badgeShown(UIView *view) {
    SGAudioQualityBadge *badge = [view isKindOfClass:SGAudioQualityBadge.class] ? (SGAudioQualityBadge *)view : nil;
    return badge.shown && badge.window && SGAudioQualityViewDrawn((id<SGAudioQualityViewChain>)badge);
}

static void hideBadge(UIView *view) {
    SGAudioQualityBadge *badge = (SGAudioQualityBadge *)view;
    badge.shown = NO;
    badge.alpha = 0;
    checkDetails();
}

#pragma mark - placing it

// Where `view` stands in `unit` with its own transform left out (the redesign lowers the times while a finger scrubs).
static CGRect untransformedIn(UIView *view, UIView *unit) {
    CGSize size = view.bounds.size;
    CGRect frame = CGRectMake(view.center.x - size.width / 2, view.center.y - size.height / 2, size.width, size.height);
    return [view.superview convertRect:frame toView:unit];
}

static BOOL timeShown(UIView *time, UIView *unit) {
    return time.window && time.alpha > 0.01 && SGShownUnder(time, unit);
}

// The scene's orientation, not the size class: a landscape window of regular height (an iPad's) is landscape too.
static BOOL landscape(UIView *view) {
    return UIInterfaceOrientationIsLandscape(view.window.windowScene.interfaceOrientation);
}

// Where `label`'s single line has its baseline, from the label's top. UILabel centers the line it lays out in its
// bounds, and a line taller than its font (Encore's labels set a line height) has the room above the glyphs.
static CGFloat baselineFromTop(UILabel *label) {
    NSAttributedString *text = label.attributedText;
    UIFont *font = text.length ? [text attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] : nil;
    if (![font isKindOfClass:UIFont.class]) font = label.font;
    CGFloat line = [label textRectForBounds:label.bounds limitedToNumberOfLines:1].size.height;
    return (label.bounds.size.height - line) / 2 + line + font.descender;
}

static CGFloat onPixels(CGFloat value, CGFloat scale) {
    return round(value * scale) / scale;
}

static void placeBadge(UIView *unit, BOOL redesigned, CGFloat timesDrop) {
    // Off, nothing is looked up or remembered; SGAudioQualitySettingChanged hid the badges made before.
    if (!sg_on || !unit) return;
    if (!sg_units) sg_units = [NSHashTable weakObjectsHashTable];
    [sg_units addObject:unit];
    SGAudioQualityBadge *badge = objc_getAssociatedObject(unit, &kBadgeKey);
    SGAudioTier tier = sg_shown.tier;
    if (!badge && tier == SGAudioTierNone) return;
    UIView *take = SGFindIdentifier(unit, @"now-playing-time-take-label", &kTakeKey);
    UIView *remaining = SGFindIdentifier(unit, @"now-playing-time-remaning-label", &kRemainingKey);
    if (!badge) {
        badge = [SGAudioQualityBadge new];
        badge.redesigned = redesigned;
        badge.alpha = 0;
        objc_setAssociatedObject(unit, &kBadgeKey, badge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!sg_badges) sg_badges = [NSHashTable weakObjectsHashTable];
        [sg_badges addObject:badge];
        SGLog(@"audio quality: a badge in %@, times %@", NSStringFromClass(unit.nextResponder.class), take && remaining ? @"found" : @"not found");
    }
    if (badge.superview != unit) [unit addSubview:badge];
    else if (unit.subviews.lastObject != badge) [unit bringSubviewToFront:badge];
    UIView *units = unit.superview;
    if (badge.tap.view != units) {
        [badge.tap.view removeGestureRecognizer:badge.tap];
        [units addGestureRecognizer:badge.tap];
    }

    BOOL wasShown = badge.alpha > 0;
    BOOL retitled = tier != SGAudioTierNone && tier != badge.tier;
    // The redesign's iPad player keeps this time row when it turns (PlayerLyrics.x's control column or the single
    // one), so there its times and their room decide; the native look and a phone's landscape screens hide it.
    BOOL rowTurns = redesigned && unit.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad;
    BOOL shown = tier != SGAudioTierNone && (rowTurns || !landscape(unit)) && timeShown(take, unit) && timeShown(remaining, unit);
    if (shown) {
        CGRect a = untransformedIn(take, unit), b = untransformedIn(remaining, unit);
        CGRect leading = CGRectGetMidX(a) <= CGRectGetMidX(b) ? a : b, trailing = CGRectGetMidX(a) <= CGRectGetMidX(b) ? b : a;
        // Under the middle of the bar, whose ends the two times line up with.
        CGFloat middle = (CGRectGetMinX(leading) + CGRectGetMaxX(trailing)) / 2;
        CGFloat room = 2 * MIN(middle - CGRectGetMaxX(leading), CGRectGetMinX(trailing) - middle) - 2 * kTimeGap;
        void (^retitle)(void) = ^{
            badge.tier = tier;
            CGSize size = [badge sizeThatFits:CGSizeZero];
            badge.bounds = CGRectMake(0, 0, size.width, size.height);
        };
        if (retitled && wasShown && badge.window) {
            [UIView transitionWithView:badge duration:kFade options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                            animations:retitle completion:nil];
        } else {
            retitle();
        }
        CGSize size = badge.bounds.size;
        shown = size.width <= room;
        CGPoint origin;
        UILabel *takeLabel = redesigned ? (UILabel *)SGFindIdentifier(unit, @"now-playing-time-take-label-internal", &kTakeLabelKey) : nil;
        if ([takeLabel isKindOfClass:UILabel.class] && [takeLabel isDescendantOfView:take]) {
            // The redesign's: the text's baseline on the elapsed time's, where the redesign has lowered the times, on
            // the screen's pixels.
            CGFloat scale = unit.window.screen.scale ?: UIScreen.mainScreen.scale;
            CGFloat baseline = CGRectGetMinY(a) + [takeLabel convertPoint:CGPointZero toView:take].y + baselineFromTop(takeLabel) + timesDrop;
            UIFont *font = badge.font;
            CGFloat textBaseline = size.height / 2 - font.lineHeight / 2 + font.ascender;
            origin = CGPointMake(onPixels(middle - size.width / 2, scale), onPixels(baseline - textBaseline, scale));
        } else {
            // Edges on whole points, so the text stays crisp.
            origin = CGPointMake(round(middle - size.width / 2), round(CGRectGetMidY(a) + timesDrop - size.height / 2));
        }
        badge.center = CGPointMake(origin.x + size.width / 2, origin.y + size.height / 2);
    }
    badge.shown = shown;
    if (!shown) checkDetails();
    CGFloat alpha = shown ? 1 : 0;
    if (badge.alpha == alpha) return;
    if (!badge.window || UIAccessibilityIsReduceMotionEnabled()) {
        badge.alpha = alpha;
        return;
    }
    [UIView animateWithDuration:kFade delay:0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ badge.alpha = alpha; } completion:nil];
}

void SGAudioQualityPlaceBadge(UIView *unit) {
    placeBadge(unit, NO, 0);
}

void SGAudioQualityPlaceRedesignedBadge(UIView *unit, CGFloat timesDrop) {
    placeBadge(unit, YES, timesDrop);
}

void SGAudioQualitySetRedesignedInk(UIView *unit, CGFloat ink, CGFloat fill, BOOL plusL) {
    [(SGAudioQualityBadge *)objc_getAssociatedObject(unit, &kBadgeKey) setInk:ink fill:fill plain:!plusL];
}

CGFloat SGAudioQualityStandardInk(void) {
    return kRedesignInkLight;
}

CGFloat SGAudioQualityStandardFill(void) {
    return kRedesignFillLight;
}

UIView *SGAudioQualityShownBadge(UIView *unit) {
    SGAudioQualityBadge *badge = objc_getAssociatedObject(unit, &kBadgeKey);
    return badge.superview == unit && badgeShown(badge) ? badge : nil;
}

static SGAudioQualityWatcher *sg_watcher;

%ctor {
    sg_on = SGFlag(SGKeyPlayerAudioQuality, NO);
    sg_watcher = [SGAudioQualityWatcher new];
    SGAddPlayerStateObserver(sg_watcher);
    // Posted on main (PlayerState.x); another device taking the song over takes the badge away.
    [NSNotificationCenter.defaultCenter addObserverForName:SGPlayerPlaybackLocationDidChangeNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) { update(SGPlayerState()); }];
    // Posted on main as the player opens or closes; the details are only up while it is open.
    [NSNotificationCenter.defaultCenter addObserverForName:SGPlayerTransitionNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) { [sg_panel close]; }];
    // The unit's first layout can come before its times have theirs, and opening the player does not lay the unit
    // out again on its own (seen on an iPhone 13 Pro, 9.1.90): once the player is up, the badge is placed again.
    [NSNotificationCenter.defaultCenter addObserverForName:SGPlayerTransitionEndedNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        if (!sg_on) return;
        for (UIView *unit in sg_units.allObjects) [unit setNeedsLayout];
    }];
}
