// Exercise the production SGModPage init hook, including init replacement/nil.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../../harness/harness-fail.h"
#import "AudioProbeUI.h"
#import "PixiePageController.h"
#import "PixiePageNavigation.h"

@interface FixturePageOwner : UIViewController
@property(nonatomic,strong) UIViewController *sheet;
@end
@implementation FixturePageOwner
- (void)presentViewController:(UIViewController *)page animated:(BOOL)animated completion:(void (^)(void))completion {
    self.sheet=page;
}
@end
@interface FixtureHostStack : UINavigationController @end
@implementation FixtureHostStack @end
@interface FixtureIncompletePage : UIViewController @end
@implementation FixtureIncompletePage @end

static NSUInteger destroyed;
static NSArray *receivedSections;
static __weak id allocatedReceiver;
static __weak id replacement;
static NSUInteger mode;

@interface SGModPage : NSObject
- (instancetype)initWithTitle:(NSString *)title intro:(NSString *)intro
                     sections:(NSArray *)sections footer:(NSString *)footer;
@end
@implementation SGModPage
- (instancetype)initWithTitle:(NSString *)title intro:(NSString *)intro
                     sections:(NSArray *)sections footer:(NSString *)footer {
    receivedSections=sections;
    if(mode==1) {
        self=(id)[NSObject new];
        replacement=self;
        return self;
    }
    if(mode==2)return nil;
    return [super init];
}
- (void)dealloc {destroyed++;}
@end

// Keep the actual navigation factory in the row, as the host does.
@interface FixtureRow : NSObject
@property(nonatomic,copy) NSString *title, *searchIdentifier, *searchKeywords;
@property(nonatomic,copy) UIViewController *(^page)(void);
@end
@implementation FixtureRow @end
@interface FixtureGroup : NSObject
@property(nonatomic,copy) NSArray<FixtureRow *> *rows;
@end
@implementation FixtureGroup @end
__attribute__((visibility("default")))
FixtureRow *SGPageRow(NSString *title,UIViewController *(^page)(void)) {
    FixtureRow *row=[FixtureRow new];row.title=title;row.page=page;return row;
}
__attribute__((visibility("default")))
id SGSearchIdentified(FixtureRow *row,NSString *identifier) {row.searchIdentifier=identifier;return row;}
__attribute__((visibility("default")))
id SGSearchKeywords(FixtureRow *row,NSString *keywords) {row.searchKeywords=keywords;return row;}
__attribute__((visibility("default")))
id SGWithTile(id row,NSString *symbol,UIColor *color) {return row;}
__attribute__((visibility("default")))
FixtureGroup *SGSection(NSString *title,NSArray *rows) {FixtureGroup *group=[FixtureGroup new];group.rows=rows;return group;}

int main(void) {
    @autoreleasepool {
        SAPInstallDownloadSettings();
        for(NSString *title in @[@"Retrine",@"Vitrine"]) for(mode=0;mode<3;mode++) {
            NSUInteger before=destroyed;
            __weak id result;
            @autoreleasepool {
                SGModPage *page=[SGModPage alloc];
                allocatedReceiver=page;
                FixtureRow *ads=SGSearchIdentified(SGPageRow(@"Ads",nil),@"page.ads");
                FixtureGroup *privacy=SGSection(nil,@[ads]), *advanced=SGSection(nil,@[]);
                page=[page initWithTitle:title intro:nil sections:@[privacy,advanced] footer:nil];
                result=page;
                HARNESS_CHECK(receivedSections.count==2);
                HARNESS_CHECK(receivedSections.firstObject==privacy && receivedSections.lastObject==advanced);
                HARNESS_CHECK(privacy.rows.count==2 && privacy.rows.firstObject==ads);
                if(mode==0) {
                    HARNESS_CHECK(page==allocatedReceiver && destroyed==before);
                    FixtureRow *row=privacy.rows.lastObject;
                    HARNESS_CHECK([row.title isEqual:@"Pixie downloads"] && [row.searchIdentifier isEqual:@"page.pixie"] && row.searchKeywords.length);
                    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:UIViewController.new];
                    [nav pushViewController:row.page() animated:NO];
                    [nav.topViewController loadViewIfNeeded];
                    HARNESS_CHECK([nav.topViewController.title isEqual:@"Pixie Download Manager"]);
                }
                if(mode==1)HARNESS_CHECK(allocatedReceiver==nil && page==replacement && destroyed==before+1);
                if(mode==2)HARNESS_CHECK(page==nil && allocatedReceiver==nil && destroyed==before+1);
            }
            HARNESS_CHECK(result==nil && replacement==nil && destroyed==before+1);
        }
        mode=0;
        @autoreleasepool {
            id page=[[SGModPage alloc] initWithTitle:@"Other" intro:nil sections:@[@"existing"] footer:nil];
            HARNESS_CHECK(page && receivedSections.count==1);
        }
        FixturePageOwner *owner=[FixturePageOwner new];
        UINavigationController *stack=[[FixtureHostStack alloc]initWithRootViewController:owner];
        SAPPixiePageController *page=[[SAPPixiePageController alloc]initWithStyle:UITableViewStyleGrouped];
        SAPShowPixiePage(owner,page);
        HARNESS_CHECK(stack.topViewController==page && !owner.sheet);
        [stack popViewControllerAnimated:NO];
        // Reproduce stale conformance metadata without creating a duplicate
        // runtime protocol. The host fixture already declares both spellings.
        FixtureIncompletePage *incomplete=[FixtureIncompletePage new];
        for(NSString *name in @[@"SPTPageController",@"_TtP19Tome_PageAttributes17SPTPageController_"]) {
            Protocol *protocol=NSProtocolFromString(name);
            HARNESS_CHECK(protocol!=nil);
            class_addProtocol(incomplete.class,protocol);
            HARNESS_CHECK([incomplete conformsToProtocol:protocol]);
        }
        SAPShowPixiePage(owner,incomplete);
        UINavigationController *sheet=(id)owner.sheet;
        HARNESS_CHECK(stack.topViewController==owner && [sheet isKindOfClass:UINavigationController.class] && sheet.topViewController==incomplete);
        UIViewController *child=[UIViewController new];
        SAPShowPixiePage(incomplete,child);
        HARNESS_CHECK(sheet.topViewController==child);
        puts("PASS: both roots open Pixie; incompatible page presents separately with working nested navigation");
    }
    return 0;
}
