#import <Foundation/Foundation.h>

#define SGKeyPixieLyrics @"spotifyglass.lyrics.pixie.enabled"
#define SGKeyPixieLyricsPaused @"spotifyglass.lyrics.pixie.paused"
BOOL SGPixieLyricsAvailable(void);
void SGPixieLyricsSettingsChanged(void);
void SGPixieLyricsDownloadMissing(void);
void SGPixieLyricsDeleteSaved(void (^done)(unsigned long long));
NSDictionary<NSString *,NSNumber *> *SGPixieLyricsCounts(void);
extern NSNotificationName const SGPixieLyricsProgress;
