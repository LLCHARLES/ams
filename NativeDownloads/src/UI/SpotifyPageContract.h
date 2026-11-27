#pragma once
#import <objc/runtime.h>
#include <stdlib.h>

static inline BOOL SAPImplementsPageMethods(Class page,Protocol *protocol) {
    for(unsigned kind=0;kind<2;kind++) {
        unsigned count=0;
        struct objc_method_description *methods=protocol_copyMethodDescriptionList(protocol,YES,kind==0,&count);
        BOOL complete=YES;
        for(unsigned i=0;i<count;i++) {
            Method method=kind==0?class_getInstanceMethod(page,methods[i].name):class_getClassMethod(page,methods[i].name);
            if(!method){complete=NO;break;}
        }
        free(methods);if(!complete)return NO;
    }
    unsigned count=0;
    Protocol *__unsafe_unretained *parents=protocol_copyProtocolList(protocol,&count);
    BOOL complete=YES;
    for(unsigned i=0;i<count;i++)if(!SAPImplementsPageMethods(page,parents[i])){complete=NO;break;}
    free(parents);return complete;
}

// Register only our own base classes. At presentation check the destination,
// not the class of the page opening it (the two dylibs can load separately).
static inline BOOL SAPSpotifyPageContract(Class page,BOOL registerClass) {
    const char *names[]={"_TtP19Tome_PageAttributes17SPTPageController_","SPTPageController"};
    BOOL found=NO;
    for(unsigned i=0;i<sizeof(names)/sizeof(*names);i++) {
        Protocol *protocol=objc_getProtocol(names[i]);if(!protocol)continue;
        found=YES;
        if(!SAPImplementsPageMethods(page,protocol))return NO;
        if(registerClass && ![page conformsToProtocol:protocol])class_addProtocol(page,protocol);
        if(![page conformsToProtocol:protocol])return NO;
    }
    return found;
}
