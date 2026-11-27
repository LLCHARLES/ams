#pragma once
#import <UIKit/UIKit.h>

// Main thread. Points are in window coordinates. Keep the returned touch through up.
UITouch *SGHarnessTouchDown(UIWindow *window, CGPoint point);
void SGHarnessTouchMove(UITouch *touch, CGPoint point);
void SGHarnessTouchUp(UITouch *touch, CGPoint point);

void SGHarnessTap(UIWindow *window, CGPoint point);
void SGHarnessHold(UIWindow *window, CGPoint point, NSTimeInterval seconds);
void SGHarnessDrag(UIWindow *window, CGPoint from, CGPoint to, NSTimeInterval seconds);
