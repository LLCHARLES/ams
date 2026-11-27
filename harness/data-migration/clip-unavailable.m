#define SGLyricsClipWriteWithLayout fixtureWriteWithLayout
#import "../now-playing/artwork.m"
#undef SGLyricsClipWriteWithLayout
#import "Core/SGDataRoot.h"

// The now-playing drivers define these around their own copies of the generated sources; this binary links
// the plain generated files and never runs the artwork checks that read them.
NSUInteger harnessArtworkHashes;
BOOL harnessCoverRevisions(UIImage *a, UIImage *b) { return NO; }

// Fail normally rather than feeding nil to a real encoder and raising a crash dialog.
BOOL SGLyricsClipWriteWithLayout(NSURL *file, CGImageRef backdrop, CGImageRef cover, NSString *previous, NSString *line,
                                 NSString *translation, NSString *next, CGSize size, SGLyricsClipStyle style,
                                 SGLyricsClipLayout layout, BOOL (^current)(void)) {
    check(NO, @"unavailable clip destination reached the encoder");
    return NO;
}

void checkUnavailableClip(void) {
    NSURL *invalid = [cacheRoot URLByAppendingPathComponent:@"Retrine"];
    check([NSData.data writeToURL:invalid atomically:YES], @"install invalid cache root");
    check(SGDataRoot(NSCachesDirectory) == nil, @"cache root is unavailable");
    supported = @[MPNowPlayingInfoProperty3x4AnimatedArtwork];
    nativeInfo(nil);
    track(@"no-clip-destination", SGLockArtworkLyrics, nil, @[lineOf(@"First", 0, 10000)]);
    check(await(^BOOL { return artwork() != nil; }), @"lyric artwork is offered");
    check(video(artwork()) == nil, @"video request completes without a file");
    choose(SGLockArtworkOff);
    [NSFileManager.defaultManager removeItemAtURL:cacheRoot error:nil];
}
