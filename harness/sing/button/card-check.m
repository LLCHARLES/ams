#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SGLastTrack.h"
#import "Shared/Sing/Sing.h"
#import "../../harness-fail.h"

UIView *SGSingCardView(void);
static __weak id<SGPlayerStateObserver> listener;
static NSUInteger reads;
@implementation SPTPlayerState
@end
@implementation SPTPlayerTrack
@end
@implementation SGShownTrack
@end
static SPTPlayerState *player;
SPTPlayerState *SGPlayerState(void) { return player; }
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) { listener = observer; }
id SGKaraokePlayer(void) { return nil; }
SGShownTrack *SGShownTrackNow(void) {
    SGShownTrack *shown = [SGShownTrack new];
    [shown setValue:@YES forKey:@"current"];
    [shown setValue:player.track.trackTitle forKey:@"title"];
    [shown setValue:player.track.artistName forKey:@"artist"];
    return shown;
}
BOOL SGSingReadLevels(float *v, float *r, int count) {
    reads++;
    for (int i = 0; i < count; i++) v[i] = r[i] = (float)(reads + i) / 100;
    return SGSingCurrentState() == SGSingStateSinging;
}

void SGCheckSingCard(UIView *root) {
    player = [SPTPlayerState new];
    SPTPlayerTrack *track = [SPTPlayerTrack new];
    [track setValue:@"spotify:track:harness" forKey:@"URI"];
    [player setValue:track forKey:@"track"];
    [player setValue:@YES forKey:@"isPlaying"];
    SGSetSingLevel(1);
    SGSetSingOn(YES);
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:root.bounds];
    [root addSubview:scroll];
    UIView *card = SGSingCardView();
    card.frame = (CGRect){CGPointZero, [card sizeThatFits:scroll.bounds.size]};
    scroll.contentSize = CGSizeMake(root.bounds.size.width, 2 * root.bounds.size.height);
    [scroll addSubview:card];
    [card layoutIfNeeded];
    NSTimer *timer = [card valueForKey:@"timer"];
    HARNESS_CHECK(timer.valid);
    NSUInteger before = reads;
    [timer fire];
    HARNESS_CHECK(reads > before);
    [timer fire];
    CAShapeLayer *vocal = [card valueForKey:@"vocals"];
    HARNESS_CHECK([vocal animationForKey:@"scroll"]);
    scroll.contentOffset = CGPointMake(0, card.bounds.size.height);
    before = reads;
    [card setNeedsLayout]; [card layoutIfNeeded];
    HARNESS_CHECK(!timer.valid && reads == before);
    scroll.contentOffset = CGPointZero;
    HARNESS_CHECK(reads > before && [[card valueForKey:@"timer"] isValid]);
    SGSetSingOn(NO);
    HARNESS_CHECK([[[card valueForKey:@"song"] accessibilityValue] containsString:@"Off"]);
    HARNESS_CHECK(![[card valueForKey:@"timer"] isValid]);
    [track setValue:@"Late title" forKey:@"trackTitle"];
    [track setValue:@"Late artist" forKey:@"artistName"];
    if ([listener respondsToSelector:@selector(playerStateDidReport:)]) [listener playerStateDidReport:player];
    HARNESS_CHECK([[[card valueForKey:@"title"] text] isEqual:@"Late title"]);
    HARNESS_CHECK([[[card valueForKey:@"artist"] text] isEqual:@"Late artist"]);
    HARNESS_CHECK([[[card valueForKey:@"song"] accessibilityLabel] isEqual:@"Late title, Late artist"]);
    [player setValue:@YES forKey:@"isPaused"];
    [listener playerStateDidChange:player];
    HARNESS_CHECK([[[card valueForKey:@"play"] accessibilityLabel] isEqual:@"Play"]);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    before = reads;
    SGSetSingOn(YES);
    [card setNeedsLayout]; [card layoutIfNeeded];
    HARNESS_CHECK(reads == before && ![[card valueForKey:@"timer"] isValid]);
    NSLog(@"[harness] PASS visible glide; offscreen/inactive graph asleep; event-driven accessibility");
    exit(0);
}
