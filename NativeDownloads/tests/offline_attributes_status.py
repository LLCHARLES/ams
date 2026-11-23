"""Run the public status transformer with real admission and dyld/bundle doubles."""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/"tools"))
from companion_build import include_directories
from generate_target import generate_headers
from pixie_target import V9190

fixture = r'''
#include "profile_host.h"
#import "OfflineConfig.h"
#import "WireProto.h"
#include <stdatomic.h>
static atomic_uint failures;

static BOOL rewritten(NSData *data) {
    NSMutableDictionary *values=[NSMutableDictionary dictionary];
    for(NSDictionary *field in SAPProtoFields(data)) {
        NSArray *entry=SAPProtoFields(field[@"value"]);
        NSString *key=SAPProtoString(entry,1);
        NSArray *value=SAPProtoFields(SAPProtoData(entry,2));
        if(key)values[key]=@(SAPProtoNumber(value,2,SAPProtoNumber(value,3,0)));
    }
    return [values isEqual:@{@"offline":@1,@"can-use-offline":@1,
        @"max-offline-tracks":@1000000,@"max-offline-downloads-per-device":@1000000}];
}
static BOOL consistent(NSData *input,BOOL recognized,int admitted) {
    SAPOfflineAttributesStatus status={!recognized,NO};
    NSData *output=SAPRewriteOfflineAccountAttributesWithStatus(input,&status);
    if(status.recognized!=recognized||(admitted>=0&&status.admitted!=admitted))return NO;
    return recognized&&status.admitted?rewritten(output):output==input;
}
int main(void){@autoreleasepool {
    const uint8_t bytes[]={0x0a,0x0d,0x0a,7,'o','f','f','l','i','n','e',0x12,2,0x10,0};
    NSData *valid=[NSData dataWithBytes:bytes length:sizeof(bytes)];
    NSData *unknown=SAPProtoInteger(98,123);
    exactHost();
    NSDictionary *correct=metadata;
    for(unsigned admitted=0;admitted<2;admitted++) {
        metadata=admitted?correct:@{@"CFBundleShortVersionString":@"other",@"CFBundleVersion":@"919002269"};
        dispatch_apply(128,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^(size_t i){@autoreleasepool {
            NSData *input=i%2?valid:unknown;
            if(!consistent(input,i%2,admitted))atomic_fetch_add(&failures,1);
            NSData *without=SAPRewriteOfflineAccountAttributesWithStatus(input,NULL);
            NSData *legacy=SAPRewriteOfflineAccountAttributes(input);
            if(admitted&&i%2) {
                if(!rewritten(without)||![without isEqual:legacy])atomic_fetch_add(&failures,1);
            } else if(without!=input||legacy!=input)atomic_fetch_add(&failures,1);
        }});
    }
    if(atomic_load(&failures)){fputs("status matrix or NULL/legacy wrapper mismatch\n",stderr);return 1;}
    for(NSData *bad in @[NSData.data,SAPProtoBytes(1,SAPProtoBytes(3,valid)),
        SAPProtoBytes(1,SAPProtoBytes(1,[@"offline" dataUsingEncoding:NSUTF8StringEncoding])),
        [NSData dataWithBytes:(uint8_t[]){0x0a,0xff} length:2]]) {
        if(!consistent(bad,NO,YES)){fputs("malformed body was recognized\n",stderr);return 1;}
    }
    imageCount=1;publishImages();
    if(!consistent(valid,YES,NO)){fputs("missing shared image admitted\n",stderr);return 1;}
    imageCount=2;publishImages();
    if(!consistent(valid,YES,YES)){fputs("early rejection was cached\n",stderr);return 1;}
    dispatch_apply(256,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^(size_t i){@autoreleasepool {
        if(i%4==0){removedImage(image_header(1),0);addedImage(image_header(1),0);}
        if(!consistent(valid,YES,-1)||!consistent(unknown,NO,-1))atomic_fetch_add(&failures,1);
    }});
    if(atomic_load(&failures)){fputs("status and rewrite disagree during image notifications\n",stderr);return 1;}
    removedImage(image_header(1),0);
    if(!consistent(valid,YES,NO)){fputs("image removal did not revoke admission\n",stderr);return 1;}
    puts("PASS recognition x admission, concurrent callers, NULL status, wrapper parity and loading snapshots");
    return 0;
}}
'''

with tempfile.TemporaryDirectory(prefix="pixie-attributes-status-") as temporary:
    folder = Path(temporary)
    include = folder/"include"
    generate_headers(include, V9190)
    (folder/"check.m").write_text(fixture)
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    original = (ROOT/"src/Spotify/OfflineConfig.m").read_text()
    guard = "observed.recognized=accountAttributesRecognized(input);"
    if guard not in original:
        raise AssertionError("Recognition mutation site moved")
    for mutation in (True, False):
        candidate = original.replace(guard, "observed.recognized=observed.admitted&&accountAttributesRecognized(input);", 1) if mutation else original
        (folder/"OfflineConfig.m").write_text(candidate)
        subprocess.run(["xcrun", "clang", "-isysroot", sdk, "-fobjc-arc", "-fsanitize=address,undefined",
                        *("-I"+str(p) for p in include_directories(include)), "-I"+str(ROOT/"tests"),
                        str(folder/"check.m"), str(folder/"OfflineConfig.m"), *(str(ROOT/p) for p in (
                            "src/Spotify/WireProto.m", "src/UI/Localization.m",
                            "src/Diagnostics/DiagnosticTrace.m", "src/Diagnostics/NativeKeyTrace.m",
                            "tests/trace_platform_stub.m")),
                        "-framework", "Foundation", "-o", str(folder/"check")], check=True)
        result = subprocess.run([str(folder/"check")], capture_output=True, text=True)
        if mutation:
            if result.returncode != 1 or "status matrix" not in result.stderr:
                raise AssertionError("Recognition/admission coupling mutation was not detected: "+result.stderr)
            print("PASS mutation: recognition incorrectly gated by admission is rejected")
        else:
            if result.returncode:
                raise AssertionError(result.stdout+result.stderr)
            print(result.stdout, end="")
