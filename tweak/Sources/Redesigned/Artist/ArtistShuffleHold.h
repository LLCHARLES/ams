// Included only by the artist header. Both states come from Spotify's controls for this page.
#import "Core/SGLocalize.h"
#import "Redesigned/Kit/SGRActionRow.h"
#import "Redesigned/Kit/SGRRestyle.h"
#import "Shared/Haptics/Haptics.h"

static id artistStringsAsset(NSBundle *bundle, NSString *asset) {
    NSData *data = bundle ? [[NSDataAsset alloc] initWithName:asset bundle:bundle].data : nil;
    return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
}

static NSDictionary *artistControlWords(void) {
    static NSDictionary *words;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *url = [NSBundle.mainBundle URLForResource:@"SPTStrings" withExtension:@"bundle"];
        NSBundle *bundle = url ? [NSBundle bundleWithURL:url] : nil;
        NSArray *keys = artistStringsAsset(bundle, @"_i18n.KEYS");
        NSDictionary *files = artistStringsAsset(bundle, @"_i18n.INDEX");
        NSMutableDictionary *found = [NSMutableDictionary dictionary];
        for (NSString *language in [NSBundle.mainBundle.preferredLocalizations arrayByAddingObject:@"en"]) {
            NSString *file = [files isKindOfClass:NSDictionary.class] ? files[language] : nil;
            NSArray *values = artistStringsAsset(bundle, [@"_i18n." stringByAppendingString:file ?: language]);
            if (![keys isKindOfClass:NSArray.class] || ![values isKindOfClass:NSArray.class]) continue;
            for (NSString *key in @[@"ShuffleButtonOff", @"ShuffleButtonOn", @"ShuffleButtonOnSmartShuffle",
                                    @"AccessibilityPlay", @"AccessibilityPause", @"AccessibilityShufflePlay"]) {
                NSUInteger i = [keys indexOfObject:[@"encore:sEncore" stringByAppendingString:key]];
                if (i >= values.count || ![values[i] isKindOfClass:NSString.class] || ![values[i] length]) continue;
                if (!found[key]) found[key] = [NSMutableSet set];
                [found[key] addObject:values[i]];
            }
        }
        words = found;
    });
    return words;
}

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
    NSDictionary *words = artistControlWords();
    NSString *value = self.shuffle.accessibilityValue, *label = self.play.accessibilityLabel;
    if (!value || !label) return NO;
    *on = [words[@"ShuffleButtonOn"] containsObject:value] || [words[@"ShuffleButtonOnSmartShuffle"] containsObject:value];
    *playing = [words[@"AccessibilityPause"] containsObject:label];
    return (*on || [words[@"ShuffleButtonOff"] containsObject:value]) &&
           (*playing || [words[@"AccessibilityPlay"] containsObject:label] || [words[@"AccessibilityShufflePlay"] containsObject:label]);
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
