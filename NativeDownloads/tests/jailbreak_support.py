"""Jailbreak bootstrap readiness follows patch and import admission, never packaging."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
fixture = r'''
#import <Foundation/Foundation.h>
#import "JailbreakSupport.h"
#import "JailbreakPatches.h"
static bool admitted,patches,imports;
static unsigned patchCalls,importCalls;
bool SAPRuntimeProfileAdmitted(void){return admitted;}
bool SAPJBApplyPatches(uint8_t *image,size_t size,SAPJBWrite write,void *ctx,const char **reason) {
    patchCalls++;*reason=patches?NULL:"fixture_patch_refused";return patches;
}
bool SAPInstallJailbreakAudioImports(void){importCalls++;return imports;}
void MSHookMemory(void *target,const void *bytes,size_t length){}
int main(void){@autoreleasepool {
    if([SAPJailbreakSupportReport()[@"native_patches_ready"]boolValue])return 1;
    if(SAPInstallJailbreakSupport()||patchCalls||importCalls)return 2;
    if(![SAPJailbreakSupportReport()[@"reason"]isEqual:@"unsupported_image"])return 3;
    admitted=true;
    if(SAPInstallJailbreakSupport()||importCalls)return 4;
    if(![SAPJailbreakSupportReport()[@"reason"]isEqual:@"fixture_patch_refused"])return 5;
    patches=true;
    if(SAPInstallJailbreakSupport())return 6;
    if(![SAPJailbreakSupportReport()[@"reason"]isEqual:@"audio_imports_unavailable"])return 7;
    imports=true;
    if(!SAPInstallJailbreakSupport()||![SAPJailbreakSupportReport()[@"native_patches_ready"]boolValue])return 8;
    admitted=false;
    if(SAPInstallJailbreakSupport()||[SAPJailbreakSupportReport()[@"native_patches_ready"]boolValue])return 9;
    puts("PASS jailbreak bootstrap reports ready only after admitted patches and audio imports");return 0;
}}
'''

with tempfile.TemporaryDirectory(prefix="pixie-jailbreak-support-") as temp:
    folder = Path(temp)
    (folder/"CydiaSubstrate").mkdir()
    (folder/"CydiaSubstrate/CydiaSubstrate.h").write_text("#include <stddef.h>\nvoid MSHookMemory(void *,const void *,size_t);\n")
    (folder/"check.m").write_text(fixture)
    source = (ROOT/"src/JailbreakSupport.m").read_text()
    for mutation in (True, False):
        candidate = source.replace("if(!SAPRuntimeProfileAdmitted())return false;", "if(false)return false;") if mutation else source
        (folder/"JailbreakSupport.m").write_text(candidate)
        subprocess.run(["xcrun", "clang", "-fobjc-arc", "-I"+str(folder), "-I"+str(ROOT/"src"),
                        "-I"+str(ROOT/"src/Public"), str(folder/"check.m"),
                        str(folder/"JailbreakSupport.m"), "-framework", "Foundation",
                        "-o", str(folder/"check")], check=True)
        result = subprocess.run([str(folder/"check")], capture_output=True, text=True)
        expected = 2 if mutation else 0
        if result.returncode != expected:
            raise AssertionError(f"bootstrap mutation={mutation}: {result.returncode}\n{result.stdout}{result.stderr}")
        print("PASS mutation: bypassing jailbreak host admission is rejected" if mutation else result.stdout.strip())
