#import <Foundation/Foundation.h>
@class SGLyricsResult;
// Worker only. A regular local file, never a stream or URL request.
SGLyricsResult *SGEmbeddedLyrics(NSString *path);
