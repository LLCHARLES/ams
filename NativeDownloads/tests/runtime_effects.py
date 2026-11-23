"""Real admission + real cache/hooks and constructor/jailbreak entry bodies.

The constructor's iOS dependencies and jailbreak memory writer are system
doubles. Cache transformations and hook installation compile from production.
"""
from pathlib import Path
import subprocess
import tempfile
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from companion_build import include_directories
from generate_target import generate_headers
from pixie_target import V9190
ui=(ROOT/"src/Runtime/PixieBootstrap.m").read_text()
constructor=ui[ui.index("__attribute__((constructor)) static void SAPLoad(void)"):]
constructor=constructor.replace("__attribute__((constructor)) ","",1)
jailbreak=(ROOT/"src/JailbreakSupport.m").read_text().replace(
    "#import <CydiaSubstrate/CydiaSubstrate.h>","")
fixture=r'''
#include "profile_host.h"
#import "OfflineConfig.h"
#import "OfflineFlags.h"
#import "WireProto.h"
#import "DiagnosticTrace.h"
#import "JailbreakPatches.h"
#include <objc/runtime.h>
static unsigned effects,writes,patches;
static void MSHookMemory(void *p,const void *b,size_t n) {writes++;}
static bool TestPatch(uint8_t *image,size_t size,SAPJBWrite writer,void *context,const char **reason) {patches++;return true;}
bool SAPInstallJailbreakAudioImports(void) {effects++;return true;}
#define SAPJBApplyPatches TestPatch
'''
constructor_prelude=r'''
#undef SAPJBApplyPatches
#undef SAP_TRACE
#define SAP_TRACE(...) ((void)0)
#define SAP_JAILBREAK 1
static void constructorEffect(void) {effects++;}
static void constructorActive(BOOL active) {effects++;}
static BOOL constructorEnabled(void) {effects++;return NO;}
#define SAPDiagnosticsInitialize constructorEffect
#define SAPDiagnosticsEnabled constructorEnabled
#define SAPPlayerTraceSetActive constructorActive
#define SAPNativeErrorLogSetActive constructorActive
#define SpotifyAudioProbeInitialize constructorEffect
#define SAPInstallAVHooks constructorEffect
#define SAPInstallOfflineFlags constructorEffect
#define SAPInstallOfflineConfig constructorEffect
#define SAPInstallNativeOffline constructorEffect
#define SAPInstallTrackDownloader constructorEffect
#define SAPInstallDownloadSettings constructorEffect
#define SAPInstallNativeDownloadQualityObservation constructorEffect
#define SAPInstallNativeShareHooks constructorEffect
#define SAPSetOfflineKeySuccessObserver(...) constructorEffect()
#include "ProcessScope.h"
static NSString *UIApplicationDidFinishLaunchingNotification=@"fixture-launch";
static NSString *SAPDiagnosticsDidChangeNotification=@"fixture-unused";
'''
main=r'''
#undef SAPInstallOfflineConfig
#undef SAPInstallOfflineFlags
@interface Cache:NSUserDefaults
@property NSMutableDictionary *storage;
@property unsigned writes;
@end
@implementation Cache
- (NSData *)dataForKey:(NSString *)key {return self.storage[key];}
- (void)setObject:(id)value forKey:(NSString *)key {self.writes++;self.storage[key]=value;}
@end
@interface SPTDataLoaderService:NSObject
- (void)URLSession:(id)s dataTask:(id)t didReceiveData:(id)d;
- (void)URLSession:(id)s task:(id)t didCompleteWithError:(id)e;
@end
@implementation SPTDataLoaderService
- (void)URLSession:(id)s dataTask:(id)t didReceiveData:(id)d {}
- (void)URLSession:(id)s task:(id)t didCompleteWithError:(id)e {}
@end
int main(void) {@autoreleasepool {
    Cache *cache=[Cache new];cache.storage=[NSMutableDictionary dictionary];
    NSData *body=SAPProtoBytes(1,SAPProtoBytes(3,[NSData data]));
    const uint8_t accountBytes[]={0x0a,0x0d,0x0a,7,'o','f','f','l','i','n','e',0x12,2,0x10,0};
    NSData *account=[NSData dataWithBytes:accountBytes length:sizeof(accountBytes)];
    cache.storage[@"eeveeCachedCustomizeData"]=body;
    Method method=class_getInstanceMethod(SPTDataLoaderService.class,@selector(URLSession:dataTask:didReceiveData:));
    IMP original=method_getImplementation(method);
    for(unsigned i=0;i<7;i++) {
        exactHost();
        if(i==0)metadata=@{@"CFBundleShortVersionString":@"9.2.0",@"CFBundleVersion":@"920002054"};
        if(i==1)metadata=@{@"CFBundleShortVersionString":@"9.1.90",@"CFBundleVersion":@"other"};
        if(i==2)images[0].uuid.uuid[0]^=1;
        if(i==3)images[1].uuid.uuid[0]^=1;
        if(i==4)imageCount=1;
        if(i==5)metadata=@{@"CFBundleShortVersionString":@"9.1.90",@"CFBundleVersion":@"919002269",@"NSExtension":@{}};
        if(i==6)hostPath=@"Payload/Spotify.appex";
        publishImages();
        SAPLoad();
        if(SAPInstallJailbreakSupport()||effects||writes||patches) {
            fprintf(stderr,"unsupported host %u had constructor/jailbreak effects\n",i);return 1;
        }
        SAPInstallOfflineConfig();SAPInstallOfflineFlags();
        if(SAPPrepareCachedOfflineConfig(cache)||cache.writes||
           SAPRewriteOfflineConfig(body,NO)!=body||
           SAPRewriteOfflineAccountAttributes(account)!=account||method_getImplementation(method)!=original) {
            fprintf(stderr,"unsupported host %u rewrote cache/config/hooks\n",i);return 1;
        }
    }
    exactHost();
    if([SAPRewriteOfflineAccountAttributes(account)isEqual:account]) {
        fputs("admitted account attributes did not transform\n",stderr);return 1;
    }
    if(!SAPPrepareCachedOfflineConfig(cache)||cache.writes!=2||
       [cache.storage[@"eeveeCachedCustomizeData"]isEqual:body]) {
        fputs("admitted cache transformation did not execute\n",stderr);return 1;
    }
    SAPInstallOfflineConfig();
    if(method_getImplementation(method)==original||!SAPInstallJailbreakSupport()||patches!=1) {
        fputs("admitted hook/jailbreak boundary did not execute\n",stderr);return 1;
    }
    puts("PASS unsupported constructor, cache, config hooks and jailbreak writes are inert");return 0;
}}
'''
with tempfile.TemporaryDirectory(prefix="pixie-runtime-effects-") as temporary:
    folder=Path(temporary);source=folder/"effects.m"
    include=folder/"include";generate_headers(include,V9190)
    source.write_text(fixture+jailbreak+constructor_prelude+constructor+main)
    config=ROOT/"src/Spotify/OfflineConfig.m"
    for mutation in (True,False):
        candidate=config
        if mutation:
            candidate=folder/"OfflineConfig.m"
            original=config.read_text()
            guard="if(!observed.recognized||!observed.admitted)return input;"
            if guard not in original:raise AssertionError("Transformer admission site moved")
            candidate.write_text(original.replace(guard,"if(!observed.recognized)return input;",1))
        subprocess.run(["xcrun","clang","-fobjc-arc",*["-I"+str(p) for p in include_directories(include)],"-I"+str(ROOT/"tests"),
                        str(source),str(candidate),*[str(ROOT/p) for p in [
                            "src/Spotify/OfflineFlags.m","src/Spotify/WireProto.m","src/UI/Localization.m",
                            "src/Diagnostics/DiagnosticTrace.m","src/Diagnostics/NativeKeyTrace.m","tests/trace_platform_stub.m"]],
                        "-framework","Foundation","-o",str(folder/"effects")],check=True)
        result=subprocess.run([str(folder/"effects")],capture_output=True,text=True)
        if mutation:
            if result.returncode!=1 or "rewrote cache/config/hooks" not in result.stderr:
                raise AssertionError("Transformer admission mutation was not detected: "+result.stderr)
            print("PASS mutation: rejected-host account transformer mutation detected")
        else:
            if result.returncode:raise AssertionError(result.stderr)
            print(result.stdout,end="")
