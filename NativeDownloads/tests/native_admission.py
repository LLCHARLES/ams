"""Run SAPPrepareNativeOffline with a scheduler/manager double, without UIKit.

Only the function is extracted because the enclosing file links private iOS UI
hooks; the executable runs the actual production admission and setter ordering.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "src/Spotify/NativeOfflineAdapter.m").read_text()
body = source[source.index("void SAPPrepareNativeOffline("):source.index("void SAPReadNativeOfflineQuota(")]
fixture = r'''
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import "NativeSetupStatus.h"
#import "Localization.h"
#define SAPProfileSetterOffset 0
static const uintptr_t setterOffset=0;
#define SAPUnsupportedProfileReason "Unsupported test profile"
static bool admitted=true;
static bool SAPRuntimeProfileAdmitted(void) {return admitted;}
static unsigned setters,finishes;
static BOOL valid,guarded,prepared;
static int mode,tracks;
static long long duration;
static void setter(void *m,int32_t d,int32_t t,int32_t ed,int32_t e,int32_t a) {
    setters++;tracks=t;duration=d;
}
static BOOL nativeState(id w,void **m,uintptr_t *i,NSMutableDictionary *out) {
    if(!valid)return NO;
    *m=(void *)1;*i=(uintptr_t)setter;
    [out addEntriesFromDictionary:@{@"restriction_guard_active":@(guarded),
        @"key_mode_runtime_selectable":@NO,@"offline_key_request_mode":@(mode),
        @"music_limit":@(tracks),@"music_duration_seconds":@(duration),
        @"episode_duration_seconds":@1,@"episode_limit":@1,@"abp_duration_seconds":@1}];
    return YES;
}
static void SAPInstallNativeOffline(void) {}
static unsigned long SAPTraceCurrentOperation(void) {return 0;}
@interface Scheduler:NSObject
- (id)scheduler;
- (void)postBlock:(void (^)(void))block;
@end
@implementation Scheduler
- (id)scheduler {return self;}
- (void)postBlock:(void (^)(void))block {block();}
@end
static id nativeWrapper;
@interface SAPNativePreparation:NSObject
@property(copy) void (^completion)(BOOL,NSString *);
@property unsigned long traceOperation;
@property BOOL finished;
- (void)finish:(BOOL)ready reason:(NSString *)reason report:(NSDictionary *)report;
@end
@implementation SAPNativePreparation
- (void)finish:(BOOL)ready reason:(NSString *)reason report:(NSDictionary *)report {
    if(self.finished)return;self.finished=YES;finishes++;self.completion(ready,reason);
}
@end
'''
main = r'''
int main(void) {@autoreleasepool {
    nativeWrapper=[Scheduler new];
    admitted=false;
    SAPPrepareNativeOffline(nil,^(BOOL ready,NSString *reason){prepared=ready;});
    if(setters||prepared){fputs("rejected host invoked private setter\n",stderr);return 1;}
    admitted=true;
    const struct {BOOL valid,guard;int mode;unsigned setters;BOOL ready;} cases[]={
        {NO,YES,0,0,NO},{YES,NO,0,0,NO},{YES,YES,1,0,NO},
        {YES,YES,-1,0,NO},{YES,YES,0,1,YES}
    };
    for(unsigned n=0;n<sizeof(cases)/sizeof(cases[0]);n++) {
        valid=cases[n].valid;guarded=cases[n].guard;mode=cases[n].mode;
        setters=finishes=tracks=duration=0;prepared=NO;
        SAPPrepareNativeOffline(nil,^(BOOL ready,NSString *reason){prepared=ready;});
        if(setters!=cases[n].setters||finishes!=1||prepared!=cases[n].ready) {
            fprintf(stderr,"admission case %u: setters=%u ready=%d\n",n,setters,prepared);return 1;
        }
    }
    puts("PASS native preparation: rejected profiles/patches never invoke setter");return 0;
}}
'''

with tempfile.TemporaryDirectory(prefix="pixie-admission-") as temporary:
    folder = Path(temporary)
    for mutation in (True, False):
        candidate = body.replace("if(!patchReady)", "if(NO)") if mutation else body
        (folder / "check.m").write_text(fixture + candidate + main)
        subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks",
                        "-I"+str(ROOT/"src/Public"),"-I"+str(ROOT/"src/Generated"),"-framework", "Foundation",
                        str(folder / "check.m"), str(ROOT/"src/Spotify/NativeSetupStatus.m"),
                        str(ROOT/"src/UI/Localization.m"), "-o", str(folder / "check")], check=True)
        result = subprocess.run([str(folder / "check")], capture_output=True, text=True)
        if mutation:
            if result.returncode == 0 or "admission case 1: setters=1" not in result.stderr:
                raise AssertionError("Admission mutation was not detected: " + result.stderr)
            print("PASS mutation: setter-before-admission defect detected")
        else:
            if result.returncode:
                raise AssertionError(result.stderr)
            print(result.stdout, end="")
