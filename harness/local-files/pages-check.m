#import "Shared/LocalFiles/LocalMusicIndex.h"
#import "Shared/LocalFiles/LocalMusicPlayback.h"
#import "../harness-fail.h"

static SGLocalMusicSong *song(NSString *name, NSDictionary *tags, NSDictionary *edit) {
    return [[SGLocalMusicSong alloc] initWithName:name metadataURI:nil tags:tags edit:edit artwork:nil];
}

@interface ObservationStateWithoutLoading : NSObject
@property (nonatomic, strong) id track, playbackId;
@property (nonatomic) BOOL isPlaying;
@property (nonatomic) double position;
@end
@implementation ObservationStateWithoutLoading
@end
@interface ObservationState : ObservationStateWithoutLoading
@property (nonatomic) BOOL isLoading;
@end
@implementation ObservationState
@end
@interface ObservationTrack : NSObject
@property (nonatomic, strong) id URI, metadata;
@end
@implementation ObservationTrack
@end

int main(void) {
    @autoreleasepool {
        SGLocalMusicSong *a = song(@"Live/A.flac", @{@"title": @"A", @"artist": @"Guest", @"albumArtist": @"Ensemble", @"album": @"Night", @"disc": @2, @"track": @1}, @{});
        SGLocalMusicSong *b = song(@"Live/B.m4a", @{@"title": @"B", @"artist": @"Ensemble", @"album": @"Night", @"disc": @1, @"track": @2}, @{});
        SGLocalMusicSong *c = song(@"C.mp3", @{@"title": @"C", @"artist": @"Ensemble", @"album": @"Night", @"disc": @1, @"track": @1}, @{});
        SGLocalMusicSong *d = song(@"Live/D.flac", @{@"title": @"D", @"artist": @"Ensemble", @"album": @"Night", @"disc": @1, @"track": @2}, @{});
        SGLocalMusicSong *missing = song(@"unlabelled.flac", @{}, @{});
        SGLocalMusicSong *other = song(@"Other.mp3", @{@"artist": @"Other", @"album": @"Night"}, @{});
        SGLocalMusicIndex *index = [[SGLocalMusicIndex alloc] initWithSongs:@[a, b, c, d, missing, other]];
        HARNESS_CHECK([index artistNamed:@"Ensemble"].songs.count == 4);
        HARNESS_CHECK(index.albums.count == 3);
        SGLocalMusicGroup *album = [index albumsForArtist:[index artistNamed:@"Ensemble"]].firstObject;
        HARNESS_CHECK(([[album.songs valueForKey:@"title"] isEqual:@[@"C", @"B", @"D", @"A"]]));
        HARNESS_CHECK(index.artists.firstObject.name.length == 0 && index.artists.firstObject.songs.count == 1);
        HARNESS_CHECK(index.albums.firstObject.name.length == 0);
        HARNESS_CHECK(([[index.folders valueForKey:@"name"] isEqual:@[@"", @"Live"]]));
        HARNESS_CHECK(index.folders.lastObject.songs.count == 3);
        HARNESS_CHECK([[index artistNamed:@"eNsEmBlE"].name isEqual:@"Ensemble"]);
        HARNESS_CHECK([index artistNamed:@"Absent"] == nil && [index artistNamed:@""] == nil);
        SGLocalMusicSong *edited = song(@"edited.mp3", @{@"title": @"Original", @"album": @"Old", @"artist": @"Old Artist"},
            @{@"title": @"My Title", @"artist": @"My Artist", @"album": @"My Album"});
        HARNESS_CHECK([edited.title isEqual:@"My Title"] && [edited.artist isEqual:@"My Artist"] && [edited.album isEqual:@"My Album"]);
        HARNESS_CHECK(SGLocalMusicSupportsVersion(@"9.1.90"));
        HARNESS_CHECK(!SGLocalMusicSupportsVersion(@"9.1.78") && !SGLocalMusicSupportsVersion(@"9.1.88"));
        NSError *free = [NSError errorWithDomain:@"com.spotify.SPTPlayer" code:101
            userInfo:@{@"kSPTPlayerErrorDisallowReasonsKey": [NSSet setWithObject:@"mft_disallow"]}];
        HARNESS_CHECK([SGLocalMusicFailureMessage(free) isEqual:@"Spotify Free limits playing chosen songs. Spoof Premium in Retrine Settings lifts this limit."]);
        NSError *conflict = [NSError errorWithDomain:@"com.spotify.SPTPlayer" code:100 userInfo:nil];
        HARNESS_CHECK([SGLocalMusicFailureMessage(conflict) isEqual:@"Spotify could not play this."]);
        SGLocalMusicObservations *observations = [SGLocalMusicObservations new];
        NSArray *originalIdentity = @[@1, @10, @100, @42, @0, @42, @0];
        NSArray *replacementIdentity = @[@1, @11, @100, @42, @0, @42, @0];
        NSDictionary *pending = [observations captureURI:@"spotify:local:::same:180" path:@"/same.m4a" playbackID:@"first"
            readIdentity:^{ return originalIdentity; }];
        HARNESS_CHECK([observations verifiedObservation:pending currentIdentity:replacementIdentity] == nil);
        HARNESS_CHECK([observations captureURI:@"spotify:local:::same:180" path:@"/same.m4a" playbackID:@"first"
            readIdentity:^{ HARNESS_FAIL(@"Position report reread a replaced file"); return replacementIdentity; }] == nil);
        NSDictionary *replayed = [observations captureURI:@"spotify:local:::same:180" path:@"/same.m4a" playbackID:@"second"
            readIdentity:^{ return replacementIdentity; }];
        HARNESS_CHECK(([[observations verifiedObservation:replayed currentIdentity:replacementIdentity]
            isEqual:@{@"uri": @"spotify:local:::same:180", @"identity": @[@1, @11, @100, @42, @0, @42, @0]}]));
        HARNESS_CHECK(!SGLocalMusicObservationContract(ObservationStateWithoutLoading.class, ObservationTrack.class));
        HARNESS_CHECK(!SGLocalMusicObservationContract(ObservationState.class, NSObject.class));
        HARNESS_CHECK(SGLocalMusicObservationContract(ObservationState.class, ObservationTrack.class));
        SGLocalMusicFileCache *files = [SGLocalMusicFileCache new];
        __block NSArray *identity = @[@1, @10, @100, @42, @0, @42, @0];
        [files entryForName:@"same.m4a" identity:^{ return identity; } read:^{ return @{@"title": @"Old"}; }];
        identity = @[@1, @11, @100, @42, @0, @42, @0];
        NSDictionary *fresh = [files entryForName:@"same.m4a" identity:^{ return identity; } read:^{ return @{@"title": @"Fresh"}; }];
        HARNESS_CHECK([fresh[@"metadata"][@"title"] isEqual:@"Fresh"]);
        identity = @[@1, @12, @100, @42, @0, @42, @0];
        HARNESS_CHECK(([files entryForName:@"same.m4a" identity:^{ return identity; } read:^{
            identity = @[@1, @13, @100, @42, @0, @42, @0];
            return @{@"title": @"Superseded"};
        }] == nil));
        SGLocalMusicArtworkReference *first = [[SGLocalMusicArtworkReference alloc] initWithURL:[NSURL fileURLWithPath:@"/one"]
            identity:@[@1] format:@"fixture" item:0 edited:NO];
        SGLocalMusicArtworkReference *second = [[SGLocalMusicArtworkReference alloc] initWithURL:[NSURL fileURLWithPath:@"/two"]
            identity:@[@2] format:@"fixture" item:0 edited:NO];
        SGLocalMusicSong *one = [[SGLocalMusicSong alloc] initWithName:@"one" metadataURI:nil tags:@{@"artist": @"Artist", @"album": @"Album"} edit:@{} artwork:first];
        SGLocalMusicSong *two = [[SGLocalMusicSong alloc] initWithName:@"two" metadataURI:nil tags:@{@"artist": @"Artist", @"album": @"Album"} edit:@{} artwork:second];
        __unused SGLocalMusicIndex *sharedAlbum = [[SGLocalMusicIndex alloc] initWithSongs:@[one, two]];
        UIImage *red = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(2, 2)] imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [UIColor.redColor setFill]; UIRectFill(CGRectMake(0, 0, 2, 2));
        }];
        SGLocalMusicArtworkCache *artwork = [SGLocalMusicArtworkCache new];
        [artwork imageForReference:one.artwork pixelSize:2 decode:^{ return red; }];
        HARNESS_CHECK([artwork imageForReference:two.artwork pixelSize:2 decode:^{ return (UIImage *)nil; }] == red);
        NSLog(@"[harness] PASS local pages: grouping, ordering, edit overlay, artist lookup, build gating and Spotify refusal messages");
        NSLog(@"[harness] PASS reimport identity/pending replacement and shared album artwork cache entry");
        NSLog(@"[harness] PASS stale playback observation rejection, fresh-load verification and missing-selector gating");
    }
    return 0;
}
