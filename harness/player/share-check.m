#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Redesigned/Player/ShareCards.h"
#import "Redesigned/Lyrics/LyricCardPicker.h"
#import "Shared/Lyrics/Lyrics.h"
#import "../harness-fail.h"

// Measure the real UIKit boundaries without substituting the sheet or the renderer.
void SGRHarnessRunShare(UIWindow *window, BOOL systemOnly) {
    NSString *scenario = systemOnly ? @"share-system" : @"share";
    __block NSUInteger sheets = 0, renders = 0;
    __block BOOL finished = NO;
    __block CFTimeInterval lastBeat = CACurrentMediaTime(), longestGap = 0;
    NSTimer *heartbeat = [NSTimer scheduledTimerWithTimeInterval:0.01 repeats:YES block:^(NSTimer *timer) {
        CFTimeInterval now = CACurrentMediaTime();
        longestGap = MAX(longestGap, now - lastBeat);
        lastBeat = now;
    }];
    [NSTimer scheduledTimerWithTimeInterval:60 repeats:NO block:^(NSTimer *timer) {
        if (!finished) HARNESS_FAIL(@"share scenario did not finish");
    }];
    SEL renderSelector = @selector(imageWithActions:);
    Method render = class_getInstanceMethod(UIGraphicsImageRenderer.class, renderSelector);
    IMP originalRender = method_getImplementation(render);
    method_setImplementation(render, imp_implementationWithBlock(^UIImage *(UIGraphicsImageRenderer *renderer, void (^actions)(UIGraphicsImageRendererContext *)) {
        CFTimeInterval began = CACurrentMediaTime();
        UIImage *image = ((UIImage *(*)(id, SEL, id))originalRender)(renderer, renderSelector, actions);
        BOOL card = CGImageGetWidth(image.CGImage) == 1080 && CGImageGetHeight(image.CGImage) == 1350;
        if (card) {
            if (NSThread.isMainThread) HARNESS_FAIL(@"card rendered on main");
            @synchronized (window) { renders++; }
            NSLog(@"[share timing] card render %.1f ms, main=%d", (CACurrentMediaTime() - began) * 1000, NSThread.isMainThread);
        }
        return image;
    }));
    SEL initSelector = @selector(initWithActivityItems:applicationActivities:);
    Method initializer = class_getInstanceMethod(UIActivityViewController.class, initSelector);
    IMP originalInit = method_getImplementation(initializer);
    method_setImplementation(initializer, imp_implementationWithBlock(^void *(void *receiver, NSArray *items, NSArray *activities) {
        if (!systemOnly) {
            UIImage *card = items.firstObject;
            if (![card isKindOfClass:UIImage.class] || CGImageGetWidth(card.CGImage) != 1080 || CGImageGetHeight(card.CGImage) != 1350) {
                HARNESS_FAIL(@"shared card pixels are not 1080x1350");
            }
        }
        CFTimeInterval began = CACurrentMediaTime();
        void *result = ((void *(*)(void *, SEL, id, id))originalInit)(receiver, initSelector, items, activities);
        NSLog(@"[share timing] %@ sheet %lu UIKit init %.1f ms, main=%d", scenario, (unsigned long)++sheets,
              (CACurrentMediaTime() - began) * 1000, NSThread.isMainThread);
        return result;
    }));
    SEL presentSelector = @selector(presentViewController:animated:completion:);
    Method presentation = class_getInstanceMethod(UIViewController.class, presentSelector);
    IMP originalPresent = method_getImplementation(presentation);
    method_setImplementation(presentation, imp_implementationWithBlock(^(UIViewController *host, UIViewController *controller, BOOL animated, dispatch_block_t completion) {
        BOOL activity = [controller isKindOfClass:UIActivityViewController.class];
        CFTimeInterval began = CACurrentMediaTime();
        ((void (*)(id, SEL, id, BOOL, id))originalPresent)(host, presentSelector, controller, animated, ^{
            if (completion) completion();
            if (!activity) return;
            NSLog(@"[share timing] %@ sheet %lu appeared after %.1f ms; longest main heartbeat gap %.1f ms",
                  scenario, (unsigned long)sheets, (CACurrentMediaTime() - began) * 1000, longestGap * 1000);
            [host dismissViewControllerAnimated:NO completion:^{
                if (!systemOnly && sheets == 1) {
                    SGRLyricCardLine *line = [SGRLyricCardLine new];
                    line.text = @"A song for you 🎵";
                    line.pronunciation = @"A song for you";
                    SGRPresentLyricCardPicker(@[line], 0, YES, SGKaraokePlayingTrack());
                    return;
                }
                @synchronized (window) {
                    if (!systemOnly && renders != 2) HARNESS_FAIL(@"two cards were not rendered");
                }
                finished = YES;
                [heartbeat invalidate];
                NSLog(@"[harness] %@ checks: %d of %d right -- PASS", scenario, systemOnly ? 1 : 2, systemOnly ? 1 : 2);
                exit(0);
            }];
        });
        if (activity) NSLog(@"[share timing] %@ UIKit present synchronous %.1f ms", scenario, (CACurrentMediaTime() - began) * 1000);
    }));
    // Use the picker's real Share action only after its presentation has completed.
    SEL appearedSelector = @selector(viewDidAppear:);
    Class picker = NSClassFromString(@"SGRLyricCardPicker");
    Method appeared = class_getInstanceMethod(picker, appearedSelector);
    IMP originalAppeared = method_getImplementation(appeared);
    class_addMethod(picker, appearedSelector, imp_implementationWithBlock(^(UIViewController *host, BOOL animated) {
        ((void (*)(id, SEL, BOOL))originalAppeared)(host, appearedSelector, animated);
        dispatch_async(dispatch_get_main_queue(), ^{
            UIBarButtonItem *share = host.navigationItem.rightBarButtonItem;
            [UIApplication.sharedApplication sendAction:share.action to:share.target from:share forEvent:nil];
        });
    }), method_getTypeEncoding(appeared));
    dispatch_async(dispatch_get_main_queue(), ^{
        if (systemOnly) {
            UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[@"Retrine"] applicationActivities:nil];
            [window.rootViewController presentViewController:sheet animated:YES completion:nil];
        } else {
            SGRShareSongCard(window.rootViewController.view);
        }
    });
}
