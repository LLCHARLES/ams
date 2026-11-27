#import "SGWGCore.h"
#import "SGWGImage.h"
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <string.h>

SGWGImageMatch SGWGMatchImage(const char *path) {
    if (!path) return (SGWGImageMatch){0};
    static dispatch_once_t once;
    static NSData *ownedName;
    static const void *bytes;
    static size_t length;
    dispatch_once(&once, ^{
        NSString *name = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleExecutable"];
        if ([name isKindOfClass:NSString.class]) ownedName = [name dataUsingEncoding:NSUTF8StringEncoding];
        bytes = ownedName.bytes;
        length = ownedName.length;
    });
    const char *slash = strrchr(path, '/');
    const char *name = slash ? slash + 1 : path;
    return (SGWGImageMatch){
        .main = !strcmp(name, "Spotify") || (length && strlen(name) == length && !memcmp(name, bytes, length)),
        .shared = !strcmp(name, "SpotifyShared"),
    };
}

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
        SGWGImageMatch match = SGWGMatchImage(_dyld_get_image_name(i));
        if (!match.main && !match.shared) continue;
        const struct mach_header_64 *header = (const void *)_dyld_get_image_header(i);
        if (!header || header->magic != MH_MAGIC_64) return NO;
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
        if (![uuid isEqualToString:match.main ? expectedMain : expectedShared]) return NO;
        mainSeen |= match.main;
        sharedSeen |= match.shared;
    }
    if (pendingImages) *pendingImages = !mainSeen || !sharedSeen;
    return mainSeen && sharedSeen;
#endif
}

BOOL SGWGAdmissionReady(void) { return SGWGCheckAdmission(NULL); }
