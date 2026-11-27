// A podcast's speed button at an end of the controls row (Components.UI.SpeedControlButtonNowPlaying), on one line and
// inside the button (issue #28). Spotify writes the speed in a stack of two Encore labels, the value ("1.25배속" in
// Korean) and "×", centered on the 48 pt button, and turns the stack to a column when the value is long (9.2.0,
// tnative: 1.25 in 15 pt with "×" under it), the stack reaching past the button either way, past the row's edge for a
// Korean "1배속×" in 21 pt (stack {-14, 9} in a button at the row's start). The stack is kept a line and scaled down,
// never up, to the button's width about its center, so every word it draws is where the button takes its tap and
// VoiceOver frames it, short of the next control. A transform over Spotify's layout, which stays underneath; the
// button keeps its touches, accessibility and Spotify's text, font and color.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Player.h"

static NSString *const kSpeedButtonID = @"Components.UI.SpeedControlButtonNowPlaying";
static char kSpeedButtonKey, kWatchedKey;

@interface SGRSpeedLabelOwner : NSObject
@property (nonatomic, weak) UIView *button;
@end
@implementation SGRSpeedLabelOwner
@end

// The stack of Spotify's speed labels inside the button: the stack view that holds the labels.
static UIStackView *labelStackIn(UIView *view) {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:UIStackView.class] && ((UIStackView *)sub).arrangedSubviews.count > 1) return (UIStackView *)sub;
        UIStackView *found = labelStackIn(sub);
        if (found) return found;
    }
    return nil;
}

static void fit(UIStackView *labels, UIView *button) {
    if (!labels.superview) return;
    if (labels.axis != UILayoutConstraintAxisHorizontal) {
        labels.axis = UILayoutConstraintAxisHorizontal;
        labels.spacing = 0;
    }
    // The line Spotify's layout gives the stack and its middle in the button, the transform left out: the line is
    // scaled about that middle, so it fits twice the nearer of the button's two sides.
    CGFloat line = [labels systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].width;
    CGFloat middle = [labels.superview convertPoint:labels.center toView:button].x;
    CGRect bounds = button.bounds;
    CGFloat room = 2 * MIN(middle - CGRectGetMinX(bounds), CGRectGetMaxX(bounds) - middle);
    if (line < 1 || room <= 0) return;
    CGFloat scale = MIN(1, room / line);
    CGAffineTransform transform = CGAffineTransformMakeScale(scale, scale);
    if (!CGAffineTransformEqualToTransform(labels.transform, transform)) labels.transform = transform;
}

void SGRPlayerFitSpeedLabel(UIView *host) {
    UIView *button = SGRFindByIdentifier(host, kSpeedButtonID, &kSpeedButtonKey);
    UIStackView *labels = labelStackIn(button);
    if (!labels) return;
    // Spotify lays the stack out again as the speed changes, with no pass of the controls after it.
    SGRSpeedLabelOwner *owner = objc_getAssociatedObject(labels, &kWatchedKey);
    if (!owner) {
        owner = [SGRSpeedLabelOwner new];
        objc_setAssociatedObject(labels, &kWatchedKey, owner, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGRObserveLayout(labels, ^(UIView *view) {
            UIView *watchedButton = owner.button;
            if (watchedButton) fit((UIStackView *)view, watchedButton);
        });
    }
    owner.button = button;
    fit(labels, button);
}
