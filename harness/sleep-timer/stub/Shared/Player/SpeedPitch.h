// The call SleepTimer.m makes of SpeedPitch.h, without UIKit; main.m answers it.
#import <Foundation/Foundation.h>
void SGPlayerSetGain(float gain);
typedef void *AudioUnit;
typedef void (*SGPlayerOutputWatcher)(AudioUnit);
BOOL SGPlayerWatchMusicOutput(SGPlayerOutputWatcher watcher);
#define SGPlayerSpeedDidChangeNotification @"test.speedChanged"
