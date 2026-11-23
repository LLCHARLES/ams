#import <Foundation/Foundation.h>
#import "Shared/Flags/Flags.h"
#define SGL(key, fallback) (fallback)
#define SGRestartNote nil
@interface SGModRow : NSObject
@property NSString *key;
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
        printf("PASS upsell settings %s\n", getenv("SPOTIFY_920") ? "9.2.0" : "9.1.90");
    }
    return 0;
}
