#pragma once
#import <Foundation/Foundation.h>

// Pixie's public ABI, declared locally so Retrine has no link-time companion dependency.
typedef struct { BOOL recognized; BOOL admitted; } SAPOfflineAttributesStatus;
FOUNDATION_EXPORT NSData *SAPRewriteOfflineAccountAttributesWithStatus(
    NSData *input, SAPOfflineAttributesStatus *status) __attribute__((visibility("default")));
#define SGOfflineCompanionImageName "SpotifyAudioProbe.dylib"
