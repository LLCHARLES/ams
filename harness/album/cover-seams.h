// External boundaries controlled by cover-hero-check.m; injected into generated AlbumHeader.m only.
#import <UIKit/UIKit.h>
@class AVPlayer, AVPlayerLayer, SGRCoverReading;

void SGRAlbumTestAlbumCover(NSString *artist, NSString *album, CGFloat pixels, void (^done)(NSURL *));
void SGRAlbumTestPageCover(NSString *artist, NSString *album, NSString *uri, CGFloat pixels, void (^done)(NSURL *, BOOL));
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#if !SGR_COVER_BASELINE
void SGRAlbumTestIdentifierCover(NSString *uri, NSString *artist, NSString *album, CGFloat pixels, void (^done)(NSURL *, SGMotionIdentifierOutcome));
#endif
void SGRAlbumTestStillEditionCover(NSString *uri, NSString *artist, NSString *album, CGFloat pixels, void (^done)(NSURL *));
void SGRAlbumTestRowMatcher(NSString *artist, NSString *album, NSString *uri, CGFloat pixels, void (^ready)(BOOL (^)(NSString *, NSString *)), void (^done)(NSURL *));
void SGRAlbumTestPoster(NSURL *file, void (^done)(UIImage *));
BOOL SGRAlbumTestStillRead(UIImage *image, void (^done)(SGRCoverReading *));
AVPlayerLayer *SGRAlbumTestPlayerLayer(AVPlayer *player);
Class SGRAlbumTestClipClass(void);
NSCache *SGRAlbumTestRenderCache(void);
