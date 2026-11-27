// Reuse the existing NSURLSession/Spotify doubles and real Logos hooks.
#define main legacyOfflineHarnessMain
#include "../../harness/adblock/offline-check.m"
#undef main

int main(int argc,const char **argv) { @autoreleasepool {
    if(argc!=2)return 1;
    SEL response=@selector(URLSession:dataTask:didReceiveResponse:completionHandler:);
    Class cls=SPTDataLoaderService.class;
    IMP original=class_getMethodImplementation(cls,response);
    void *library=dlopen(argv[1],RTLD_NOW|RTLD_GLOBAL);
    if(!library)return 1;
    dispatch_sync(offlineInstallQueue, ^{});
    check(class_getMethodImplementation(cls,response)==original,@"rejected companion leaves delegate untouched");
    protocolCases(NO,NO);
    void (*admit)(bool)=dlsym(library,"SGTestSetAdmitted");
    if(!admit)return 1;
    admit(true);
    [NSNotificationCenter.defaultCenter postNotificationName:@"SAPOfflineProfileReady" object:nil];
    dispatch_sync(offlineInstallQueue, ^{});
    protocolCases(YES,YES);
    completionCases();
    printf("Offline delegate admission: %u checks; %u failures\n",checks,failures);
    return failures?1:0;
}}
