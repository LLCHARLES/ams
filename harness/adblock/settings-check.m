#import <Foundation/Foundation.h>
#import "Shared/Flags/Flags.h"
#define SGL(key, fallback) (fallback)
#define SGRestartNote nil
@class UIViewController;
@interface SGModRow : NSObject
@property NSString *key;
@property NSString *title, *warning;
@property (copy) UIViewController *(^page)(void);
@property (copy) NSString *(^value)(void);
@property (copy) void (^action)(void);
@end
@implementation SGModRow
@end
@interface SGModSection : NSObject
@property NSArray *rows;
@end
@implementation SGModSection
@end
@interface UIViewController : NSObject
@end
@implementation UIViewController
@end
@interface SGModPage : UIViewController
@property NSArray<SGModSection *> *sections;
- (instancetype)initWithTitle:(NSString *)title intro:(NSString *)intro sections:(NSArray *)sections footer:(NSString *)footer;
@end
@implementation SGModPage
- (instancetype)initWithTitle:(NSString *)title intro:(NSString *)intro sections:(NSArray *)sections footer:(NSString *)footer {
    if ((self = [super init])) _sections = sections;
    return self;
}
@end
static SGModRow *SGFlagRow(NSString *title, NSString *key) {
    SGModRow *row = [SGModRow new]; row.key = key; return row;
}
static SGModRow *SGKillRow(NSString *title, NSString *key) { return SGFlagRow(title, key); }
static SGModSection *SGSection(NSString *title, NSArray *rows) {
    SGModSection *section = [SGModSection new]; section.rows = rows; return section;
}
static SGModSection *SGNotedSection(NSString *title, NSArray *rows, NSString *note) { return SGSection(title, rows); }
static SGModRow *SGPageRow(NSString *title, UIViewController *(^page)(void)) {
    SGModRow *row = [SGModRow new]; row.title = title; row.page = page; return row;
}
static SGModRow *SGStatRow(NSString *title, NSString *(^value)(void)) {
    SGModRow *row = [SGModRow new]; row.title = title; row.value = value; return row;
}
static SGModRow *SGActionRow(NSString *title, NSString *detail, void (^action)(void)) {
    SGModRow *row = [SGModRow new]; row.title = title; row.action = action; return row;
}
#define SGSearchIdentified(row, identifier) (row)
#define SGWithSymbol(row, symbol) (row)
#define SGOptionRow(title, subtitle, key) SGFlagRow(title, key)
#define SGKeyFakePremium @"premium"
#define SGKeyHideAds @"ads"
#define SGKeyHideUpsells @"upsells"
#define SGFakePremiumWarning @"warning"
static SGModSection *SGSponsorBlockSettingsSection(void) { return SGSection(nil, @[]); }
static SGModSection *SGPrivacySection(void) { return SGSection(nil, @[]); }
static SGModSection *SGPrivacyCountersSection(void) { return SGSection(nil, @[SGStatRow(@"Telemetry fixture", ^{ return @"4"; })]); }
static NSArray *SGAdBlockLabels(void) { return @[@"Requests"]; }
static NSUInteger ads = 7;
static NSUInteger SGAdBlockCount(NSString *label) { return ads; }
static NSUInteger SGAdBlockChecked(NSString *label) { return 10; }
static NSUInteger SGBlockedCount(NSString *label) { return 4; }
static void SGResetAdBlock(void) { ads = 0; }
// The removed key is last, so each runtime can expose its own table length.
const SGFlagDef SGFlagTable[] = {
    {"ios-feature-nowplaying-modes.video_first_shuffle_upsell_enabled", SGFlagBool, 1, 0, 1},
    {"ios-feature-shuffletoggleupsell.is_enabled_pt2", SGFlagBool, 1, 0, 1},
};
// The production declaration is const; supply the runtime fixture through the page's view of it.
static NSUInteger fixtureCount(void) { return getenv("SPOTIFY_920") ? 1 : 2; }
#define SGFlagCount fixtureCount()
#include "page.inc"
int main(void) {
    @autoreleasepool {
        SGModPage *page = (id)adFlagsPage();
        NSArray *keys = [page.sections[1].rows valueForKey:@"key"];
        NSArray *expected = getenv("SPOTIFY_920")
            ? @[@"ios-feature-nowplaying-modes.video_first_shuffle_upsell_enabled"]
            : @[@"ios-feature-shuffletoggleupsell.is_enabled_pt2", @"ios-feature-nowplaying-modes.video_first_shuffle_upsell_enabled"];
        if (![keys isEqualToArray:expected]) { NSLog(@"FAIL unavailable upsell row: %@", keys); return 1; }
        SGModPage *settings = (id)SGAdsSettingsPage();
        SGModRow *link = settings.sections.lastObject.rows.firstObject;
        if (![link.title isEqual:@"Blocked statistics"] || ![link.value() isEqual:@"Ads 7 · Telemetry 4"]) {
            NSLog(@"FAIL statistics link or counter summary"); return 1;
        }
        SGModPage *statistics = (id)link.page();
        NSArray<SGModRow *> *adRows = statistics.sections.firstObject.rows;
        if (statistics.sections.count != 2 || ![adRows.firstObject.value() isEqual:@"7 of 10"]) {
            NSLog(@"FAIL grouped ad and telemetry statistics"); return 1;
        }
        adRows.lastObject.action();
        if (![link.value() isEqual:@"Ads 0 · Telemetry 4"]) { NSLog(@"FAIL independent ad reset"); return 1; }
        printf("PASS upsell settings %s\n", getenv("SPOTIFY_920") ? "9.2.0" : "9.1.90");
    }
    return 0;
}
