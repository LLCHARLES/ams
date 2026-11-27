// Included only by the artist header. Both states come from Spotify's controls for this page.
#import "Core/SGLocalize.h"
#import "Redesigned/Kit/SGRActionRow.h"
#import "Redesigned/Kit/SGRRestyle.h"
#import "Shared/Haptics/Haptics.h"

@interface SGRArtistHold : UILongPressGestureRecognizer <UIGestureRecognizerDelegate>
@property(nonatomic, weak) UIView *shuffle, *play, *header;
@property(nonatomic, copy) NSString *artist, *heldArtist;
@property(nonatomic, weak) UIView *heldPlay, *heldShuffle;
@end

@implementation SGRArtistHold
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    // The drag guard cancels control tracking, not the page's scroll gesture.
    return YES;
}
- (BOOL)readShuffleOn:(BOOL *)on playing:(BOOL *)playing {
    SGRPlayCapsule *capsule = (SGRPlayCapsule *)self.view;
    if (!self.artist.length || !capsule.window || capsule.hidden || self.play != capsule.source ||
        self.header.window != capsule.window || ![self.play isDescendantOfView:self.header] ||
        ![self.shuffle isDescendantOfView:self.header] || !SGRSourceEnabled(self.play) || !SGRSourceEnabled(self.shuffle)) return NO;
    NSDictionary<NSString *, NSSet<NSString *> *> *words = SGRSpotifyControlWords();
    NSString *value = self.shuffle.accessibilityValue;
    if (!value) return NO;
    *on = [words[@"ShuffleButtonOn"] containsObject:value] || [words[@"ShuffleButtonOnSmartShuffle"] containsObject:value];
    if (!*on && ![words[@"ShuffleButtonOff"] containsObject:value]) return NO;
    if (SGRPlayButtonPlaying(self.play, playing)) return YES;
    // Without the play button's own state, only its label tells, in the languages Spotify's strings carry.
    NSString *label = self.play.accessibilityLabel;
    if (!label) return NO;
    *playing = [words[@"AccessibilityPause"] containsObject:label];
    return *playing || [words[@"AccessibilityPlay"] containsObject:label] || [words[@"AccessibilityShufflePlay"] containsObject:label];
}
- (BOOL)shuffleArtist {
    BOOL on, playing;
    if (![self readShuffleOn:&on playing:&playing]) return NO;
    if (on) SGPlayFeedback(SGFeedbackGrab);
    else {
        if (!SGRActivate(self.shuffle) || ![self readShuffleOn:&on playing:&playing] || !on) return NO;
    }
    return playing || SGRActivate(self.play);
}
- (BOOL)voiceShuffle:(UIAccessibilityCustomAction *)action {
    return [self shuffleArtist];
}
- (void)trackHold {
    BOOL inside = CGRectContainsPoint(self.view.bounds, [self locationInView:self.view]);
    if (self.state == UIGestureRecognizerStateBegan) {
        BOOL on, playing;
        self.heldArtist = inside && [self readShuffleOn:&on playing:&playing] ? self.artist : nil;
        self.heldPlay = self.play;
        self.heldShuffle = self.shuffle;
    } else {
        if (!inside || self.heldPlay != self.play || self.heldShuffle != self.shuffle ||
            ![self.heldArtist isEqual:self.artist]) self.heldArtist = nil;
        if (self.state == UIGestureRecognizerStateEnded && self.heldArtist) [self shuffleArtist];
        if (self.state != UIGestureRecognizerStateChanged) self.heldArtist = nil;
    }
}
@end

static void artistBindHold(SGRHeaderInfo *info, UIView *header, UIView *play, UIView *shuffle, NSString *artist) {
    for (UIView *view in info.subviews) {
        if (![view isKindOfClass:SGRPlayCapsule.class]) continue;
        static char key;
        SGRArtistHold *hold = objc_getAssociatedObject(view, &key);
        if (!hold) {
            hold = [SGRArtistHold new];
            [hold addTarget:hold action:@selector(trackHold)];
            [view addGestureRecognizer:hold];
            // A swipe before the hold threshold fails the hold, but UIControl's drag-out
            // slop can still send touchUpInside even when lifted outside the capsule.
            UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc] initWithTarget:nil action:nil];
            drag.delegate = hold;
            [view addGestureRecognizer:drag];
            objc_setAssociatedObject(view, &key, hold, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            UIAccessibilityCustomAction *action = [[UIAccessibilityCustomAction alloc]
                initWithName:SGL(@"settings.gestures.action.shuffle", @"Shuffle") target:hold selector:@selector(voiceShuffle:)];
            view.accessibilityCustomActions = [(view.accessibilityCustomActions ?: @[]) arrayByAddingObject:action];
        }
        if (hold.play != play || hold.shuffle != shuffle || ![hold.artist isEqual:artist]) hold.heldArtist = nil;
        hold.header = header;
        hold.play = play;
        hold.shuffle = shuffle;
        hold.artist = artist;
        return;
    }
}
