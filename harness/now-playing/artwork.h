#import <Foundation/Foundation.h>
#import "../harness-wait.h"
#import "Shared/LockScreenLyrics/LockScreenLyrics.h"
@class SPTPlayerState, SGKaraokeLine;
void check(BOOL ok, NSString *what);
void runFor(NSTimeInterval seconds);
static inline void drainMain(void) {
    __block BOOL delivered = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ delivered = YES; });
    HARNESS_AWAIT(delivered);
}
SGKaraokeLine *lineOf(NSString *text, NSInteger start, NSInteger end);
SPTPlayerState *harnessState(NSString *uri, NSString *title);
void harnessLines(NSArray *lines);
void harnessPosition(NSInteger position);
void harnessReport(NSString *uri, NSString *title);
void harnessMetadata(NSDictionary *metadata);
NSDictionary *harnessSystem(void);
NSUInteger harnessSets(void);
void artworkChecks(void);
void activityChecks(void);
void publicationChecks(void);
extern NSString *harnessLanguage;
extern NSDictionary *harnessTranslations;
extern BOOL harnessHoldTranslation;
extern NSUInteger harnessAutomaticTranslations;
void harnessDeliverTranslations(void);
void harnessReading(SGRLyricsReading reading, BOOL leads);
extern NSString *harnessSongLanguage;
