// Host inputs are doubles; error presentation, applyEffect/applyAll/tend and
// pending explicit-action delivery below are copied verbatim from AudioEffects.x.
#import "AudioEffectsApply.h"

static BOOL hostOn = YES;
static NSString *hostDirectory;
static dispatch_block_t pendingDrain;

BOOL SGDSPSwitch(NSString *key) { return [key isEqualToString:SGKeyDSPLiveprog] ? hostOn : YES; }
double SGDSPNumber(NSString *key) { return 0; }
NSString *SGDSPString(NSString *key) { return @"guard.eel"; }
NSString *SGDSPFileKey(SGDSPFileKind kind) { return SGKeyDSPLiveprogFile; }
NSString *SGDSPLibraryDirectory(SGDSPFileKind kind) { return hostDirectory; }
NSArray<NSString *> *SGDSPEffectSwitches(void) { return @[SGKeyDSPLiveprog]; }

// Other effect settings are never requested by this Liveprog-only host.
const double SGDSPEqualizerFrequencies[15] = {0};
const double SGDSPCompanderFrequencies[7] = {0};
NSArray<NSNumber *> *SGDSPGains(NSString *key) {
    require(false, "unexpected other-effect gains");
    return nil;
}
NSArray<NSString *> *SGDSPConvolverModeNames(void) { return @[]; }
NSArray<NSString *> *SGDSPCrossfeedModeNames(void) { return @[]; }
NSArray<NSString *> *SGDSPReverbPresetNames(void) { return @[]; }
static void SGPlayerSetOutputControl(BOOL on, double gain, double threshold, double release) {}

// This fixture supplies the selected file; preset-files.m tests the disk reader.
NSMutableData *SGDSPReadTextFile(NSURL *url, NSError **error) {
    return [NSMutableData dataWithContentsOfURL:url];
}

#include "AudioEffectsConfig.m"

// A route/format notification asks the production drain for a full reapplication.
// Engine rate and replacement changes are made by the test before that event.
static BOOL applyMaster(void) {
    applyAll(atomic_load(&sg_engine));
    return YES;
}

static void guard_after(dispatch_time_t time, dispatch_queue_t queue, dispatch_block_t callback) {
    pendingDrain = callback;
}
#define dispatch_after guard_after
#include "AudioEffectsApply.m"
#undef dispatch_after

static void hostDrain(void) {
    dispatch_block_t callback = pendingDrain;
    pendingDrain = nil;
    require(callback != nil, "host configuration was scheduled");
    callback();
}

static void hostApply(NSString *effect) {
    SGDSPApply(effect);
    hostDrain();
}

// AVAudioSession and AutoEq are host boundaries. The real followRoute scopes
// automatic setter notifications so they cannot masquerade as user retries.
@interface GuardAudioPort : NSObject
@property(nonatomic, copy) NSString *UID;
@property(nonatomic, copy) NSString *portName;
@end
@implementation GuardAudioPort
@end
@interface GuardRoute : NSObject
@property(nonatomic, copy) NSArray *outputs;
@end
@implementation GuardRoute
@end
@interface GuardAudioSession : NSObject
@property(nonatomic, strong) GuardRoute *currentRoute;
+ (instancetype)sharedInstance;
@end
@implementation GuardAudioSession
+ (instancetype)sharedInstance {
    static GuardAudioSession *session;
    if (!session) {
        session = [GuardAudioSession new];
        session.currentRoute = [GuardRoute new];
        GuardAudioPort *port = [GuardAudioPort new];
        port.UID = @"headphones";
        port.portName = @"Headphones";
        session.currentRoute.outputs = @[port];
    }
    return session;
}
@end
static void SGAutoEqOutputChanged(NSString *uid, NSString *name) {
    // AutoEq's synchronous applyPreset/leavePreset calls the settings setters,
    // each of which enqueues the affected effect through SGDSPApply.
    SGDSPApply(SGKeyDSPLiveprog);
}
#define AVAudioSessionPortDescription GuardAudioPort
#define AVAudioSession GuardAudioSession
#include "AudioEffectsRoute.m"
#undef AVAudioSession
#undef AVAudioSessionPortDescription

static void hostScript(const char *script) {
    NSString *path = [hostDirectory stringByAppendingPathComponent:@"guard.eel"];
    require([@(script) writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL],
            "script fixture is written");
}
