// A local file's edit laid over what Spotify read from it (LocalFiles.h).
//
// -[SPTPlayerTrack metadata] is the one place: trackTitle, artistName, albumTitle and imageURL each read
// self.metadata and take title, artist_name, album_title and image_url from it (their code in the
// binary, through NSDictionary's spt_metadata_* in IDZKAdditions), and the player, the now playing bar
// and the system's now playing info are built from the player's track. So the names go in there, and
// the cover as an image address of the kind Spotify gives a local file, spotify:localfileimage:<path>.
//
// Spotify's loader hands such an address (three parts, no ipod-library in it) to
// SPTLocalAVAssetImageLoaderRequest, whose -loadLocalFileImage reads the cover out of the file at the
// path with AVAsset and passes its bytes to -dispatchSuccess:, which gives them to the delegate's
// imageLoaderRequest:didLoadImageData:. The request caches nothing (preventInMemoryCaching and
// preventPersistentCaching answer YES), so a stored cover is read from disk each time and passed on
// the same way. The system's now playing artwork is added too, in case Spotify fetches it apart.
#import <MediaPlayer/MediaPlayer.h>
#import <mach/mach.h>
#import <ptrauth.h>
#import "Core/SGCore.h"
#import "Headers/SPTLocalAVAssetImageLoaderRequest.h"
#import "Headers/SPTPlayer.h"
#import "Shared/Player/NowPlayingExtras.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/WireGuard/SGWGABI.h"
#import "LocalFiles.h"

static NSURL *(*sg_coverURL)(id, SEL);

// Metadata is rewritten before a loader instance exists. A typed property alone cannot
// prove what a custom getter returns. Both admitted arm64 getters are exactly a load of
// the NSURL field into the return register followed by ret. Don't invoke a test getter
// on an uninitialized request, or publish replacement addresses for an unknown accessor.
static BOOL directURLGetter(IMP getter, Ivar field) {
    ptrdiff_t offset = ivar_getOffset(field);
    if (offset < 0 || offset % 8 || offset / 8 > 0xfff) return NO;
    uint32_t code[2];
    vm_size_t copied = 0;
    vm_address_t imp = (vm_address_t)ptrauth_strip(getter, ptrauth_key_function_pointer);
    if (vm_read_overwrite(mach_task_self(), imp, sizeof(code), (vm_address_t)code, &copied) != KERN_SUCCESS ||
        copied != sizeof(code)) return NO;
    const uint32_t loadX0FromX0 = 0xf9400000, ret = 0xd65f03c0;
    return code[0] == (loadX0FromX0 | ((uint32_t)(offset / 8) << 10)) && code[1] == ret;
}

// Called for every track in every list many times a second: one prefix check for any other track.
static NSDictionary *withEdit(NSDictionary *metadata, NSString *uri) {
    if (metadata && ![metadata isKindOfClass:NSDictionary.class]) return metadata;
    NSDictionary *edit = SGLocalFileEditFor(uri);
    if (!edit) return metadata;
    NSMutableDictionary *edited = metadata ? [metadata mutableCopy] : [NSMutableDictionary dictionary];
    if ([edit[@"title"] length]) edited[@"title"] = edit[@"title"];
    if ([edit[@"artist"] length]) edited[@"artist_name"] = edit[@"artist"];
    if ([edit[@"album"] length]) edited[@"album_title"] = edit[@"album"];
    NSString *cover = sg_coverURL ? SGLocalFileCoverURL(SGLocalFileCoverPath(edit)) : nil;
    // Every size, since a reader may take any of them: Spotify's loader, and the redesign's artwork bridge
    // (Redesigned/Kit/SGRBridges.x), which reads the stored file itself.
    if (cover) {
        for (NSString *field in @[@"image_small_url", @"image_url", @"image_large_url", @"image_xlarge_url"]) edited[field] = cover;
    }
    return edited;
}

#pragma mark - the system's now playing artwork

@interface SGLocalFileNowPlaying : NSObject <SGPlayerStateObserver>
@end

@implementation SGLocalFileNowPlaying {
    NSString *_track;
    NSUInteger _request;
}

// Spotify's info is matched by its title, which is the edited one when Spotify built it from the
// player's track and the file's own when it did not, so the artwork rides on either.
- (void)show:(SPTPlayerState *)state {
    NSString *uri = SGURIString(state.track.URI);
    NSUInteger request = ++_request;
    SGNowPlayingSetExtras(@"localFiles", nil, nil);
    SGNowPlayingSetExtras(@"localFiles.tags", nil, nil);
    if (!SGLocalFileCoverPath(SGLocalFileEditFor(uri))) return;
    SGLocalFileLoadCover(uri, ^(UIImage *cover) {
        if (!cover || request != self->_request || ![uri isEqualToString:self->_track]) return;
        // This synchronous system callback only returns the already-decoded image; it does no IO.
        MPMediaItemArtwork *artwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:cover.size requestHandler:^UIImage *(CGSize size) {
            return cover;
        }];
        SGNowPlayingSetExtras(@"localFiles", @{MPMediaItemPropertyArtwork: artwork}, SGLocalFileInfo(uri)[@"title"]);
        SGNowPlayingSetExtras(@"localFiles.tags", @{MPMediaItemPropertyArtwork: artwork}, SGLocalFileTags(uri)[@"title"]);
    });
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSString *track = SGURIString(state.track.URI);
    if (track == _track || [track isEqualToString:_track]) return;
    _track = track;
    [self show:state];
}

- (void)editsChanged:(NSNotification *)note {
    if ([note.object isEqual:_track]) [self show:SGPlayerState()];
}

@end

#pragma mark - hooks

%group SGLocalTrackHooks
%hook SPTPlayerTrack
- (NSDictionary *)metadata {
    NSDictionary *metadata = %orig;
    NSString *uri = SGURIString(self.URI);
    return SGLocalFileIs(uri) ? withEdit(metadata, uri) : metadata;
}
%end
%end

%group SGLocalCoverHooks
%hook SPTLocalAVAssetImageLoaderRequest
- (void)loadLocalFileImage {
    // The admitted getter reads the base request's NSURL slot, also on inherited requests.
    NSURL *url = sg_coverURL(self, @selector(URL));
    NSString *path = [url isKindOfClass:NSURL.class] ? SGLocalFileCoverInURL(url.absoluteString) : nil;
    if (!path) {
        %orig;
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSData *data = [NSData dataWithContentsOfFile:path];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (data) [self dispatchSuccess:data];
            else {
                SGLog(@"local files: the cover %@ is gone, the track shows none", path.lastPathComponent);
                %orig;
            }
        });
    });
}
%end
%end

%ctor {
    Class loader = NSClassFromString(@"SPTLocalAVAssetImageLoaderRequest");
    // Both supported getters load _URL directly. The method ABI only says '@'; check
    // the declared result and its backing storage before publishing any replacement URL.
    objc_property_t property = class_getProperty(loader, "URL");
    char *result = property ? property_copyAttributeValue(property, "T") : NULL;
    char *storage = property ? property_copyAttributeValue(property, "V") : NULL;
    Ivar field = storage ? class_getInstanceVariable(loader, storage) : NULL;
    const char *type = field ? ivar_getTypeEncoding(field) : NULL;
    BOOL urlResult = result && !strcmp(result, "@\"NSURL\"") && type && !strcmp(type, result);
    free(storage);
    free(result);
    Method getter = class_getInstanceMethod(loader, @selector(URL));
    IMP readURL = getter ? method_getImplementation(getter) : NULL;
    if (urlResult && SGWGMethodMatches(getter, "@", @[]) && directURLGetter(readURL, field) &&
        SGWGMethodMatches(class_getInstanceMethod(loader, @selector(loadLocalFileImage)), "v", @[]) &&
        SGWGMethodMatches(class_getInstanceMethod(loader, @selector(dispatchSuccess:)), "v", @[@"@"])) {
        sg_coverURL = (void *)readURL;
        %init(SGLocalCoverHooks);
    } else {
        SGLog(@"local files: cover loader API unavailable");
    }
    Class track = NSClassFromString(@"SPTPlayerTrack");
    if (!SGWGMethodMatches(class_getInstanceMethod(track, @selector(metadata)), "@", @[]) ||
        !SGWGMethodMatches(class_getInstanceMethod(track, @selector(URI)), "@", @[])) {
        SGLog(@"local files: track metadata API unavailable");
        return;
    }
    %init(SGLocalTrackHooks);
    static SGLocalFileNowPlaying *nowPlaying;
    nowPlaying = [SGLocalFileNowPlaying new];
    SGAddPlayerStateObserver(nowPlaying);
    [NSNotificationCenter.defaultCenter addObserver:nowPlaying selector:@selector(editsChanged:) name:SGLocalFileEditsDidChangeNotification object:nil];
    SGRequireClasses(@[@"SPTPlayerTrack", @"SPTLocalAVAssetImageLoaderRequest"]);
}
