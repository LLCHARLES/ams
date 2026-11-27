#import <UIKit/UIKit.h>
#import "../harness-fail.h"

// Exercise the real metadata hook, including its ctor's admission of the paired loader.
@interface SPTLocalAVAssetImageLoaderRequest : NSObject
@property (nonatomic, strong) NSURL *URL;
@end
@implementation SPTLocalAVAssetImageLoaderRequest
@synthesize URL = _URL;
- (NSURL *)URL { return (id)@"not a URL"; } // Even the declared property type can be stale.
- (void)loadLocalFileImage {}
- (void)dispatchSuccess:(NSData *)data {}
@end

static id original;
@interface SPTPlayerTrack : NSObject @end
@implementation SPTPlayerTrack
- (id)URI { return @"spotify:local:a:b:c:1"; }
- (id)metadata { return original; }
@end
@interface ChangedMetadata : NSObject @end
@implementation ChangedMetadata
- (id)mutableCopyWithZone:(NSZone *)zone { return [NSMutableDictionary dictionary]; }
@end

BOOL SGLocalFileIs(NSString *uri) { return YES; }
NSString *SGURIString(id uri) { return uri; }
NSDictionary *SGLocalFileEditFor(NSString *uri) { return @{@"title": @"edited", @"cover": @"cover.jpg"}; }
NSString *SGLocalFileCoverPath(id edit) { return @"cover.jpg"; }
NSString *SGLocalFileCoverURL(id path) { return @"replacement address"; }
NSString *SGLocalFileCoverInURL(id url) { return nil; }
NSDictionary *SGLocalFileInfo(id uri) { return nil; }
NSDictionary *SGLocalFileTags(id uri) { return nil; }
void SGLocalFileLoadCover(id uri, void (^completion)(UIImage *)) {}
void SGAddPlayerStateObserver(id observer) {}
id SGPlayerState(void) { return nil; }
void SGNowPlayingSetExtras(id owner, id extras, id title) {}
void SGRequireClasses(NSArray *names) {}
NSNotificationName const SGLocalFileEditsDidChangeNotification = @"harness-edits";

int main(void) {
    @autoreleasepool {
        SPTPlayerTrack *track = [SPTPlayerTrack new];
        original = [ChangedMetadata new];
        HARNESS_CHECK(track.metadata == original);
        original = @{@"image_url": @"original"};
        NSDictionary *metadata = track.metadata;
        HARNESS_CHECK([metadata isEqual:(@{@"title": @"edited", @"image_url": @"original"})]);
        puts("[harness] PASS malformed metadata and incompatible URL preserve original cover");
    }
    return 0;
}
