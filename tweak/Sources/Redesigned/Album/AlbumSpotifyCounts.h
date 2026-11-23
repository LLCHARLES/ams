#import <Foundation/Foundation.h>
#import "Shared/SpotifyMetadata/SGSpotifyMetadata.h"
#import "Shared/SpotifyMetadata/SGSpotifyAlbumIdentity.h"

// Identity/codec functions are Foundation-only, exercised with independent wire fixtures.
NSArray<NSString *> *SGRAlbumMetadataTracks(NSData *json);
@interface SGRAlbumTrackIndex : NSObject
+ (instancetype)fromMetadata:(NSData *)json;
@property (nonatomic, copy, readonly) NSArray<NSString *> *tracks;
- (NSNumber *)numberForURI:(NSString *)uri title:(NSString *)title;
@end
NSDictionary<NSString *, NSNumber *> *SGRAlbumCountsInReply(NSData *data, NSArray<NSString *> *tracks);
NSString *SGRAlbumTrackURIFromMenuIdentifier(NSString *identifier);

typedef void (^SGRAlbumCountsTransport)(NSString *path, NSData *body, SGSpotifyMetadataReply done);
typedef void (^SGRAlbumCountsReply)(NSDictionary<NSString *, NSNumber *> *counts);

// One JSON GET and one batched protobuf POST per miss, never a per-track request or automatic retry.
// At most 500 distinct tracks/album, 64 albums and 2 MiB on disk. Success expires in 24 hours;
// failure is unavailable for five minutes. Disk and parsing run on the private serial utility queue.
// Call on main; replies arrive on main. Concurrent requests for an album are coalesced.
@interface SGRAlbumCountsStore : NSObject
- (instancetype)initWithCacheURL:(NSURL *)url transport:(SGRAlbumCountsTransport)transport;
- (void)loadAlbum:(NSString *)albumURI completion:(SGRAlbumCountsReply)done;
- (void)loadTrackIndex:(NSString *)uri completion:(void (^)(SGRAlbumTrackIndex *index))done;
@end
SGRAlbumCountsStore *SGRAlbumSpotifyCountsStore(void);

// A page's identity, not its displayed title, owns the result. A new identity invalidates an old reply.
@interface SGRAlbumCountPage : NSObject
@property (nonatomic, copy, readonly) NSString *albumURI;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSNumber *> *counts;
- (instancetype)initWithStore:(SGRAlbumCountsStore *)store;
- (void)followAlbum:(NSString *)albumURI changed:(dispatch_block_t)changed;
@end
