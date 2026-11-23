// What photo-hero-check does not compile: the rest of the artist header's pass (the Kit's header info and lookups,
// Follow, About, the logo), which the harness never runs, and the hooks the field leans on elsewhere.
#import <UIKit/UIKit.h>
#import "motion-view-stubs.h"
#import "Redesigned/Kit/SGRHeaderInfo.h"

const CGFloat SGRHeaderInfoBottom = 14;
const CGFloat SGRHeaderInfoTitleRise = 56;
@implementation SGRHeaderInfo
@end

// Play's hold to shuffle (ArtistShuffleHold.h): never pressed here.
#import "Redesigned/Kit/SGRActionRow.h"
#import "Shared/Haptics/Haptics.h"
@implementation SGRPlayCapsule
@end
void SGPlayFeedback(SGFeedback feedback) {}
BOOL SGRActivate(UIView *source) { return NO; }
BOOL SGRSourceEnabled(UIView *source) { return NO; }

// Core/SGLocalize.m: English.
NSString *SGL(NSString *key, NSString *english) { return english; }

// Redesigned/Kit/SGRRepaint.x and SGRAccent.x.
__weak UIView *sgr_artistRoot = nil;
UIColor *SGRAccentColor(void) { return nil; }
BOOL SGIsBaseSurface(CGColorRef color) { return NO; }

// Redesigned/Kit/SGRBridges.x: the field asks whether the player is opening or closing.
BOOL SGRPlayerIsTransitioning(void) { return NO; }
void SGRObservePlayerTransition(id owner, void (^changed)(id owner)) {}

// Core/SGUIMode.m: the redesign is on, every hook installs.
BOOL SGRedesignedUI(void) { return YES; }

// Shared/AnimatedArtwork: Apple Music on, as it is by default; no logo.
BOOL SGMotionAppleMusicOn(void) { return YES; }
CGFloat SGMotionPixels(void) { return 720; }
void SGMotionArtistLogo(NSString *name, CGFloat pixels, void (^done)(UIImage *logo)) {}

// Redesigned/Kit/SGRRestyle.m and SGRActionRow.m: the lookups, as the header check has them.
void SGForEachView(UIView *view, void (^visit)(UIView *)) {
    if (!view) return;
    visit(view);
    for (UIView *child in view.subviews) SGForEachView(child, visit);
}
UIView *SGRFindByIdentifier(UIView *view, NSString *identifier, const void *key) {
    BOOL match = [identifier hasSuffix:@"*"] ? [view.accessibilityIdentifier hasPrefix:[identifier substringToIndex:identifier.length - 1]]
                                             : [view.accessibilityIdentifier isEqual:identifier];
    if (match) return view;
    for (UIView *child in view.subviews) {
        UIView *found = SGRFindByIdentifier(child, identifier, NULL);
        if (found) return found;
    }
    return nil;
}
NSString *SGRFirstLabelText(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) return ((UILabel *)view).text;
    for (UIView *child in view.subviews) {
        NSString *text = SGRFirstLabelText(child);
        if (text.length) return text;
    }
    return nil;
}
UIImageView *SGRHeaderArtworkIn(UIView *root) { return nil; }
BOOL SGRObserveLayout(UIView *view, void (^laidOut)(UIView *view)) { return NO; }
void SGRBlankView(UIView *view) {}
SGRMirrorButton *SGRPinnedMore(UIView *page, const void *key, UIView *more) { return nil; }

// Artist/ArtistFollow.x and ArtistSections.x.
BOOL SGRArtistFollowing(UIView *page, NSString *moreIdentifier, BOOL *following, void (^changed)(void)) { return NO; }
BOOL SGRArtistListenersInAbout(UIView *header, UIView *metadata, UIView *more) { return NO; }
