#!/usr/bin/env python3
"""Exercise DJ's shipped asset reader and layout body with Foundation UI doubles.

Logos/UIKit cannot run on macOS Foundation; extraction keeps the product
decisions executable, with assets and popup presentation as boundary doubles.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
text = (ROOT / "tweak/Sources/Shared/AdBlock/DJ.x").read_text()
helpers = text[text.index("static id stringsAsset"):text.index("// The title is set")]
layout = text[text.index("- (void)viewDidLayoutSubviews"):text.index("%end", text.index("%hook PopUpContainer"))]
layout = layout.replace("%orig;", "").replace("%c(SPTEncorePopUpPresenter)", "presenterClass")
fixture = r'''
#import <Foundation/Foundation.h>
#define SGLog(...) do {} while(0)
static NSDictionary *assets;
static BOOL missingBundle;
static Class presenterClass;
static BOOL missingDismiss;
@interface Bundle : NSObject
+ (instancetype)mainBundle;
+ (instancetype)bundleWithPath:(NSString *)path;
- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)type;
- (NSArray *)preferredLocalizations;
@end
@implementation Bundle
+ (instancetype)mainBundle { return [self new]; }
+ (instancetype)bundleWithPath:(NSString *)path { return [self new]; }
- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)type { return missingBundle ? nil : @"strings"; }
- (NSArray *)preferredLocalizations { return @[@"de"]; }
@end
#define NSBundle Bundle
@interface NSDataAsset : NSObject
@property NSData *data;
- (instancetype)initWithName:(NSString *)name bundle:(NSBundle *)bundle;
@end
@implementation NSDataAsset
- (instancetype)initWithName:(NSString *)name bundle:(NSBundle *)bundle {
    if ((self = [super init]) && assets[name]) _data = [NSJSONSerialization dataWithJSONObject:assets[name] options:0 error:nil];
    return self;
}
@end
@interface UIView : NSObject
@property BOOL hidden;
@property UIView *window;
@property NSString *text;
@end
@implementation UIView
@end
#define UILabel UIView
@interface UIViewController : NSObject
@property UIView *view;
@end
@implementation UIViewController
@end
id SGFindIdentifier(UIView *view, NSString *identifier, void *key) { return view; }
static int dismissals;
static BOOL cleared;
@interface SPTEncorePopUpPresenter : NSObject
+ (id)shared;
- (void)dismissPopupWithAnimate:(BOOL)animate clearQueue:(BOOL)clearQueue completion:(id)completion;
@end
@implementation SPTEncorePopUpPresenter
+ (id)shared { return missingDismiss ? [NSObject new] : [self new]; }
- (void)dismissPopupWithAnimate:(BOOL)animate clearQueue:(BOOL)clearQueue completion:(id)completion {
    dismissals++; cleared = clearQueue;
}
@end
'''
test = r'''
int main(int argc, char **argv) { @autoreleasepool {
    int scenario = atoi(argv[1]);
    presenterClass = scenario == 5 ? NSObject.class : SPTEncorePopUpPresenter.class;
    missingDismiss = scenario == 6;
    assets = @{@"_i18n.KEYS": @[@"SPTEndless_DJMusicImpl:sDJMRegionUnavailableDialogTitle"],
               @"_i18n.INDEX": @{@"en": @"english", @"de": @"german"},
               @"_i18n.english": @[@"DJ is not available in your country"],
               @"_i18n.german": @[@"DJ ist in deinem Land nicht verfügbar"]};
    if (scenario == 1) assets = @{};
    if (scenario == 2) missingBundle = YES;
    if (scenario == 3) assets = @{@"_i18n.KEYS": @[@"different key"]};
    if (scenario == 4) assets = @{@"_i18n.KEYS": @[@"SPTEndless_DJMusicImpl:sDJMRegionUnavailableDialogTitle"],
                                @"_i18n.en": @[], @"_i18n.de": @[@42]};
    NSArray *titles = @[@"DJ is not available in your country", @"DJ ist in deinem Land nicht verfügbar",
                         @"Meet your DJ", @"DJ is not available in your country!", @"Clear cache", NSNull.null];
    for (NSUInteger i = 0; i < titles.count; i++) {
        Popup *popup = [Popup new]; popup.view = [UIView new]; popup.view.window = [UIView new];
        popup.view.text = titles[i] == NSNull.null ? nil : titles[i];
        int before = dismissals;
        [popup viewDidLayoutSubviews];
        BOOL expected = scenario == 0 && i < 2;
        if (popup.view.window.hidden != expected || (dismissals > before) != expected || cleared) {
            NSLog(@"FAIL DJ scenario=%d title=%@", scenario, titles[i]); return 1;
        }
        [popup viewDidLayoutSubviews];
        if (dismissals != before + (expected ? 1 : 0)) return 1;
    }
    printf("PASS DJ exact match and fail-open scenario %d\n", scenario);
    return 0;
}}
'''
source = fixture + helpers + "\n@interface Popup : UIViewController\n@end\n@implementation Popup\n" + layout + "\n@end\n" + test
with tempfile.TemporaryDirectory(prefix="dj-dialog-") as temp:
    out = Path(temp)
    (out / "check.m").write_text(source)
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", str(out / "check.m"),
                    "-framework", "Foundation", "-o", str(out / "dj-check")], check=True)
    for scenario in range(7):
        subprocess.run([str(out / "dj-check"), str(scenario)], check=True)
