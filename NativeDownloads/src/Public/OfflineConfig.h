#pragma once
#import <Foundation/Foundation.h>
void SAPInstallOfflineConfig(void);
NSDictionary *SAPOfflineConfigReport(void);
// Pure transform, also exercised with captured-schema fixtures on the host.
__attribute__((visibility("default"))) NSData *SAPRewriteOfflineConfig(NSData *data, BOOL bootstrap);
// Complete nebula AccountAttributesResponse, not Ucs/Customize/Bootstrap.
// Field 1 is a repeated map entry: UTF-8 key[1], Attribute value[2]; the
// Attribute oneof is bool[2], integer[3] or UTF-8 string[4]. Existing value
// types and unrelated fields are preserved. Offline and can-use-offline become
// true; max-offline-tracks and max-offline-downloads-per-device become 1000000.
// Recognition requires a nonempty, valid field-1 map with typed attributes;
// empty bodies, other schemas and malformed maps are unrecognized.
typedef struct { BOOL recognized; BOOL admitted; } SAPOfflineAttributesStatus;
// One operation reports schema recognition independently of host admission.
// Admission is captured once per call, not rechecked between status and output.
// Returns rewritten bytes only when both are true, otherwise the input object.
// status may be NULL. Concurrent calls must use separate status storage and
// must not mutate input during the call. No account/cache/request writes occur.
// Admission reads an acquire/release atomic image snapshot published by dyld
// add/remove callbacks, plus immutable bundle metadata and target safety gates.
// No negative result is cached: calls before image loading completes can retry.
FOUNDATION_EXPORT NSData *SAPRewriteOfflineAccountAttributesWithStatus(
    NSData *input, SAPOfflineAttributesStatus *status) __attribute__((visibility("default")));
// Compatibility wrapper using the same operation with no status output.
__attribute__((visibility("default"))) NSData *SAPRewriteOfflineAccountAttributes(NSData *data);
BOOL SAPPrepareCachedOfflineConfig(NSUserDefaults *defaults);
