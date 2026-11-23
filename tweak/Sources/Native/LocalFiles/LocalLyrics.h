// Spotify turns its own lyrics off for local files before it asks its lyrics service.
// The footer's file-lyrics button and viewer share one current-track snapshot.
//
//     LocalLyricsButton.x   the button on the footer, and has_lyrics for a linked local file
//     LocalLyricsPage.m     the page: the lines on black, following the song
#import <UIKit/UIKit.h>

// The page for whatever plays, full screen.
UIViewController *SGLocalLyricsPage(void);
@class SGLyricsResult;
SGLyricsResult *SGNativeCurrentFileSheet(BOOL *loading);
extern NSNotificationName const SGNativeFileSheetDidChange;
