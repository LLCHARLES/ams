// Generated from targets/*.json by tools/generate_target.py; do not edit.
#pragma once
#include <stdint.h>
#define SAP_SPOTIFY_VERSION "9.1.90"
#define SAP_TARGET_MANAGER_FIELD_SHIFT 0
#define SAP_TARGET_SETTER UINT64_C(0x101d1debc)
#define SAP_TARGET_MANAGER_VTABLE UINT64_C(0x10ca326c8)
#define SAP_TARGET_PROVIDER UINT64_C(0x1083de7b0)
#define SAP_TARGET_RENDER_CALLBACK UINT64_C(0x1076b9e2c)
#define SAPProfileVersion "9.1.90"
#define SAPProfileBuild "919002269"
#define SAPProfileMainUUIDHex "fbce22c17e1b3e0d9be866ff9291943e"
#define SAPProfileEnabled 0x1
#define SAPProfileReservationCountersVerified 0x1
#define SAPProfileRuntimeLayoutVerified 0x1
#define SAPProfileSetterOffset 0x1d1debc
#define SAPProfileVtableOffset 0xca326c8
#define SAPProfileCallOffset 0x3594f60
#define SAPProfileProviderOffset 0x83de7b0
#define SAPProfileQuotaBlockOffset 0x2b0
#define SAPProfileWrapperManagerOffset 0x8
#define SAPProfileQueueFlagsOffset 0x220
#define SAPProfileManagerProviderOffset 0x290
#define SAPProfileTraceOwnerOffset 0x8
#define SAPProfileTraceDescriptorOffset 0xc8
#define SAPProfileDescriptorFileOffset 0x4
static const uint8_t SAPProfileMainUUID[]={0xfb,0xce,0x22,0xc1,0x7e,0x1b,0x3e,0x0d,0x9b,0xe8,0x66,0xff,0x92,0x91,0x94,0x3e};
static const uint8_t SAPProfileSharedUUID[]={0x2e,0x07,0x42,0x34,0xcf,0xc6,0x3f,0x0e,0x92,0x55,0xc9,0x88,0x18,0x24,0x16,0x7a};
static const uint8_t SAPProfileSetterCode[]={0xe6,0x03,0x1e,0xaa,0x8f,0x3e,0xf4,0x95,0xfe,0x03,0x06,0xaa,0xfd,0x7b,0x11,0xa9};
static const uint8_t SAPProfileProviderHead[]={0xff,0x03,0x06,0xd1,0xfc,0x6f,0x12,0xa9,0xfa,0x67,0x13,0xa9,0xf8,0x5f,0x14,0xa9,0xf6,0x57,0x15,0xa9,0xf4,0x4f,0x16,0xa9,0xfd,0x7b,0x17,0xa9,0xfd,0xc3,0x05,0x91,0xf5,0x03,0x05,0xaa,0xf4,0x03,0x00,0xaa,0xf7,0x03,0x08,0xaa,0x08,0x40,0x42,0x39};
static const struct {const char *name;uintptr_t offset;size_t length;} SAPProfileSamples[]={
{"key_request_entry",0x3594f60,4},
{"key_request_observer",0x23700,239},
{"key_success_entry",0x6231e70,16},
{"key_success_observer",0x23900,251},
{"key_failure_entry",0x893730,16},
{"key_failure_observer",0x23b00,251},
{"quota_setter_entry",0x1d1debc,16},
{"quota_guard",0x23f00,48},
{"native_key_provider_entry",0x83de7b0,48},
};
static const struct {const char *cls,*selector,*encoding;unsigned arguments;} SAPProfileRequiredMethods[]={
{"SPTOfflineManagerImplementation","initWithScheduler:offlineManager:syncManager:metadataModel:","@48@0:8@16^{OfflineManager=^^?}24^{SyncManager=^^?^^?}32^v40",6},
{"SPTOfflineManagerImplementation","stateForTrackWithURL:","Q24@0:8@16",3},
{"SPTOfflineManagerImplementation","makeEntityAvailableOfflineWithURL:trackURLs:","v32@0:8@16@24",4},
{"SPTOfflineManagerImplementation","makeEntityAvailableOfflineWithURL:","v24@0:8@16",3},
{"SPTOfflineManagerImplementation","resetEntityOfflineAvailabilityWithURL:","v24@0:8@16",3},
{"SPTFreeTierOfflineStatusUpdatingContentOperation","offlineSyncStatusForURL:","q24@0:8@16",3},
{"SPTEsperantoTransportBridgeImpl","callSingle:method:payload:onResponse:","@48@0:8@16@24@32@?40",6},
{"SPTEsperantoTransportBridgeImpl","callStream:method:payload:onResponse:","@48@0:8@16@24@32@?40",6},
{"SPTEsperantoCosmosTransport","callSingle:method:payload:onResponse:","@48@0:8@16@24@32@?40",6},
{"SPTEsperantoCosmosTransport","callStream:method:payload:onResponse:","@48@0:8@16@24@32@?40",6},
{"SPTCoreProductState","stringForKey:","@24@0:8@16",3},
{"SPTCoreProductState","setOriginalValues:","v24@0:8@16",3},
{"SPTDataLoaderService","URLSession:task:didCompleteWithError:","v40@0:8@16@24@32",5},
{"Connectivity_HttpClientKit.HttpClientURLSession","URLSession:task:didCompleteWithError:","v40@0:8@16@24@32",5},
{"SPTCoreURLSessionDataDelegate","URLSession:task:didCompleteWithError:","v40@0:8@16@24@32",5},
};
