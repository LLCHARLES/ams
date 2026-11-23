// SGMotionFollower (AnimatedArtwork.h): one track's walk of the sources at a time, for the lock screen
// (LockScreenMotion.x) and the redesign's player (Redesigned/Player/PlayerMotion.x) alike.
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Core/SGOptionalWork.h"
#import "Shared/Player/PlayerState.h"
#import "AnimatedArtwork.h"
#import "SGMotionClip.h"

@interface SGMotionFollower () <SGPlayerStateObserver>
@end

// artistName can be only the lead. Use the structured credits when Spotify supplied them.
static NSString *songArtists(SPTPlayerTrack *track, NSDictionary *metadata) {
    NSString *lead = metadata[@"artist_name"];
    if (![lead isKindOfClass:NSString.class] || !lead.length || !metadata[@"artist_name:1"]) return track.artistName;
    NSMutableArray *names = [NSMutableArray arrayWithObject:lead];
    for (NSUInteger i = 1; ; i++) {
        NSString *name = metadata[[NSString stringWithFormat:@"artist_name:%lu", (unsigned long)i]];
        if (![name isKindOfClass:NSString.class] || !name.length) break;
        [names addObject:name];
    }
    return [names componentsJoinedByString:@", "];
}

@implementation SGMotionFollower {
    BOOL (^_begin)(NSString *, SPTPlayerState *);
    void (^_found)(NSString *, NSURL *);
    NSString *_track;    // the URI walked last
    BOOL _walked;        // whether `begin` let it be walked
    NSURL *_canvas;      // the Canvas its metadata named as the walk began, nil for none
    NSString *_source;   // where the clip found came from, nil for none or not found yet
    NSUInteger _walk;    // counts the walks, so an overtaken one is told from the newest
    NSString *_ahead;    // the next track whose clip was fetched ahead
    SGMotionTicket *_currentTicket, *_aheadTicket;
}

- (instancetype)initWithBegin:(BOOL (^)(NSString *, SPTPlayerState *))begin found:(void (^)(NSString *, NSURL *))found {
    if (!(self = [super init])) return nil;
    _begin = [begin copy];
    _found = [found copy];
    SGAddPlayerStateObserver(self);
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(defaultsChanged:) name:NSUserDefaultsDidChangeNotification object:nil];
    return self;
}

- (void)dealloc {
    [_currentTicket cancel];
    [_aheadTicket cancel];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)defaultsChanged:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{ [self fetchAhead]; });
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    [self playerStateDidReport:state];
    [self fetchAhead];
}

- (void)playerUpNextDidChange:(SPTPlayerState *)state {
    [self fetchAhead];
}

- (void)playerStateDidReport:(SPTPlayerState *)state {
    NSString *uri = SGURIString(state.track.URI);
    if (!uri.length) {
        [_currentTicket cancel];
        _currentTicket = nil;
        _track = nil;
        _walked = NO;
        _walk++;
        [self fetchAhead];
        return;
    }
    NSURL *canvas = SGMotionCanvasIn(state.track.metadata);
    if ([uri isEqualToString:_track]) {
        if (!_walked || _canvas || !canvas || !SGMotionCanvasOutranks(SGMotionSourceOrder(), _source)) return;
        SGLog(@"motion: the Canvas of %@ came after the track, asked again", uri);
    }
    [self walk:state uri:uri canvas:canvas];
}

- (void)walk:(SPTPlayerState *)state uri:(NSString *)uri canvas:(NSURL *)canvas {
    [_currentTicket cancel];
    _currentTicket = nil;
    _track = uri;
    _canvas = canvas;
    _source = nil;
    NSUInteger walk = ++_walk;
    _walked = _begin(uri, state);
    if (!_walked) { [self fetchAhead]; return; }
    NSDictionary *metadata = [state.track.metadata isKindOfClass:NSDictionary.class] ? state.track.metadata : nil;
    __weak SGMotionFollower *weakSelf = self;
    _currentTicket = SGMotionRequestAlbumSongClip(uri, canvas, songArtists(state.track, metadata), metadata[@"album_title"], state.track.trackTitle, metadata[@"album_uri"], SGMotionPixels(), ^(NSURL *file, NSString *source) {
        SGMotionFollower *follower = weakSelf;
        if (!follower || walk != follower->_walk) return;
        follower->_source = source;
        follower->_found(uri, file);
        [follower fetchAhead];
    });
}

// The next track's clip, fetched into the store once, so a skip finds it there.
- (void)fetchAhead {
    SPTPlayerState *state = SGPlayerState();
    SPTPlayerTrack *track = SGPlayerUpNextIn(state);
    NSString *uri = SGURIString(track.URI);
    BOOL allowed = _walked && uri.length && SGOptionalWorkMayRun(NO);
    if (allowed && [uri isEqualToString:_ahead]) return;
    [_aheadTicket cancel];
    _aheadTicket = nil;
    _ahead = nil;
    if (!allowed) return;
    _ahead = uri;
    NSDictionary *metadata = [track.metadata isKindOfClass:NSDictionary.class] ? track.metadata : nil;
    _aheadTicket = SGMotionRequestAlbumSongClip(uri, SGMotionCanvasIn(metadata), songArtists(track, metadata), metadata[@"album_title"], track.trackTitle, metadata[@"album_uri"], SGMotionPixels(),
                    ^(NSURL *file, NSString *source) {
        SGLog(@"motion: the next track's clip fetched ahead: %@", file ? source : @"none");
    });
}

- (void)restart {
    [_currentTicket cancel];
    [_aheadTicket cancel];
    _currentTicket = _aheadTicket = nil;
    _ahead = nil;
    _track = nil;
    _walked = NO;
    _walk++;
    SPTPlayerState *state = SGPlayerState();
    if (state) [self playerStateDidChange:state];
}

@end
