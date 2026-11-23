#import <Foundation/Foundation.h>
#import "Core/SGPrefs.h"

#define SGKeySponsorBlock @"spotifyglass.sponsorblock.enabled"
#define SGKeySponsorBlockOverlay @"spotifyglass.sponsorblock.overlay"
#define SGKeySponsorBlockRespectManual @"spotifyglass.sponsorblock.respectManualSeek"
#define SGKeySponsorBlockHaptics @"spotifyglass.sponsorblock.haptics"
#define SGKeySponsorBlockMinimum @"spotifyglass.sponsorblock.minDuration"
#define SGKeySponsorBlockCount @"spotifyglass.sponsorblock.skipCount"
#define SGKeySponsorBlockSaved @"spotifyglass.sponsorblock.timeSaved"

typedef NS_ENUM(NSInteger, SGSponsorBlockBehavior) {
    SGBlockAuto, SGBlockAsk, SGBlockShowOnly, SGBlockOff,
};
NSString *SGSponsorBlockBehaviorKey(NSString *category);
SGSponsorBlockBehavior SGSponsorBlockReadBehavior(NSUserDefaults *store, NSString *category);
double SGSponsorBlockMinimum(void);
enum { SGSponsorBlockMaxMinimum = 60 };
NSString *SGSponsorBlockValidServer(id value); // nil for an invalid HTTPS base
NSString *SGSponsorBlockServer(void); // validated, including the default
dispatch_block_t SGSponsorBlockRecordSkip(NSUserDefaults *store, double seconds);
void SGSponsorBlockResetStats(NSUserDefaults *store);

NSArray<NSString *> *SGSponsorBlockCategories(void);
BOOL SGSponsorBlockCategoryDefault(NSString *category);
NSString *SGSponsorBlockCategoryKey(NSString *category);
NSString *SGSponsorBlockEpisodeID(NSString *uri);
NSURLRequest *SGSponsorBlockRequest(NSString *episodeID, NSSet<NSString *> *categories);

@interface SGSponsorBlockSegment : NSObject
@property (nonatomic, readonly) double start, end;
@property (nonatomic, readonly, copy) NSString *category, *uuid;
@end

// nil means a failed/malformed response; 404 is an empty, successful result.
NSArray<SGSponsorBlockSegment *> *SGSponsorBlockParse(NSData *data, NSInteger status, NSString *episodeID);
typedef void (^SGSponsorBlockReply)(NSArray<SGSponsorBlockSegment *> *segments);
typedef void (^SGSponsorBlockFetch)(NSString *episodeID, NSSet<NSString *> *categories, SGSponsorBlockReply reply);
// Network and parsing off main; completion on main.
void SGSponsorBlockFetchSegments(NSString *episodeID, NSSet<NSString *> *categories, SGSponsorBlockReply reply);

typedef dispatch_block_t SGSponsorBlockAction;
typedef struct { double position, timestamp, rate; BOOL playing; } SGSponsorBlockReading;
typedef BOOL (^SGSponsorBlockReadLive)(NSString *episode, SGSponsorBlockReading *reading);
typedef void (^SGSponsorBlockNotice)(BOOL ask, SGSponsorBlockAction action);
typedef dispatch_block_t (^SGSponsorBlockRecord)(double seconds);
// Arm a single main-queue deadline; the returned block cancels it.
typedef dispatch_block_t (^SGSponsorBlockSchedule)(double delay, dispatch_block_t fire);

// Main-thread session; rules are a launch snapshot. The record boundary returns the stats reversal.
@interface SGSponsorBlockSession : NSObject
- (instancetype)initWithBehaviors:(NSDictionary<NSString *, NSNumber *> *)behaviors
                           minimum:(double)minimum respectManual:(BOOL)respectManual
                             fetch:(SGSponsorBlockFetch)fetch
                              seek:(void (^)(double seconds))seek
                            record:(SGSponsorBlockRecord)record notice:(SGSponsorBlockNotice)notice;
@property (nonatomic) double playbackRate;
// NSDate reference-date seconds, same domain as now(). Receipt time is not the player's timestamp.
@property (nonatomic) double reportTimestamp;
@property (nonatomic, copy) SGSponsorBlockReadLive readLive;
@property (nonatomic, copy) double (^now)(void);
@property (nonatomic, copy) SGSponsorBlockSchedule schedule;
@property (nonatomic, readonly, copy) NSArray<SGSponsorBlockSegment *> *visibleSegments;
@property (nonatomic, readonly) double episodeDuration;
- (void)observeURI:(NSString *)uri position:(double)position duration:(double)duration
          playing:(BOOL)playing enabled:(BOOL)enabled;
@end

// Overlay consumers: read on main; notification is posted synchronously on main (object = session).
// Segments are immutable, seconds in the current episode. Empty/zero outside an eligible episode.
FOUNDATION_EXPORT NSNotificationName const SGSponsorBlockSegmentsDidChangeNotification;
BOOL SGSponsorBlockMarkersEnabled(void); // master && marker switch, both read at launch
NSArray<SGSponsorBlockSegment *> *SGSponsorBlockVisibleSegments(void);
double SGSponsorBlockEpisodeDuration(void);
// The marks on a progress slider (SponsorBlockMarkers.m); main thread, from slider hooks a look installs only when
// SGSponsorBlockMarkersEnabled(). Shown: the slider entered a window, `opacity` its look's for the marks. Laid out:
// after the slider's own layout pass.
@class UISlider;
void SGSponsorBlockMarksShown(UISlider *slider, double opacity);
void SGSponsorBlockMarksLaidOut(UISlider *slider);

@class SGModSection;
SGModSection *SGSponsorBlockSettingsSection(void);
