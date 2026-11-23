#import "Localization.h"
#include <assert.h>
#include <dlfcn.h>
#include <string.h>

int main(int argc,char **argv) { @autoreleasepool {
    assert(argc>=3);
    NSString *language=@(argv[1]);
    BOOL bridge=[@(argv[2]) isEqual:@"bridge"];
    BOOL late=argc>3 && strcmp(argv[3],"--load-retrine")==0;
    if(late) {
        assert(argc>4);
        assert(dlsym(RTLD_DEFAULT,"SGL")==NULL);
        assert([SAPL(@"common.cancel",@"Cancel") isEqual:@"Cancel"]);
        assert(dlopen(argv[4],RTLD_NOW|RTLD_GLOBAL));
    }
    assert((dlsym(RTLD_DEFAULT,"SGL")!=NULL)==bridge);
    BOOL korean=[language isEqual:@"ko"];
    assert([SAPDeviceL(@"this_copy")isEqual:korean?@"이 사본":@"This copy"]);
    assert([SAPDeviceL(@"not_registered")isEqual:korean?@"등록되지 않음":@"Not registered"]);
    NSString *snapshot=[NSString stringWithFormat:SAPDeviceL(@"snapshot_format"),@1,@5,@2,@5,SAPDeviceL(@"received"),SAPDeviceL(@"unavailable")];
    assert([snapshot isEqual:korean?@"마지막으로 확인한 상태(성공을 의미하지 않음)\n사용 가능한 슬롯: 1 / 5 · 앱 슬롯: 2 / 5\n앱: 수신됨 · 직접 응답: 사용 불가":
        @"Last observed state (not proof of success)\nFree slots: 1 of 5 · Native slots: 2 of 5\nNative: received · Direct: unavailable"]);
    assert([SAPL(@"common.cancel",@"Cancel") isEqual:korean?@"취소":@"Cancel"]);
    assert([SAPL(@"settings.pixie.missing_fixture_key",@"Missing translation") isEqual:@"Missing translation"]);
    assert([SAPL(@"common.cancel",@"Invalid format %ld") isEqual:@"Invalid format %ld"]);
    NSString *(*selectedLanguage)(void)=dlsym(RTLD_DEFAULT,"SGLanguage");
    if(selectedLanguage)assert([selectedLanguage() isEqual:language]);

    // Expected values come directly from the shipped source resources, not SAPL.
    NSBundle *bundle=[NSBundle bundleWithPath:[NSBundle.mainBundle pathForResource:@"Retrine" ofType:@"bundle"]];
    NSUInteger checked=0;
    if(bundle) {
        NSDictionary *english=[NSDictionary dictionaryWithContentsOfFile:
            [bundle pathForResource:@"Localizable" ofType:@"strings" inDirectory:nil forLocalization:@"en"]];
        NSDictionary *translated=[NSDictionary dictionaryWithContentsOfFile:
            [bundle pathForResource:@"Localizable" ofType:@"strings" inDirectory:nil forLocalization:language]];
        for(NSString *key in english) {
            if(![key hasPrefix:@"settings.pixie."])continue;
            NSString *expected=korean?translated[key]:english[key];
            assert(expected.length && [SAPL(key,english[key]) isEqual:expected]);
            checked++;
        }
        assert(checked>0);
    }
    printf("PASS: Pixie %s; bridge=%d; %lu resource values, missing-key/format fallback%s\n",
           language.UTF8String,bridge,(unsigned long)checked,late?"; late-loaded Retrine":"");
    return 0;
} }
