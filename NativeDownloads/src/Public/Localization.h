#pragma once
#import <Foundation/Foundation.h>

// Reuse Retrine's language, resources and checked English fallback.
// The key is stable; only the displayed value is translated.
NSString *SAPL(NSString *key,NSString *english) NS_FORMAT_ARGUMENT(2);
// Device states and catalog categories retain their nonlocalized identifiers.
NSString *SAPDeviceL(NSString *key);
NSString *SAPCategoryTitle(NSString *category);
