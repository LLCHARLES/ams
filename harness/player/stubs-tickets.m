// MotionSources.m's cancellable walk, for sources whose animated artwork store hands out tickets (SGMotionTicket.m);
// build.sh compiles this only where that file exists. Its delayed lookup uses the production ticket's cancellation
// contract; a cancelled consumer is not called when the shared lookup finishes.
#import "Shared/AnimatedArtwork/SGMotionTicket.h"
#import "Shared/SpotifyMetadata/SGSpotifyMetadata.h"
#import "../motion/no-recording-lookup.h"

dispatch_block_t SGSpotifyMetadataRequestAllowConstrained(NSString *path, NSData *body, BOOL allow, SGSpotifyMetadataReply done) {
    HARNESS_FAIL(@"unexpected Spotify album metadata request: %@", path);
}

static NSMutableArray<SGMotionTicket *> *sg_backgroundTickets;
NSArray<SGMotionTicket *> *SGRHarnessMotionTickets(void) { return sg_backgroundTickets ?: @[]; }

SGMotionTicket *SGMotionRequestClip(NSString *uri, NSURL *canvas, NSString *artist, NSString *album, CGFloat pixels,
                                   void (^done)(NSURL *file, NSString *source)) {
    return SGMotionRequestSongClip(uri, canvas, artist, album, nil, pixels, done);
}
SGMotionTicket *SGMotionRequestSongClip(NSString *uri, NSURL *canvas, NSString *artist, NSString *album, NSString *song, CGFloat pixels,
                                       void (^done)(NSURL *file, NSString *source)) {
    SGMotionTicket *ticket = [SGMotionTicket new];
    if ([NSProcessInfo.processInfo.environment[@"HARNESS_SCENARIO"] isEqual:@"background"]) {
        if (!sg_backgroundTickets) sg_backgroundTickets = [NSMutableArray array];
        [sg_backgroundTickets addObject:ticket];
        return ticket;
    }
    SGMotionClipFor(uri, canvas, artist, album, pixels, ^(NSURL *file, NSString *source) {
        if (!ticket.cancelled) done(file, source);
    });
    return ticket;
}

SGMotionTicket *SGMotionRequestAlbumSongClip(NSString *uri, NSURL *canvas, NSString *artist, NSString *album, NSString *song,
                                           NSString *albumURI, CGFloat pixels, void (^done)(NSURL *, NSString *)) {
    return SGMotionRequestSongClip(uri, canvas, artist, album, song, pixels, done);
}
