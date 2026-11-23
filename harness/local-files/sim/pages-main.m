#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import "Shared/LocalFiles/LocalMusicPages.h"
#import "Shared/LocalFiles/LocalMusicStore.h"
#import "Shared/LocalFiles/LocalAudioImport.h"
#import "Shared/LocalFiles/LocalMusicPlayback.h"
#import "../../harness-fail.h"

@protocol SPTPageController <NSObject>
@end
@interface LocalPageProtocol : NSObject <SPTPageController>
@end
@implementation LocalPageProtocol
@end

static NSUInteger imports;
void SGLocalAudioPresentPicker(UIViewController *presenter) { ++imports; }
NSNotificationName const SGLocalMusicPlaybackDidChangeNotification = @"fixture.playback";
BOOL SGLocalMusicPlaybackAvailable(void) { return NO; }
NSString *SGLocalMusicVerifiedURI(NSString *name, NSArray *identity) { return nil; }
BOOL SGLocalMusicCanPlaySongs(NSArray *songs) { return NO; }
void SGLocalMusicPlay(NSArray *songs, BOOL shuffle, void (^done)(NSError *)) { HARNESS_FAIL(@"Unverified fixture played"); }
void SGLocalMusicQueue(SGLocalMusicSong *song, BOOL next, void (^done)(NSError *)) { HARNESS_FAIL(@"Unverified fixture queued"); }

@interface PagesApp : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UINavigationController *nav;
@property (nonatomic, strong) SGLocalMusicIndex *index;
@property (nonatomic) NSUInteger step;
- (void)advance;
@end

static UIImage *cover(void) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(160, 160) format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor colorWithRed:0.13 green:0.27 blue:0.34 alpha:1] setFill];
        UIRectFill(CGRectMake(0, 0, 160, 160));
        [[UIColor colorWithRed:0.88 green:0.60 blue:0.34 alpha:1] setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(48, 32, 64, 64)] fill];
        [@"NIGHT\nSESSIONS" drawInRect:CGRectMake(16, 108, 144, 48) withAttributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:16 weight:UIFontWeightBold],
            NSForegroundColorAttributeName: UIColor.whiteColor}];
    }];
}
static void advance(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{ [(__bridge PagesApp *)observer advance]; });
}
static UICollectionView *albumCollection(UIView *view) {
    if ([view isKindOfClass:UICollectionView.class]) return (UICollectionView *)view;
    for (UIView *child in view.subviews) {
        UICollectionView *collection = albumCollection(child);
        if (collection) return collection;
    }
    return nil;
}

@implementation PagesApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    [UIView setAnimationsEnabled:NO];
    SGRegisterPages();
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    NSArray *titles = @[@"First Light", @"Blue Hour", @"Open Water", @"Slow Motion", @"Northern Lights", @"Home Again", @"Afterglow"];
    NSMutableArray *songs = [NSMutableArray array];
    NSURL *coverURL = [SGLocalAudioFolder() URLByAppendingPathComponent:@"fixture-cover.png"];
    HARNESS_CHECK([UIImagePNGRepresentation(cover()) writeToURL:coverURL atomically:YES]);
    SGLocalMusicArtworkReference *art = [[SGLocalMusicArtworkReference alloc] initWithURL:coverURL
        identity:SGLocalMusicFileIdentity(coverURL) format:nil item:0 edited:NO];
    for (NSUInteger i = 0; i < titles.count; ++i) {
        [songs addObject:[[SGLocalMusicSong alloc] initWithName:[NSString stringWithFormat:@"Sessions/%@.flac", titles[i]]
            metadataURI:nil tags:@{@"title": titles[i], @"artist": @"Mira & The Coast", @"album": @"Night Sessions", @"disc": @1, @"track": @(i + 1)}
            edit:@{} artwork:art]];
    }
    [songs addObject:[[SGLocalMusicSong alloc] initWithName:@"Untitled recording.wav" metadataURI:nil tags:@{} edit:@{} artwork:nil]];
    self.index = [[SGLocalMusicIndex alloc] initWithSongs:songs];
    self.nav = [[UINavigationController alloc] initWithRootViewController:[[SGLocalMusicPage alloc] initWithIndex:self.index kind:@"library" key:nil]];
    self.window.rootViewController = self.nav;
    [self.window makeKeyAndVisible];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, advance, CFSTR("com.retrine.localpages.next"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    return YES;
}
- (void)shot:(NSString *)name {
    [self.window layoutIfNeeded];
    NSLog(@"[harness] SHOT %@", name);
}
- (void)advance {
    SGLocalMusicPage *page = (id)self.nav.topViewController;
    switch (self.step++) {
        case 0:
            HARNESS_CHECK([page tableView:page.tableView numberOfRowsInSection:0] == 2);
            NSLog(@"[harness] NEXT");
            break;
        case 1: {
            NSIndexPath *artistPath = [NSIndexPath indexPathForRow:1 inSection:0];
            [page tableView:page.tableView didSelectRowAtIndexPath:artistPath];
            [self.nav.view layoutIfNeeded];
            break;
        }
        case 2:
            HARNESS_CHECK([page.title isEqual:@"Mira & The Coast"]);
            HARNESS_CHECK([page tableView:page.tableView numberOfRowsInSection:0] == 6);
            HARNESS_CHECK([page numberOfSectionsInTableView:page.tableView] == 2);
            [self shot:@"Artist"];
            break;
        case 3: {
            [page tableView:page.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:5 inSection:0]];
            HARNESS_CHECK([page tableView:page.tableView numberOfRowsInSection:0] == 7);
            NSIndexPath *shelfPath = [NSIndexPath indexPathForRow:0 inSection:1];
            [page.tableView scrollToRowAtIndexPath:shelfPath atScrollPosition:UITableViewScrollPositionBottom animated:NO];
            [page.tableView layoutIfNeeded];
            UICollectionView *albums = albumCollection([page.tableView cellForRowAtIndexPath:shelfPath]);
            HARNESS_CHECK(albums != nil);
            [albums.delegate collectionView:albums didSelectItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
            break;
        }
        case 4:
            HARNESS_CHECK([page.title isEqual:@"Night Sessions"]);
            HARNESS_CHECK([page tableView:page.tableView numberOfRowsInSection:0] == 7);
            HARNESS_CHECK([page tableView:page.tableView contextMenuConfigurationForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] point:CGPointZero] != nil);
            [self shot:@"Album"];
            break;
        case 5: {
            SGLocalMusicGroup *folder = self.index.folders.lastObject;
            [self.nav pushViewController:[[SGLocalMusicPage alloc] initWithIndex:self.index kind:@"folder" key:folder.key] animated:NO];
            break;
        }
        case 6:
            HARNESS_CHECK([page.title isEqual:@"Sessions"]);
            HARNESS_CHECK([page tableView:page.tableView numberOfRowsInSection:0] == 7);
            [UIApplication.sharedApplication sendAction:page.navigationItem.rightBarButtonItem.action
                to:page.navigationItem.rightBarButtonItem.target from:nil forEvent:nil];
            HARNESS_CHECK(imports == 1);
            [self shot:@"Folder"];
            break;
        case 7:
            [self.nav popToRootViewControllerAnimated:NO];
            NSLog(@"[harness] NEXT");
            break;
        case 8:
            [self shot:@"Library"];
            break;
        default:
            NSLog(@"[harness] PASS local pages navigation, first five/See All, album/folder songs, artist action and import entry");
            exit(0);
    }
    if (self.step == 2 || self.step == 4 || self.step == 6) {
        // The runner acknowledges after the navigation transition, without a time-based test assertion.
        NSLog(@"[harness] NEXT");
    }
}
@end

@interface PagesScene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation PagesScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    PagesApp *app = (id)UIApplication.sharedApplication.delegate;
    self.window = app.window;
    self.window.windowScene = (UIWindowScene *)scene;
    [self.window makeKeyAndVisible];
}
- (void)sceneDidBecomeActive:(UIScene *)scene {
    PagesApp *app = (id)UIApplication.sharedApplication.delegate;
    if (!app.step) [app advance];
}
@end

int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(PagesApp.class)); }
}
