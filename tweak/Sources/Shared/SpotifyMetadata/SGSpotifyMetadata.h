// Spotify's existing spclient transport, shared by album counts and Music Haptics.
#import <Foundation/Foundation.h>
#import "Shared/AdBlock/Protobuf.h"

typedef void (^SGSpotifyMetadataReply)(NSData *data, NSInteger status, NSError *error);
static const NSUInteger SGSpotifyMetadataMaxResponseBytes = 2 * 1024 * 1024;
// A nil body is an album JSON GET; a body is an extended-metadata protobuf POST.
// Only the two metadata endpoints are accepted. Transfers use an ephemeral session, refuse
// redirects and stop at 2 MiB. Completion is asynchronous; valid transfers finish on the delegate queue.
// The returned action cancels this transfer, including a pending wait for headers.
dispatch_block_t SGSpotifyMetadataRequest(NSString *path, NSData *body, SGSpotifyMetadataReply done);
dispatch_block_t SGSpotifyMetadataRequestAllowConstrained(NSString *path, NSData *body, BOOL allowConstrained,
                                                          SGSpotifyMetadataReply done);

// The common BatchedEntityRequest wire shape. Inline so Foundation-only consumers of the
// codec (including the existing haptics harness) need not link the authenticated transport.
static inline NSData *SGSpotifyExtensionRequest(NSArray<NSString *> *uris, NSArray<NSNumber *> *kinds) {
    NSMutableArray *entities = [NSMutableArray array];
    for (NSString *uri in uris) {
        NSMutableArray *entity = [NSMutableArray arrayWithObject:SGPBString(1, uri)];
        for (NSNumber *kind in kinds) {
            [entity addObject:SGPBBytes(2, SGPBSerialize(@[SGPBVarint(1, kind.unsignedLongLongValue)]))];
        }
        [entities addObject:SGPBBytes(2, SGPBSerialize(entity))];
    }
    return SGPBSerialize(entities);
}
#define SGSpotifyExtendedMetadataPath @"/extended-metadata/v0/extended-metadata"
