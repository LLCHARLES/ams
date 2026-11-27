"""Execute selected-profile runtime admission using dyld and bundle doubles."""
from dataclasses import replace
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from pixie_target import V9190,V9200,V9202
from generate_target import generate_headers

fixture=r'''
#include "profile_host.h"
int main(int argc,char **argv) {@autoreleasepool {
    metadata=@{@"CFBundleShortVersionString":@(argv[1]),@"CFBundleVersion":@(argv[2])};
    for(unsigned i=0;i<2;i++) {
        images[i].header.magic=MH_MAGIC_64;images[i].header.ncmds=1;
        images[i].header.sizeofcmds=sizeof(struct uuid_command);
        images[i].uuid.cmd=LC_UUID;images[i].uuid.cmdsize=sizeof(struct uuid_command);
        uuid(argv[3+i],images[i].uuid.uuid);
    }
    publishImages();
    uintptr_t base=(uintptr_t)&images[0];
    if(!SAPRuntimeProfileAdmitted()){fputs("wrong exact-profile admission\n",stderr);return 1;}
    NSDictionary *correct=metadata;
    for(NSString *key in @[@"CFBundleShortVersionString",@"CFBundleVersion"]) {
        NSMutableDictionary *bad=[correct mutableCopy];bad[key]=@"other";metadata=bad;
        if(SAPProfileMatchesImage(base)){fputs("accepted metadata mismatch\n",stderr);return 1;}
    }
    metadata=correct;
    for(unsigned i=0;i<2;i++) {
        images[i].uuid.uuid[0]^=1;
        publishImages();
        if(SAPProfileMatchesImage(base)){fputs("accepted UUID mismatch\n",stderr);return 1;}
        images[i].uuid.uuid[0]^=1;
        publishImages();
    }
    imageCount=1;
    publishImages();
    if(SAPProfileMatchesImage(base)){fputs("accepted missing shared image\n",stderr);return 1;}
    imageCount=2;
    publishImages();
    if(SAPProfileMatchesImage(base+1)){fputs("accepted unrelated image\n",stderr);return 1;}
    printf("PASS Spotify %s runtime admission and fingerprint rejection\n",argv[1]);return 0;
}}
'''
with tempfile.TemporaryDirectory(prefix="pixie-runtime-profile-") as temporary:
    folder=Path(temporary)
    source=folder/"check.m";source.write_text(fixture)
    for profile,args in (
        (V9190,("9.1.90","919002269","fbce22c17e1b3e0d9be866ff9291943e","2e074234cfc63f0e9255c9881824167a")),
        (V9200,("9.2.0","920002054","b49e75781d8635d38bb57daf68fed8a8","30bac55f8361373aad607f0535395641")),
        (V9202,("9.2.2","920202587","bedf0071845d39bbb2d096f9a8095e66","527ccb30a88f3dadb1b985336d3bcad6")),
    ):
        include=folder/profile.version
        generate_headers(include,profile)
        subprocess.run(["xcrun","clang","-fobjc-arc","-I"+str(include),"-I"+str(ROOT/"src"),"-I"+str(ROOT/"tests"),
                        str(source),"-framework","Foundation","-o",str(folder/"check")],check=True)
        subprocess.run([str(folder/"check"),*args],check=True)
        if profile == V9200:
            generate_headers(include,replace(profile,runtime_layout_verified=False))
            subprocess.run(["xcrun","clang","-fobjc-arc","-I"+str(include),"-I"+str(ROOT/"src"),"-I"+str(ROOT/"tests"),
                            str(source),"-framework","Foundation","-o",str(folder/"closed")],check=True)
            result=subprocess.run([str(folder/"closed"),*args],capture_output=True,text=True)
            if result.returncode != 1 or result.stderr.strip() != "wrong exact-profile admission":
                raise AssertionError("Closing the 9.2.0 layout gate did not fail the admission fixture")
            print("PASS mutation: closed 9.2.0 layout gate detected")
