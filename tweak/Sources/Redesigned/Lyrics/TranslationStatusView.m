#import "Core/SGCore.h"
#import "TranslationStatusView.h"
#import "Redesigned/Kit/SGRTokens.h"

static const CGFloat kStatusSize = 12;
static const NSTimeInterval kStatusFade = 0.2;

// " · 12/40" while some of the song is in, nothing before the first batch.
static NSString *countOf(SGRAutoTranslationProgress *progress) {
    if (!progress.total || !progress.completed) return @"";
    return [NSString stringWithFormat:SGL(@"settings.lyricstools.status.count", @" · %lu/%lu"),
            (unsigned long)MIN(progress.completed, progress.total), (unsigned long)progress.total];
}

// What the note reads and shows for a snapshot, and whether a tap retries. Nil for nothing worth a note.
static NSString *noteFor(SGRAutoTranslationProgress *progress, NSString **symbol, BOOL *retryable) {
    NSString *name = SGRAutoTranslatorName(progress.provider);
    *retryable = NO;
    switch (progress.phase) {
        case SGRAutoTranslationPhaseRunning:
            *symbol = progress.attempt > 1 ? @"arrow.triangle.branch" : @"translate";
            if (!name) return [SGL(@"settings.lyricstools.status.running.generic", @"Translating") stringByAppendingString:countOf(progress)];
            return [[NSString stringWithFormat:progress.attempt > 1 ? SGL(@"settings.lyricstools.status.fallback", @"Trying %@ instead")
                                                                    : SGL(@"settings.lyricstools.status.running", @"Translating with %@"), name]
                    stringByAppendingString:countOf(progress)];
        case SGRAutoTranslationPhasePartial:
            *symbol = @"circle.lefthalf.filled";
            *retryable = YES;
            if (progress.total && progress.completed < progress.total)
                return [NSString stringWithFormat:SGL(@"settings.lyricstools.status.partial.count", @"%lu of %lu lines translated"),
                        (unsigned long)progress.completed, (unsigned long)progress.total];
            return SGL(@"settings.lyricstools.status.partial", @"Partly translated");
        case SGRAutoTranslationPhasePaused:
            *symbol = @"pause.circle";
            *retryable = YES;
            return [SGL(@"settings.lyricstools.status.paused", @"Translation paused") stringByAppendingString:countOf(progress)];
        case SGRAutoTranslationPhaseUnavailable:
            // Retrying cannot help until a service is set up, and the lyrics view has no safe way to open Mod Settings
            // over the player, so the note says where to go.
            *symbol = @"slash.circle";
            return SGL(@"settings.lyricstools.status.unavailable", @"Set up a translator in Lyrics › Translation & AI");
        case SGRAutoTranslationPhaseFailed: {
            *symbol = @"exclamationmark.triangle";
            *retryable = YES;
            NSString *service = name ?: SGL(@"settings.lyricstools.status.service", @"The service");
            switch (progress.failure) {
                case SGRAutoTranslationFailureConnection:
                    return [NSString stringWithFormat:SGL(@"settings.lyricstools.status.failed.connection", @"Couldn't reach %@"), service];
                case SGRAutoTranslationFailureAuthentication:
                    return [NSString stringWithFormat:SGL(@"settings.lyricstools.status.failed.key", @"%@ turned the key down"), service];
                case SGRAutoTranslationFailureBusy:
                    return [NSString stringWithFormat:SGL(@"settings.lyricstools.status.failed.busy", @"%@ is busy"), service];
                case SGRAutoTranslationFailureResponse:
                    return [NSString stringWithFormat:SGL(@"settings.lyricstools.status.failed.response", @"%@ sent an answer that couldn't be used"), service];
                default:
                    return SGL(@"settings.lyricstools.status.failed", @"Couldn't translate");
            }
        }
        default:
            return nil;
    }
}

@implementation SGRTranslationStatusView {
    UIButton *_control;
    UIImageView *_icon;
    UILabel *_label, *_retryLabel;
    NSString *_track, *_language;
    NSString *_shownText;
    BOOL _retryable;
}

// A glyph, the note and Retry in a plain custom button the row's full 44 pt high. Retry is a label of its own that
// never gives way, so a long note wraps to a second line and then truncates while Retry stays readable at its end.
// A button, so its tap wins over the lyrics view's own tap recognizer.
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.alpha = 0;
    self.hidden = YES;
    _control = [UIButton buttonWithType:UIButtonTypeCustom];
    _control.frame = self.bounds;
    _control.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_control addTarget:self action:@selector(tapped) forControlEvents:UIControlEventPrimaryActionTriggered];
    [_control addTarget:self action:@selector(pressed) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [_control addTarget:self action:@selector(released) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside |
                                                                          UIControlEventTouchDragExit | UIControlEventTouchCancel];
    [self addSubview:_control];
    _icon = [UIImageView new];
    _icon.tintColor = SGRSecondary();
    _icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithTextStyle:UIFontTextStyleCaption1 scale:UIImageSymbolScaleSmall];
    _icon.contentMode = UIViewContentModeCenter;
    [_icon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [_icon setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    _label = [UILabel new];
    _label.numberOfLines = 2;
    _label.lineBreakMode = NSLineBreakByTruncatingTail;
    [_label setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [_label setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    _retryLabel = [UILabel new];
    _retryLabel.numberOfLines = 1;
    _retryLabel.hidden = YES;
    [_retryLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [_retryLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[_icon, _label, _retryLabel]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 5;
    row.userInteractionEnabled = NO;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [_control addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:_control.leadingAnchor constant:4],
        [row.trailingAnchor constraintLessThanOrEqualToAnchor:_control.trailingAnchor constant:-4],
        [row.centerYAnchor constraintEqualToAnchor:_control.centerYAnchor],
        [row.topAnchor constraintGreaterThanOrEqualToAnchor:_control.topAnchor],
        [row.bottomAnchor constraintLessThanOrEqualToAnchor:_control.bottomAnchor],
    ]];
    _control.isAccessibilityElement = YES;
    return self;
}

- (BOOL)showsNote {
    return _shownText != nil;
}

- (UIFont *)noteFont:(UIFontWeight)weight {
    return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption1] scaledFontForFont:[UIFont systemFontOfSize:kStatusSize weight:weight]
                                                                         maximumPointSize:17];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (previous.preferredContentSizeCategory != self.traitCollection.preferredContentSizeCategory) [self drawNote];
}

- (void)drawNote {
    if (!_shownText) return;
    _label.font = [self noteFont:UIFontWeightSemibold];
    _label.textColor = SGRSecondary();
    _label.text = _shownText;
    _retryLabel.font = [self noteFont:UIFontWeightBold];
    _retryLabel.textColor = SGRPrimary();
    _retryLabel.text = SGL(@"settings.lyricstools.status.retry", @"Retry");
    _retryLabel.hidden = !_retryable;
    _icon.tintColor = SGRSecondary();
}

- (void)showProgress:(SGRAutoTranslationProgress *)progress track:(NSString *)track language:(NSString *)language {
    NSString *symbol = nil;
    BOOL retryable = NO;
    NSString *text = progress && track.length && language.length ? noteFor(progress, &symbol, &retryable) : nil;
    _track = text ? track : nil;
    _language = text ? language : nil;
    BOOL same = (text == _shownText || [text isEqualToString:_shownText]) && retryable == _retryable;
    _shownText = text;
    _retryable = retryable;
    if (!same && text) {
        [self drawNote];
        _icon.image = symbol ? [UIImage systemImageNamed:symbol] : nil;
        _icon.hidden = !_icon.image;
        _control.userInteractionEnabled = retryable;
        _control.accessibilityLabel = text;
        _control.accessibilityHint = retryable ? SGL(@"settings.lyricstools.status.retry.hint", @"Tries translating this song again") : nil;
        _control.accessibilityTraits = retryable ? UIAccessibilityTraitButton : UIAccessibilityTraitStaticText | UIAccessibilityTraitUpdatesFrequently;
    }
    if (!text) [self released];
    BOOL show = text != nil;
    if (!show && self.hidden) return;
    if (show && !self.hidden && self.alpha == 1) return;
    if (show) self.hidden = NO;
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : kStatusFade delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{ self.alpha = show ? 1 : 0; }
                     completion:^(BOOL finished) { if (finished && !self->_shownText) self.hidden = YES; }];
}

- (void)pressed {
    _control.alpha = 0.5;
}

- (void)released {
    [UIView animateWithDuration:0.15 animations:^{ self->_control.alpha = 1; }];
}

- (void)tapped {
    if (!_retryable || !_track || !_language || !self.retry) return;
    NSString *track = _track, *language = _language;
    self.retry(track, language);
}

- (NSArray *)accessibilityElements {
    return _shownText ? @[_control] : @[];
}
@end
