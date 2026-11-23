// A control of Spotify's fired from code as a tap on it would be (ContextMenu.h): the ⋯'s sheet, a menu row's
// control, the title row's buttons and the header's down arrow from the grabber.
#import "ContextMenu.h"

UIControlEvents SGRControlActionEvents(UIControl *control) {
    __block UIControlEvents events = 0;
    [control enumerateEventHandlers:^(UIAction *action, id target, SEL selector, UIControlEvents handled, BOOL *stop) {
        if (!action && [target conformsToProtocol:@protocol(SGRControlWatcher)]) return;
        events |= handled;
    }];
    return events;
}

NSString *SGRFireControl(UIControl *control) {
    if (!control) return @"nothing to fire";
    UIControlEvents events = SGRControlActionEvents(control);
    if (events & UIControlEventPrimaryActionTriggered) {
        [control sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
        return [NSString stringWithFormat:@"%@'s primary action", NSStringFromClass(control.class)];
    }
    if (events & UIControlEventTouchUpInside) {
        [control sendActionsForControlEvents:UIControlEventTouchUpInside];
        return [NSString stringWithFormat:@"%@'s touch up inside", NSStringFromClass(control.class)];
    }
    BOOL done = [control accessibilityActivate];
    return [NSString stringWithFormat:@"%@'s accessibility activation (%@, events 0x%lx)", NSStringFromClass(control.class), done ? @"taken" : @"refused", (unsigned long)events];
}
