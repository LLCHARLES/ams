#import "LocalMusicPlayback.h"
#import "LocalMusicStore.h"
#import "LocalAudioImport.h"
#import "Core/SGCore.h"
#import "Shared/Player/PlayerState.h"

NSNotificationName const SGLocalMusicPlaybackDidChangeNotification = @"spotifyglass.localFiles.playbackDidChange";
static NSString *const kIdentitiesKey = @"spotifyglass.localFiles.playbackIdentities";
static NSTimeInterval const kCommandTimeoutSeconds = 15;
static BOOL sg_observationAvailable;
static BOOL supported(void) {
    return SGLocalMusicSupportsVersion([NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]);
}
@interface SPTPlayerContext : NSObject
+ (instancetype)contextWithTracks:(NSArray *)tracks;
@property (nonatomic, strong) NSURL *URI;
@end
@interface SPTPlayerOptionOverrides : NSObject
@property (nonatomic, strong) NSNumber *shufflingContext;
@end
@interface SPTSkipToTrack : NSObject
- (instancetype)initWithTrackURI:(NSURL *)uri;
@end
@interface SPTPlayOptions : NSObject
@property (nonatomic, copy) SPTPlayerOptionOverrides *playerOptionsOverride;
@property (nonatomic, copy) SPTSkipToTrack *skipTo;
@end
@interface SPTPlayerTrack (SGLocalMusicPlayback)
- (instancetype)initWithURI:(NSURL *)uri albumURI:(NSURL *)album artistURI:(NSURL *)artist andUID:(NSString *)uid;
@end
@interface SPTPlayerState (SGLocalMusicPlayback)
@property (nonatomic, readonly) id playbackId;
@end
@interface SPTPlayerQueueWrapperImpl : NSObject
- (instancetype)initWithPlayer:(id)player;
- (id)queueMultipleTracks:(NSArray *)tracks loggingParams:(id)params;
- (id)queueTrackPlayNext:(SPTPlayerTrack *)track;
@end
@protocol SGLocalMusicPlayer <NSObject>
- (id)playContext:(SPTPlayerContext *)context options:(SPTPlayOptions *)options;
@end
@protocol SGLocalMusicTask <NSObject>
- (id)addCallback:(void (^)(id))callback on:(dispatch_queue_t)queue;
- (id)addErrorCallback:(void (^)(NSError *))callback on:(dispatch_queue_t)queue;
@end

BOOL SGLocalMusicPlaybackAvailable(void) {
    return supported() && sg_observationAvailable && [SGPlayer() respondsToSelector:@selector(playContext:options:)] &&
        [NSClassFromString(@"SPTPlayerContext") respondsToSelector:@selector(contextWithTracks:)] &&
        [NSClassFromString(@"SPTPlayerContext") instancesRespondToSelector:@selector(setURI:)] &&
        [NSClassFromString(@"SPTSkipToTrack") instancesRespondToSelector:@selector(initWithTrackURI:)] &&
        [NSClassFromString(@"SPTPlayOptions") instancesRespondToSelector:@selector(setSkipTo:)] &&
        [NSClassFromString(@"SPTPlayOptions") instancesRespondToSelector:@selector(setPlayerOptionsOverride:)] &&
        [NSClassFromString(@"SPTPlayerOptionOverrides") instancesRespondToSelector:@selector(setShufflingContext:)] &&
        [NSClassFromString(@"SPTPlayerTrack") instancesRespondToSelector:@selector(initWithURI:albumURI:artistURI:andUID:)] &&
        [NSClassFromString(@"SPTPlayerQueueWrapperImpl") instancesRespondToSelector:@selector(initWithPlayer:)] &&
        [NSClassFromString(@"SPTPlayerQueueWrapperImpl") instancesRespondToSelector:@selector(queueMultipleTracks:loggingParams:)] &&
        [NSClassFromString(@"SPTPlayerQueueWrapperImpl") instancesRespondToSelector:@selector(queueTrackPlayNext:)];
}
NSString *SGLocalMusicVerifiedURI(NSString *name, NSArray *identity) {
    if (!supported() || !identity) return nil;
    NSDictionary *entry = [NSUserDefaults.standardUserDefaults dictionaryForKey:kIdentitiesKey][name];
    if (![entry isKindOfClass:NSDictionary.class] || !SGLocalMusicSupportsVersion(entry[@"version"]) ||
        ![identity isEqual:entry[@"identity"]]) return nil;
    NSString *uri = entry[@"uri"];
    return [uri isKindOfClass:NSString.class] && [uri hasPrefix:@"spotify:local:"] ? uri : nil;
}

// Spotify's loaded track supplies the URI and physical path together. Edits and guessed tag URIs
// never grant playback, and replacing the imported file invalidates its recorded identity.
@interface SGLocalMusicIdentityObserver : NSObject <SGPlayerStateObserver>
@end
@implementation SGLocalMusicIdentityObserver {
    SGLocalMusicObservations *_observations;
    dispatch_queue_t _queue;
}
- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("spotifyglass.localFiles.playbackIdentity", DISPATCH_QUEUE_SERIAL);
        _observations = [SGLocalMusicObservations new];
        SGAddPlayerStateObserver(self);
    }
    return self;
}
- (void)playerStateDidChange:(SPTPlayerState *)state {}
- (void)playerStateDidReport:(SPTPlayerState *)state {
    if (!state.isPlaying || state.isLoading || state.position <= 0 || !SGPlayerPlaybackIsLocal()) return;
    NSString *uri = SGURIString(state.track.URI);
    id rawPath = state.track.metadata[@"local_file_path"];
    if (![uri hasPrefix:@"spotify:local:"] || ![rawPath isKindOfClass:NSString.class]) return;
    NSString *path = [rawPath stringByStandardizingPath];
    NSURL *folder = SGLocalAudioFolder();
    NSString *name = path.lastPathComponent;
    if (![[folder URLByAppendingPathComponent:name].path.stringByStandardizingPath isEqual:path]) return;
    NSDictionary *observation = [_observations captureURI:uri path:path playbackID:state.playbackId
        readIdentity:^{ return SGLocalMusicFileIdentity([NSURL fileURLWithPath:path]); }];
    if (!observation) return;
    dispatch_async(_queue, ^{
        NSArray *names = SGLocalAudioImportedNames(folder, NSUserDefaults.standardUserDefaults);
        if (![names containsObject:name]) return;
        NSArray *identity = SGLocalMusicFileIdentity([NSURL fileURLWithPath:path]);
        NSDictionary *verified = [self->_observations verifiedObservation:observation currentIdentity:identity];
        if (!verified) return;
        NSMutableDictionary *entries = [[NSUserDefaults.standardUserDefaults dictionaryForKey:kIdentitiesKey] mutableCopy] ?: [NSMutableDictionary dictionary];
        for (NSString *old in entries.allKeys) if (![names containsObject:old]) [entries removeObjectForKey:old];
        entries[name] = @{@"uri": verified[@"uri"], @"identity": verified[@"identity"],
            @"version": [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]};
        [NSUserDefaults.standardUserDefaults setObject:entries forKey:kIdentitiesKey];
        dispatch_async(dispatch_get_main_queue(), ^{
            SGLog(@"local music: Spotify assigned %@ to %@", uri, name);
            [NSNotificationCenter.defaultCenter postNotificationName:SGLocalMusicPlaybackDidChangeNotification object:nil];
        });
    });
}
@end

BOOL SGLocalMusicCanPlaySongs(NSArray<SGLocalMusicSong *> *songs) {
    if (!songs.count || !SGLocalMusicPlaybackAvailable()) return NO;
    for (SGLocalMusicSong *song in songs) if (!song.playbackURI.length) return NO;
    return YES;
}
static NSError *unavailable(void) { return [NSError errorWithDomain:@"Retrine.LocalMusic" code:1 userInfo:nil]; }
@interface SGLocalMusicCommand : NSObject
@property (nonatomic, strong) id<SGLocalMusicTask> task;
@property (nonatomic, strong) SPTPlayerQueueWrapperImpl *wrapper;
@property (nonatomic, copy) void (^done)(NSError *);
@property (nonatomic) BOOL finished;
- (void)finish:(NSError *)error;
- (void)observe:(id)task;
@end
static SGLocalMusicCommand *sg_command;
@implementation SGLocalMusicCommand
- (void)finish:(NSError *)error {
    if (self.finished) return;
    self.finished = YES;
    void (^done)(NSError *) = self.done;
    self.done = nil; self.task = nil; self.wrapper = nil;
    sg_command = nil;
    if (error) SGLog(@"local music: command refused %@", error);
    else SGLog(@"local music: command confirmed");
    done(error);
}
- (void)observe:(id)task {
    if (![task respondsToSelector:@selector(addCallback:on:)] || ![task respondsToSelector:@selector(addErrorCallback:on:)]) {
        [self finish:unavailable()]; return;
    }
    self.task = task;
    __weak typeof(self) weakSelf = self;
    [task addCallback:^(id value) { [weakSelf finish:nil]; } on:dispatch_get_main_queue()];
    [task addErrorCallback:^(NSError *error) { [weakSelf finish:error]; } on:dispatch_get_main_queue()];
}
@end

static void prepare(NSArray<SGLocalMusicSong *> *songs, void (^done)(NSError *),
                    void (^submit)(SGLocalMusicCommand *, NSArray<SPTPlayerTrack *> *)) {
    if (!songs.count) { done(nil); return; }
    if (sg_command || !SGLocalMusicCanPlaySongs(songs)) { done(unavailable()); return; }
    SGLocalMusicCommand *request = [SGLocalMusicCommand new];
    request.done = done; sg_command = request;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSURL *folder = SGLocalAudioFolder();
        NSSet *names = [NSSet setWithArray:SGLocalAudioImportedNames(folder, NSUserDefaults.standardUserDefaults)];
        BOOL valid = YES;
        for (SGLocalMusicSong *song in songs) {
            NSArray *identity = SGLocalMusicFileIdentity([folder URLByAppendingPathComponent:song.name]);
            if (![names containsObject:song.name] || ![identity isEqual:song.fileIdentity] ||
                ![SGLocalMusicVerifiedURI(song.name, identity) isEqual:song.playbackURI]) { valid = NO; break; }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!valid || !SGLocalMusicPlaybackAvailable()) { [request finish:unavailable()]; return; }
            NSMutableArray *tracks = [NSMutableArray array];
            for (SGLocalMusicSong *song in songs) {
                SPTPlayerTrack *track = [[NSClassFromString(@"SPTPlayerTrack") alloc]
                    initWithURI:[NSURL URLWithString:song.playbackURI] albumURI:nil artistURI:nil andUID:nil];
                if (!track) { [request finish:unavailable()]; return; }
                [tracks addObject:track];
            }
            __weak SGLocalMusicCommand *weakRequest = request;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kCommandTimeoutSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [weakRequest finish:unavailable()];
            });
            submit(request, tracks);
        });
    });
}
void SGLocalMusicPlay(NSArray<SGLocalMusicSong *> *songs, BOOL shuffle, void (^done)(NSError *)) {
    prepare(songs, done, ^(SGLocalMusicCommand *request, NSArray<SPTPlayerTrack *> *tracks) {
        SPTPlayerContext *context = [NSClassFromString(@"SPTPlayerContext") contextWithTracks:tracks];
        context.URI = [NSURL URLWithString:@"spotify:local-files"];
        SPTPlayerOptionOverrides *overrides = [NSClassFromString(@"SPTPlayerOptionOverrides") new];
        overrides.shufflingContext = @(shuffle);
        SPTPlayOptions *options = [NSClassFromString(@"SPTPlayOptions") new];
        options.playerOptionsOverride = overrides;
        NSUInteger start = shuffle ? arc4random_uniform((uint32_t)tracks.count) : 0;
        options.skipTo = [[NSClassFromString(@"SPTSkipToTrack") alloc] initWithTrackURI:tracks[start].URI];
        SGLog(@"local music: %@ %lu songs", shuffle ? @"shuffle" : @"play", (unsigned long)tracks.count);
        [request observe:[(id<SGLocalMusicPlayer>)SGPlayer() playContext:context options:options]];
    });
}
void SGLocalMusicQueue(SGLocalMusicSong *song, BOOL next, void (^done)(NSError *)) {
    prepare(song ? @[song] : @[], done, ^(SGLocalMusicCommand *request, NSArray<SPTPlayerTrack *> *tracks) {
        request.wrapper = [[NSClassFromString(@"SPTPlayerQueueWrapperImpl") alloc] initWithPlayer:SGPlayer()];
        SGLog(@"local music: %@ %@", next ? @"play next" : @"add to queue", song.playbackURI);
        [request observe:next ? [request.wrapper queueTrackPlayNext:tracks.firstObject]
            : [request.wrapper queueMultipleTracks:tracks loggingParams:nil]];
    });
}
__attribute__((constructor)) static void localMusicPlayback(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        static __unused SGLocalMusicIdentityObserver *observer;
        if (!supported()) return;
        sg_observationAvailable = SGLocalMusicObservationContract(NSClassFromString(@"SPTPlayerState"), NSClassFromString(@"SPTPlayerTrack"));
        if (sg_observationAvailable) observer = [SGLocalMusicIdentityObserver new];
        else SGLog(@"local music: missing player observation selectors; browse only");
    });
}
