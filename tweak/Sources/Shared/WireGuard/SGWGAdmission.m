#import "SGWGCore.h"
#import <mach-o/dyld.h>
#import <mach-o/loader.h>

BOOL SGWGCheckAdmission(BOOL *pendingImages) {
    if (pendingImages) *pendingImages = NO;
#ifdef SGWG_TESTING
    NSString *build = NSProcessInfo.processInfo.environment[@"SGWG_TEST_APP_BUILD"] ?: @"919002269";
    return [SGWGAppVersion() isEqualToString:@"9.1.90"] && [build isEqualToString:@"919002269"];
#else
    NSString *version = SGWGAppVersion();
    NSString *build = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    NSString *expectedMain = nil, *expectedShared = nil;
#define SGWG_TARGET(number, revision, mainUUID, sharedUUID) \
    if ([version isEqualToString:@number] && [build isEqualToString:@revision]) { expectedMain = @mainUUID; expectedShared = @sharedUUID; }
#include "SGWGTargets.inc"
#undef SGWG_TARGET
    if (!expectedMain) return NO;
    BOOL mainSeen = NO, sharedSeen = NO;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        NSString *name = @(_dyld_get_image_name(i)).lastPathComponent;
        BOOL main = [name isEqualToString:@"Spotify"] ||
            [name isEqualToString:[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleExecutable"]];
        BOOL shared = [name isEqualToString:@"SpotifyShared"];
        if (!main && !shared) continue;
        const struct mach_header_64 *header = (const void *)_dyld_get_image_header(i);
        if (header->magic != MH_MAGIC_64) return NO;
        const uint8_t *cursor = (const uint8_t *)(header + 1), *end = cursor + header->sizeofcmds;
        NSString *uuid = nil;
        for (uint32_t j = 0; j < header->ncmds; j++) {
            if ((size_t)(end - cursor) < sizeof(struct load_command)) return NO;
            const struct load_command *command = (const void *)cursor;
            if (command->cmdsize < sizeof(*command) || command->cmdsize > (size_t)(end - cursor)) return NO;
            if (command->cmd == LC_UUID && command->cmdsize >= sizeof(struct uuid_command)) {
                NSUUID *value = [[NSUUID alloc] initWithUUIDBytes:((const struct uuid_command *)command)->uuid];
                uuid = [[value.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""] lowercaseString];
            }
            cursor += command->cmdsize;
        }
        if (![uuid isEqualToString:main ? expectedMain : expectedShared]) return NO;
        mainSeen |= main;
        sharedSeen |= shared;
    }
    if (pendingImages) *pendingImages = !mainSeen || !sharedSeen;
    return mainSeen && sharedSeen;
#endif
}

BOOL SGWGAdmissionReady(void) { return SGWGCheckAdmission(NULL); }
