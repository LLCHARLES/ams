#import "Localization.h"
#include <dlfcn.h>

NSString *SAPL(NSString *key,NSString *english) {
    // Do not cache a missing export: the companion can load before Retrine.
    NSString *(*localize)(NSString *,NSString *)=dlsym(RTLD_DEFAULT,"SGL");
    return localize ? localize(key,english) : english;
}

NSString *SAPDeviceL(NSString *key) {
    if([key isEqual:@"this_copy"])return SAPL(@"settings.pixie.devices.this_copy",@"This copy");
    if([key isEqual:@"other_copy"])return SAPL(@"settings.pixie.devices.other_copy",@"Other copy");
    if([key isEqual:@"enabled"])return SAPL(@"settings.pixie.devices.enabled",@"Offline enabled");
    if([key isEqual:@"disabled"])return SAPL(@"settings.pixie.devices.disabled",@"Offline disabled");
    if([key isEqual:@"not_registered"])return SAPL(@"settings.pixie.devices.not_registered",@"Not registered");
    if([key isEqual:@"unconfirmed"])return SAPL(@"settings.pixie.devices.unconfirmed",@"Registration unconfirmed");
    if([key isEqual:@"received"])return SAPL(@"settings.pixie.devices.received",@"received");
    if([key isEqual:@"unavailable"])return SAPL(@"settings.pixie.devices.unavailable",@"unavailable");
    if([key isEqual:@"transport_error"])return SAPL(@"settings.pixie.devices.transport_error",@"transport error");
    if([key isEqual:@"invalid_identities"])return SAPL(@"settings.pixie.devices.invalid_identities",@"The device response contains duplicate or invalid registrations. Nothing was changed.");
    if([key isEqual:@"snapshot_format"])return SAPL(@"settings.pixie.devices.snapshot_format",@"Last observed state (not proof of success)\nFree slots: %@ of %@ · Native slots: %@ of %@\nNative: %@ · Direct: %@");
    return nil;
}

NSString *SAPCategoryTitle(NSString *category) {
    if([category isEqual:@"Albums"])return SAPL(@"settings.pixie.category.albums",@"Albums");
    if([category isEqual:@"EPs"])return SAPL(@"settings.pixie.category.eps",@"EPs");
    if([category isEqual:@"Singles"])return SAPL(@"settings.pixie.category.singles",@"Singles");
    if([category isEqual:@"Singles & EPs"])return SAPL(@"settings.pixie.category.singles_eps",@"Singles & EPs");
    if([category isEqual:@"Compilations"])return SAPL(@"settings.pixie.category.compilations",@"Compilations");
    if([category isEqual:@"Appears on"])return SAPL(@"settings.pixie.category.appears_on",@"Appears on");
    if([category isEqual:@"Playlist"])return SAPL(@"settings.pixie.category.playlist",@"Playlist");
    return category;
}
