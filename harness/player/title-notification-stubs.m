// Offline dependencies only. The controller, notification subscriptions, timer, controls,
// title/artist labels and animation helpers are compiled from production sources.
#import "title-notification-stubs.h"
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Lyrics/SGRKaraokeView.h"
#import "Redesigned/Player/Player.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"
#import "Shared/Fonts/Fonts.h"

@implementation SPTPlayerTrack
@end
@implementation SPTPlayerState
@end

static SPTPlayerState *state;
static NSHashTable *observers;
static NSMutableDictionary *answers;
static BOOL translations, simplify;

void SGTitleHarnessState(id uri, NSString *title, NSString *artist, BOOL paused) {
    SPTPlayerTrack *track = [SPTPlayerTrack new];
    [track setValue:uri forKey:@"URI"];
    [track setValue:title forKey:@"trackTitle"];
    [track setValue:artist forKey:@"artistName"];
    state = [SPTPlayerState new];
    [state setValue:track forKey:@"track"];
    [state setValue:@(paused) forKey:@"isPaused"];
    [state setValue:@(!paused) forKey:@"isPlaying"];
    for (id<SGPlayerStateObserver> observer in observers.allObjects) [observer playerStateDidChange:state];
}
void SGTitleHarnessClearState(void) { state = nil; }
SPTPlayerState *SGPlayerState(void) { return state; }
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) {
    if (!observers) observers = [NSHashTable weakObjectsHashTable];
    [observers addObject:observer];
}
NSUInteger SGTitleHarnessObserverCount(void) { return observers.allObjects.count; }
NSString *SGURIString(id uri) {
    return [uri isKindOfClass:NSURL.class] ? [uri absoluteString] :
        ([uri isKindOfClass:NSString.class] ? uri : nil);
}
void SGTitleHarnessAnswer(NSString *track, NSString *title, NSString *artist) {
    if (!answers) answers = [NSMutableDictionary dictionary];
    answers[track] = @[title, artist];
}
void SGTitleHarnessUseTranslations(BOOL enabled) { translations = enabled; }
void SGTitleHarnessSimplify(BOOL enabled) { simplify = enabled; }
NSString *SGLyricsSimplifiedTitle(NSString *title) { return [title componentsSeparatedByString:@" - "].firstObject; }
NSString *SGLyricsTranslatedTitle(NSString *track, NSString *title, NSString *artist, NSString **shownArtist) {
    NSArray *answer = translations && track ? answers[track] : nil;
    if (shownArtist) *shownArtist = answer ? answer[1] : artist;
    return answer.firstObject;
}
SGAppFont SGAppFontDrawn(void) { return SGAppFontSystem; }
BOOL SGRPlayerTwoColumns(void) { return NO; }
BOOL SGRStarAddOn(void) { return NO; }
UIView *SGRFindByIdentifier(UIView *root, NSString *identifier, const void *key) { return SGFindIdentifier(root, identifier, key); }
NSNotificationName const SGSimplifyTitlesDidChangeNotification = @"harness.simplify";
// The names are test-local; every subscriber/poster uses the production extern symbols.
NSNotificationName const SGTranslatedTitleDidChangeNotification = @"harness.translatedTitleDidChange";
NSNotificationName const SGTitleTranslationSettingsDidChangeNotification = @"harness.titleSettingsDidChange";
NSNotificationName const SGRNowPlayingArtworkDidChangeNotification = @"harness.artworkDidChange";

BOOL SGRedesignedUI(void) { return YES; }
NSInteger SGInt(NSString *key, NSInteger fallback) { return fallback; }
void SGPresentDark(UIViewController *controller) {}
BOOL SGEnabled(NSString *key) { return [key isEqualToString:SGRKeyLyricsAutoHide]; }
SGRLyricsHide SGRLyricsHideMode(void) { return SGRLyricsHideAll; }
BOOL SGRPlayerLyricsAvailable(void) { return YES; }
BOOL SGRPlayerLyricsNone(void) { return NO; }
// The lyrics turned sideways: with them closed the screen is the player's, laid out without lines.
BOOL SGRPlayerLyricsOpen(void) { return YES; }
BOOL SGFlag(NSString *key, BOOL fallback) {
    if ([key isEqual:SGKeyLyricsSimplifyTitles]) return simplify;
    if ([key isEqual:SGKeyLyricsTranslateTitles]) return translations;
    return fallback;
}
BOOL SGRPlayerIsTransitioning(void) { return NO; }
NSString *const SGPlayerTransitionEndedNotification = @"harness.playerTransitionEnded";
void SGRequireClasses(NSArray<NSString *> *names) {}
id SGKaraokePlayer(void) { return nil; }
UIImage *SGRNowPlayingArtwork(NSString **uri, NSString **identity) { return nil; }
UIColor *SGRAccentColor(void) { return nil; }

@implementation SGRArtworkField
- (void)setArtwork:(UIImage *)image identity:(NSString *)identity animated:(BOOL)animated {}
- (void)setProvisionalColor:(UIColor *)color {}
- (void)holdPage:(UIView *)page {}
- (void)showPage {}
@end
@implementation SGRKaraokeView
- (instancetype)initWithSampleLines:(NSArray *)lines length:(NSInteger)length { return [self initWithFrame:CGRectZero]; }
- (void)syncSiblings {}
@end
