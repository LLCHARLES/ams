#import "LocalMusicPlayback.h"
#import "Core/SGLocalize.h"

BOOL SGLocalMusicSupportsVersion(NSString *version) {
    return [version isEqual:@"9.1.90"] || [version isEqual:@"9.2.0"];
}

BOOL SGLocalMusicObservationContract(Class stateClass, Class trackClass) {
    for (NSString *name in @[@"track", @"isPlaying", @"isLoading", @"position", @"playbackId"])
        if (![stateClass instancesRespondToSelector:NSSelectorFromString(name)]) return NO;
    for (NSString *name in @[@"URI", @"metadata"])
        if (![trackClass instancesRespondToSelector:NSSelectorFromString(name)]) return NO;
    return YES;
}

@implementation SGLocalMusicObservations {
    NSArray *_lastLoad;
}
- (NSDictionary *)captureURI:(NSString *)uri path:(NSString *)path playbackID:(id)playbackID
                readIdentity:(NSArray *(^)(void))readIdentity {
    if (!uri.length || !path.length || !playbackID) return nil;
    NSArray *load = @[uri, path, playbackID];
    if ([_lastLoad isEqual:load]) return nil;
    _lastLoad = load;
    NSArray *identity = [readIdentity() copy];
    return identity ? @{@"uri": [uri copy], @"identity": identity} : nil;
}
- (NSDictionary *)verifiedObservation:(NSDictionary *)observation currentIdentity:(NSArray *)identity {
    return identity && [observation[@"identity"] isEqual:identity] ? observation : nil;
}
@end

NSString *SGLocalMusicFailureMessage(NSError *error) {
    id reasons = error.userInfo[@"kSPTPlayerErrorDisallowReasonsKey"];
    if ([error.domain isEqual:@"com.spotify.SPTPlayer"] &&
        ([reasons isKindOfClass:NSSet.class] || [reasons isKindOfClass:NSArray.class]) &&
        [reasons containsObject:@"mft_disallow"])
        return SGL(@"settings.localmusic.free_limit", @"Spotify Free limits playing chosen songs. Spoof Premium in Retrine Settings lifts this limit.");
    return SGL(@"settings.localmusic.failed", @"Spotify could not play this.");
}
