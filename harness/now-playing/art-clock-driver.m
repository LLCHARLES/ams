// Observe the actual one-shot deadline without scheduling or firing another timer.
#import <Foundation/Foundation.h>
extern int64_t harnessArtDelay;
extern CFAbsoluteTime harnessExtrasNow;
extern int64_t harnessArtDue;
extern __weak dispatch_source_t harnessArmedArt;
static _Thread_local int64_t deltaNs;
static dispatch_time_t artTime(dispatch_time_t start, int64_t delta) {
    deltaNs = delta;
    return dispatch_time(start, delta);
}
static void artTimer(dispatch_source_t source, dispatch_time_t start, uint64_t repeat, uint64_t leeway) {
    harnessArtDelay = deltaNs;
    harnessArmedArt = source;
    harnessArtDue = (int64_t)(harnessExtrasNow * NSEC_PER_SEC) + deltaNs;
    dispatch_source_set_timer(source, start, repeat, leeway);
}
#define dispatch_time artTime
#define dispatch_source_set_timer artTimer
extern NSUInteger harnessArtFires;
static void artHandler(dispatch_source_t source, dispatch_block_t block) {
    dispatch_source_set_event_handler(source, ^{ harnessArtFires++; block(); });
}
#define dispatch_source_set_event_handler artHandler
#import "art-dispatch.h"
#import "Core/SGFileHash.h"
NSUInteger harnessArtworkHashes;
static NSString *countArtworkHash(NSData *data) {
    harnessArtworkHashes++;
    return SGDataSHA256(data);
}
#define SGDataSHA256 countArtworkHash
#include "LyricsArtwork.m"
