#import "TrackLibrary.h"
#import "NativeAdmission.h"
#import "TrackDownload.h"
#import "Localization.h"
#import "Deadline.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <os/lock.h>

// Spotify 9.1.90, UUID FBCE22C1-7E1B-3E0D-9BE8-66FF9291943E:
// CollectionPlatformImpl.stateProvider: 0x1057c8bd8, @16@0:8.
// addURL:showUIConfirmation:completion:: 0x1058e29d4, v36@0:8@16B24@?28.
// The completion bridge is 0x108b403b4 -> 0x107139d40 -> 0x101e01a0c
// -> 0x108658a78: masks w0 to one bit and invokes the block with BOOL.
// Use the base collection implementation, NOT aligned curation's default-save
// destination UI. A repeated add is still an add, never a toggle.
static NSString *const platformClass = @"_TtC23Collection_PlatformImpl22CollectionPlatformImpl";
static os_unfair_lock platformLock = OS_UNFAIR_LOCK_INIT;
static __weak id observedPlatform;

static void rememberPlatform(id platform) {
    os_unfair_lock_lock(&platformLock);
    observedPlatform = platform;
    os_unfair_lock_unlock(&platformLock);
}

void SAPInstallTrackLibrary(void) {
    if(!SAPRuntimeProfileAdmitted())return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = NSClassFromString(platformClass);
        SEL sel = NSSelectorFromString(@"stateProvider");
        Method method = class_getInstanceMethod(cls, sel);
        if (!method || strcmp(method_getTypeEncoding(method), "@16@0:8")) return;
        IMP original = method_getImplementation(method);
        class_replaceMethod(cls, sel, imp_implementationWithBlock(^id(id receiver) {
            rememberPlatform(receiver);
            return ((id (*)(id, SEL))original)(receiver, sel);
        }), method_getTypeEncoding(method));
    });
}

@interface SAPLibraryRequest : NSObject
@property(nonatomic) BOOL finished;
@property(nonatomic,strong) dispatch_source_t deadline;
@property(nonatomic,copy) void (^completion)(NSString *, NSString *);
@end
@implementation SAPLibraryRequest @end

static void finishLibrary(SAPLibraryRequest *request, NSString *status) {
    // Only main touches the request; even a synchronous native callback is
    // enqueued, never dispatched synchronously back to the download worker.
    if (request.finished) return;
    request.finished = YES;
    if (request.deadline) dispatch_source_cancel(request.deadline);
    request.deadline = nil;
    NSString *message = nil;
    if ([status isEqual:@"unavailable"])
        message = SAPL(@"settings.pixie.like.unavailable",@"Adding this track to Liked Songs is unavailable. Add it manually; download status is shown separately.");
    else if ([status isEqual:@"failed"])
        message = SAPL(@"settings.pixie.like.failed",@"Could not add this track to Liked Songs. Try adding it manually; download status is shown separately.");
    void (^completion)(NSString *, NSString *) = request.completion;
    request.completion = nil;
    if (completion) completion(status, message);
}

void SAPAddTrackToLikedSongs(NSString *uri, BOOL (^requested)(void),
                            void (^completion)(NSString *, NSString *)) {
    if(!SAPRuntimeProfileAdmitted()){if(completion)completion(@"unavailable",SAPL(@"settings.pixie.native.unsupported_profile",@"Pixie is not enabled for this exact Spotify profile."));return;}
    NSString *capturedURI = [uri copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        SAPLibraryRequest *request = [SAPLibraryRequest new];
        request.completion = completion;
        if (!requested || !requested()) { finishLibrary(request, @"cancelled"); return; }
        os_unfair_lock_lock(&platformLock);
        id platform = observedPlatform;
        os_unfair_lock_unlock(&platformLock);
        SEL sel = NSSelectorFromString(@"addURL:showUIConfirmation:completion:");
        Method method = class_getInstanceMethod(object_getClass(platform), sel);
        if (!SAPIsMusicTrackURI(capturedURI) || !platform || !method ||
            strcmp(method_getTypeEncoding(method), "v36@0:8@16B24@?28")) {
            finishLibrary(request, @"unavailable"); return;
        }
#ifdef SAP_TESTING
        double timeout = 0.08;
#else
        double timeout = 8;
#endif
        request.deadline = SAPScheduleDeadline(dispatch_get_main_queue(), timeout, ^{
            finishLibrary(request, @"failed");
        });
        @try {
            ((void (*)(id, SEL, NSURL *, BOOL, id))objc_msgSend)(
                platform, sel, [NSURL URLWithString:capturedURI], NO, ^(BOOL success) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        finishLibrary(request, success ? @"added" : @"failed");
                    });
                });
        } @catch (NSException *exception) {
            finishLibrary(request, @"failed");
        }
    });
}
