"""Execute the actual preference observer while main waits for a background writer."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT/"src/Export/NativeShareHooks.m").read_text()
start = source.index("state.defaultsObserver=")
observer = source[start:source.index("\n", start)]
fixture = r'''
#import <Foundation/Foundation.h>
static NSString *const SAPNativeSharePreference=@"PixieShareAsFile";
@interface SAPNativeShareState:NSObject
@property id defaultsObserver;
@property BOOL suspended,lastPreference;
@property unsigned applied;
- (void)apply;
@end
@implementation SAPNativeShareState
- (void)apply {if(!NSThread.isMainThread){fputs("UI callback off main\n",stderr);exit(3);}self.applied++;}
@end
int main(void){@autoreleasepool {
    SAPNativeShareState *state=[SAPNativeShareState new];
    state.lastPreference=![NSUserDefaults.standardUserDefaults boolForKey:SAPNativeSharePreference];
    __weak SAPNativeShareState *weak=state;
'''
ending = r'''
    dispatch_semaphore_t finished=dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{
        [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:NSUserDefaults.standardUserDefaults];
        dispatch_semaphore_signal(finished);
    });
    if(dispatch_semaphore_wait(finished,dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC))){
        fputs("background defaults writer waited on main\n",stderr);return 1;
    }
    NSDate *end=[NSDate dateWithTimeIntervalSinceNow:3];
    while(!state.applied&&end.timeIntervalSinceNow>0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.001]];
    [NSNotificationCenter.defaultCenter removeObserver:state.defaultsObserver];
    if(state.applied!=1){fputs("UI update not delivered once\n",stderr);return 2;}
    puts("PASS defaults notification does not block the writer; UI update runs asynchronously on main");return 0;
}}
'''
with tempfile.TemporaryDirectory(prefix="pixie-defaults-notification-") as temporary:
    folder = Path(temporary)
    for mutation in (True, False):
        candidate = observer.replace("queue:nil", "queue:NSOperationQueue.mainQueue", 1) if mutation else observer
        (folder/"check.m").write_text(fixture+candidate+ending)
        subprocess.run(["xcrun", "clang", "-fobjc-arc", "-framework", "Foundation",
                        str(folder/"check.m"), "-o", str(folder/"check")], check=True)
        result = subprocess.run([str(folder/"check")], capture_output=True, text=True, timeout=10)
        if mutation:
            if result.returncode != 1 or "waited on main" not in result.stderr:
                raise AssertionError("Synchronous observer mutation was not detected: "+result.stderr)
            print("PASS mutation: main-queue observer deadlock is detected")
        elif result.returncode:
            raise AssertionError(result.stdout+result.stderr)
        else:
            print(result.stdout, end="")
