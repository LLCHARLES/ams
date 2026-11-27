// Edit info in the simulator: EditInfoMenu.x and LocalFiles.m as the tweak compiles them, on a mock of
// Spotify's context menu sheet presented over a player that plays a local file. The script taps the row,
// which closes the menu and brings up the editor, then types, picks a cover, saves, opens it again,
// restores the file's info, and tries to swipe away unsaved changes. It logs PASS or FAIL for each step
// and `[harness] SHOT <name>` when the screen is worth a screenshot (build-sim.sh takes them).
#import <UIKit/UIKit.h>
#import "Shared/LocalFiles/LocalFiles.h"
#import "Shared/LocalFiles/LocalInfoLookup.h"
#import <objc/runtime.h>
#import "../../harness-wait.h"

static NSString *const kURI = @"spotify:local:Daft+Punk:Discovery:One+More+Time:320";
static int sg_failures;
static NSUInteger sg_searches, sg_covers;
static BOOL sg_holdSearch, sg_conflictingPresentation;
static BOOL sg_filesBoundaryChecked, sg_photosBoundaryChecked;

#define CHECK(what, cond) do { BOOL ok = (cond); if (!ok) sg_failures++; NSLog(@"[harness] %@ %@", ok ? @"PASS" : @"FAIL", what); } while (0)

// What EditInfoMenu.x reads of the player: the track playing, and that the menu is the player's.
@interface SGHarnessTrack : NSObject
@property (nonatomic, strong) id URI;
@end
@implementation SGHarnessTrack
@end
@interface SGHarnessState : NSObject
@property (nonatomic, strong) SGHarnessTrack *track;
@end
@implementation SGHarnessState
@end

id SGPlayerState(void) {
    SGHarnessState *state = [SGHarnessState new];
    state.track = [SGHarnessTrack new];
    state.track.URI = [NSURL URLWithString:kURI];
    return state;
}
NSString *SGURIString(id uri) {
    return [uri isKindOfClass:NSURL.class] ? [(NSURL *)uri absoluteString] : uri;
}
BOOL SGPlayerMenuIsPlayers(UIViewController *menu) {
    return YES;
}

// Spotify's context menu sheet, as far as the hook goes: a table whose layout runs the hook.
@interface _TtC24ContextMenu_InternalImpl25ContextMenuViewController : UIViewController <UITableViewDataSource>
@property (nonatomic, strong) UITableView *table;
@end
@implementation _TtC24ContextMenu_InternalImpl25ContextMenuViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.dataSource = self;
    [self.view addSubview:self.table];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 3;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = @[@"Add to playlist", @"Go to queue", @"Share"][(NSUInteger)indexPath.row];
    return cell;
}
@end

static BOOL visible(UIViewController *vc) {
    return vc.viewIfLoaded.window && !vc.transitionCoordinator && !vc.navigationController.transitionCoordinator;
}
#define STEP(condition, ...) do { HARNESS_AWAIT(condition); (__VA_ARGS__)(); } while (0)

static void shot(NSString *name) {
    NSLog(@"[harness] SHOT %@", name);
    if (![NSProcessInfo.processInfo.arguments containsObject:@"capture-shots"]) return;
    NSString *ack = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [CATransaction flush];
    NSLog(@"[harness] CAPTURE %@ %@", name, ack);
    HARNESS_AWAIT([NSFileManager.defaultManager fileExistsAtPath:ack]);
    HARNESS_CHECK([NSFileManager.defaultManager removeItemAtPath:ack error:nil]);
}

static UIImage *redSquare(void) {
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(300, 300)] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [UIColor.systemRedColor setFill];
        UIRectFill(CGRectMake(0, 0, 300, 300));
    }];
}

// All requests, including accidental ones, terminate here. The harness never reaches the network.
@interface SGInfoFixtureProtocol : NSURLProtocol
@property(atomic) BOOL stopped;
- (void)finishLoading;
@end
static SGInfoFixtureProtocol *sg_pendingSearch;
@implementation SGInfoFixtureProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    dispatch_async(dispatch_get_main_queue(), ^{
    if ([self.request.URL.host isEqual:@"itunes.apple.com"]) {
        ++sg_searches;
        if (sg_holdSearch) { sg_pendingSearch = self; return; }
    } else ++sg_covers;
    [self finishLoading];
    });
}
- (void)finishLoading {
    if (self.stopped) return;
    NSData *data;
    if ([self.request.URL.host isEqual:@"itunes.apple.com"]) {
        data = [NSJSONSerialization dataWithJSONObject:@{@"results": @[
            @{@"trackName": @"One More Time", @"artistName": @"Daft Punk", @"collectionName": @"Discovery (Remastered)",
              @"trackTimeMillis": @320000, @"releaseDate": @"2001-03-12T00:00:00Z", @"artworkUrl100": @"https://is1-ssl.mzstatic.com/100x100bb.png"},
            @{@"trackName": @"One More Time (Radio Edit)", @"artistName": @"Daft Punk", @"collectionName": @"Discovery",
              @"trackTimeMillis": @319000, @"releaseDate": @"2001-03-12T00:00:00Z", @"artworkUrl100": @"https://is1-ssl.mzstatic.com/100x100bb.png"}
        ]} options:0 error:nil];
    } else {
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.scale = 1;
        UIImage *large = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(1600, 1600) format:format]
            imageWithActions:^(UIGraphicsImageRendererContext *context) {
                [UIColor.systemRedColor setFill];
                UIRectFill(CGRectMake(0, 0, 1600, 1600));
            }];
        data = UIImagePNGRepresentation(large);
    }
    [self.client URLProtocol:self didReceiveResponse:[[NSHTTPURLResponse alloc] initWithURL:self.request.URL
        statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{}] cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading { self.stopped = YES; }
@end

static void installInfoFixture(void) {
    Method method = class_getClassMethod(NSURLSessionConfiguration.class, @selector(ephemeralSessionConfiguration));
    IMP original = method_getImplementation(method);
    method_setImplementation(method, imp_implementationWithBlock(^id(id cls) {
        NSURLSessionConfiguration *config = ((id (*)(id, SEL))original)(cls, @selector(ephemeralSessionConfiguration));
        config.protocolClasses = @[SGInfoFixtureProtocol.class];
        return config;
    }));
    Method presentation = class_getInstanceMethod(UIViewController.class, @selector(presentViewController:animated:completion:));
    IMP present = method_getImplementation(presentation);
    method_setImplementation(presentation, imp_implementationWithBlock(^(UIViewController *owner, UIViewController *next, BOOL animated, void (^completion)(void)) {
        // The OS-owned Files/Photos services may dismiss themselves on an empty simulator.
        // Keep their presentation boundary, but supply an in-process sheet so dismissing it
        // cannot accidentally dismiss the editor. Production still constructs each real picker.
        if ([next isKindOfClass:UIDocumentPickerViewController.class] || [next isKindOfClass:UIImagePickerController.class]) {
            BOOL cancelled = ![(SGLocalInfoLookup *)[owner valueForKey:@"infoLookup"] busy] &&
                ((UIBarButtonItem *)owner.toolbarItems[1]).enabled;
            if ([next isKindOfClass:UIDocumentPickerViewController.class]) {
                sg_filesBoundaryChecked = YES;
                CHECK(@"Files picker cancels lookup and re-enables Find Info", cancelled);
            } else {
                sg_photosBoundaryChecked = YES;
                CHECK(@"Photos picker cancels lookup and re-enables Find Info", cancelled);
            }
            next = [UIViewController new];
            next.view.backgroundColor = UIColor.systemBackgroundColor;
        }
        if (owner.presentedViewController && [next isKindOfClass:UINavigationController.class] &&
            [NSStringFromClass(((UINavigationController *)next).topViewController.class) isEqual:@"SGLocalInfoReview"])
            sg_conflictingPresentation = YES;
        ((void (*)(id, SEL, id, BOOL, id))present)(owner, @selector(presentViewController:animated:completion:), next, animated, completion);
    }));
}

@interface UIViewController (InfoHarnessActions)
- (void)pickCoverFromFiles:(BOOL)files;
@end

@interface SGHarnessApp : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation SGHarnessApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyLocalFileEdits];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *player = [UIViewController new];
    player.view.backgroundColor = UIColor.blackColor;
    self.window.rootViewController = player;
    [self.window makeKeyAndVisible];
    HarnessWhen(@"player attached to active scene", ^BOOL {
        return player.view.window.windowScene.activationState == UISceneActivationStateForegroundActive && player.view.window.windowScene;
    }, ^{ [self runOn:player]; });
    return YES;
}

- (UIViewController *)editorOver:(UIViewController *)player {
    UINavigationController *navigation = (UINavigationController *)player.presentedViewController;
    if (![navigation isKindOfClass:UINavigationController.class]) return nil;
    UIViewController *editor = navigation.viewControllers.firstObject;
    return [NSStringFromClass(editor.class) isEqualToString:@"SGLocalFileEditor"] ? editor : nil;
}

- (void)runOn:(UIViewController *)player {
    if ([NSProcessInfo.processInfo.arguments containsObject:@"suggest"]) {
        installInfoFixture();
        [self runSuggestOn:player];
        return;
    }
    BOOL large = [NSProcessInfo.processInfo.arguments containsObject:@"large"];
    __block UIViewController *menu;
    STEP(visible(player), ^{
        menu = [_TtC24ContextMenu_InternalImpl25ContextMenuViewController new];
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:menu];
        navigation.navigationBarHidden = YES;
        navigation.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.mediumDetent];
        [player presentViewController:navigation animated:YES completion:nil];
    });
    STEP(visible(menu) && ((_TtC24ContextMenu_InternalImpl25ContextMenuViewController *)menu).table.tableFooterView != nil, ^{
        UIView *footer = ((_TtC24ContextMenu_InternalImpl25ContextMenuViewController *)menu).table.tableFooterView;
        CHECK(@"the menu has the Edit info row", [NSStringFromClass(footer.class) isEqualToString:@"SGEditInfoRow"]);
        UILabel *title = nil;
        for (UIView *view in footer.subviews) if ([view isKindOfClass:UILabel.class]) title = (UILabel *)view;
        UITraitCollection *traits = [UITraitCollection traitCollectionWithPreferredContentSizeCategory:
            large ? UIContentSizeCategoryExtraLarge : UIContentSizeCategoryLarge];
        UIFont *regular = [UIFont systemFontOfSize:
            [UIFont preferredFontForTextStyle:UIFontTextStyleBody compatibleWithTraitCollection:traits].pointSize];
        NSNumber *weight = [title.font.fontDescriptor objectForKey:UIFontDescriptorTraitsAttribute][UIFontWeightTrait];
        NSNumber *regularWeight = [regular.fontDescriptor objectForKey:UIFontDescriptorTraitsAttribute][UIFontWeightTrait];
        CHECK(@"Edit info uses regular Body text capped at Extra Large",
              title.font.pointSize == regular.pointSize && [weight isEqualToNumber:regularWeight]);
        shot(@"menu");
        [(UIControl *)footer sendActionsForControlEvents:UIControlEventTouchUpInside];
    });
    STEP(visible([self editorOver:player]), ^{
        UIViewController *editor = [self editorOver:player];
        CHECK(@"the menu closed and the editor came up over the player", editor != nil);
        CHECK(@"the editor is dark", editor.navigationController.overrideUserInterfaceStyle == UIUserInterfaceStyleDark);
        NSArray<UITextField *> *fields = [editor valueForKey:@"fields"];
        CHECK(@"the fields show the file's names", [fields[0].text isEqualToString:@"One More Time"] && [fields[1].text isEqualToString:@"Daft Punk"]);
        CHECK(@"Save is off with nothing changed", !editor.navigationItem.rightBarButtonItem.enabled && !editor.modalInPresentation);
        shot(large ? @"editor-large" : @"editor");
        if (large) exit(sg_failures ? 1 : 0);
    });
    if (large) return;
    STEP(visible([self editorOver:player]), ^{
        UIViewController *editor = [self editorOver:player];
        NSArray<UITextField *> *fields = [editor valueForKey:@"fields"];
        fields[0].text = @"One More Time (Edit)";
        [fields[0] sendActionsForControlEvents:UIControlEventEditingChanged];
        CHECK(@"a typed name turns Save on and holds a swipe", editor.navigationItem.rightBarButtonItem.enabled && editor.modalInPresentation);
        [editor performSelector:@selector(useCover:) withObject:redSquare()];
        CHECK(@"a picked cover is not stored before Save", !SGLocalFileEditFor(kURI));
    });
    shot(@"edited");
    STEP(visible([self editorOver:player]), ^{
        UIViewController *editor = [self editorOver:player];
        UIBarButtonItem *save = editor.navigationItem.rightBarButtonItem;
        [[UIApplication sharedApplication] sendAction:save.action to:save.target from:save forEvent:nil];
        NSDictionary *edit = SGLocalFileEditFor(kURI);
        CHECK(@"Save stores the name and the cover", [edit[@"title"] isEqualToString:@"One More Time (Edit)"] && SGLocalFileCoverPath(edit));
        CHECK(@"the rename gives a new lyrics key", [SGLocalFileLyricsKey(kURI) containsString:@"#"]);
    });
    STEP(!player.presentedViewController && visible(player), ^{ SGLocalFilePresentEditor(player, kURI); });
    STEP(visible([self editorOver:player]), ^{
        UIViewController *editor = [self editorOver:player];
        NSArray<UITextField *> *fields = [editor valueForKey:@"fields"];
        UITableViewCell *restore = [editor valueForKey:@"restoreCell"];
        CHECK(@"opened again, it shows the edit and offers the restore", [fields[0].text isEqualToString:@"One More Time (Edit)"] && restore.userInteractionEnabled);
        shot(@"reopened");
    });
    STEP(visible([self editorOver:player]), ^{
        UIViewController *editor = [self editorOver:player];
        NSArray<UITextField *> *fields = [editor valueForKey:@"fields"];
        UITableViewCell *restore = [editor valueForKey:@"restoreCell"];
        [(UITableViewController *)editor tableView:[(UITableViewController *)editor tableView] didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:2]];
        CHECK(@"Restore puts the file's names back, unsaved", [fields[0].text isEqualToString:@"One More Time"] && SGLocalFileEditFor(kURI)
              && editor.navigationItem.rightBarButtonItem.enabled && !restore.userInteractionEnabled);
        UIBarButtonItem *save = editor.navigationItem.rightBarButtonItem;
        [[UIApplication sharedApplication] sendAction:save.action to:save.target from:save forEvent:nil];
        CHECK(@"saved, the edit and its cover are gone", !SGLocalFileEditFor(kURI) && [SGLocalFileLyricsKey(kURI) isEqualToString:kURI]);
    });
    STEP(!player.presentedViewController && visible(player), ^{ SGLocalFilePresentEditor(player, kURI); });
    STEP(visible([self editorOver:player]), ^{
        UIViewController *editor = [self editorOver:player];
        NSArray<UITextField *> *fields = [editor valueForKey:@"fields"];
        UITableViewCell *restore = [editor valueForKey:@"restoreCell"];
        CHECK(@"with no edit, Restore is off", !restore.userInteractionEnabled);
        fields[2].text = @"Homework";
        [fields[2] sendActionsForControlEvents:UIControlEventEditingChanged];
        [(id<UIAdaptivePresentationControllerDelegate>)editor presentationControllerDidAttemptToDismiss:editor.navigationController.presentationController];
    });
    STEP(visible([self editorOver:player].presentedViewController), ^{
        UIViewController *editor = [self editorOver:player];
        UIAlertController *confirm = (UIAlertController *)editor.presentedViewController;
        CHECK(@"a swipe away with changes asks first", [confirm isKindOfClass:UIAlertController.class] && confirm.preferredStyle == UIAlertControllerStyleActionSheet
              && [confirm.actions.firstObject.title isEqualToString:@"Discard changes"]);
        shot(@"discard");
    });
    NSLog(@"[harness] %@: %d failed", sg_failures ? @"FAIL" : @"PASS", sg_failures);
    exit(sg_failures ? 1 : 0);
}

- (UITableViewController *)reviewOver:(UIViewController *)editor {
    UINavigationController *nav = (id)editor.presentedViewController;
    if (![nav isKindOfClass:UINavigationController.class]) return nil;
    return (id)nav.viewControllers.firstObject;
}

- (void)runSuggestOn:(UIViewController *)player {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyLocalFileSuggest];
    SGLocalFilePresentEditor(player, kURI);
    STEP(visible([self editorOver:player]), ^{
        [self editorOver:player].navigationController.sheetPresentationController.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge;
    });
    STEP(visible([self editorOver:player]), ^{
        UIViewController *editor = [self editorOver:player];
        CHECK(@"Find Info is default on and makes no automatic request", editor.toolbarItems.count == 3 && sg_searches == 0);
        shot(@"find-info");
        [editor performSelector:@selector(findInfo)];
        [editor performSelector:@selector(findInfo)];
    });
    STEP(visible([self reviewOver:[self editorOver:player]]), ^{
        UIViewController *editor = [self editorOver:player];
        UITableViewController *review = [self reviewOver:editor];
        CHECK(@"one search and review, no eager cover download", review && sg_searches == 1 && sg_covers == 0);
        if (!review) { NSLog(@"[harness] FAIL missing review"); exit(1); }
        NSIndexPath *album = [NSIndexPath indexPathForRow:2 inSection:0];
        NSIndexPath *title = [NSIndexPath indexPathForRow:0 inSection:0];
        CHECK(@"only differing fields checked", [review tableView:review.tableView cellForRowAtIndexPath:album].accessoryType == UITableViewCellAccessoryCheckmark &&
            [review tableView:review.tableView cellForRowAtIndexPath:title].accessoryType == UITableViewCellAccessoryNone);
        shot(@"review-best");
        STEP(visible(review), ^{
            [review tableView:review.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:0]];
            [review tableView:review.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
            CHECK(@"Other Matches preserves unchecked Cover", [review tableView:review.tableView cellForRowAtIndexPath:
                [NSIndexPath indexPathForRow:3 inSection:0]].accessoryType == UITableViewCellAccessoryNone);
        });
    });
    STEP(visible([self reviewOver:[self editorOver:player]]), ^{
        UIViewController *editor = [self editorOver:player];
        UITableViewController *review = [self reviewOver:editor];
        shot(@"review-other");
        [review performSelector:@selector(reject)];
        CHECK(@"Not This Song never saves", !SGLocalFileEditFor(kURI));
    });
    STEP(![self editorOver:player].presentedViewController && visible([self editorOver:player]), ^{
        UIViewController *editor = [self editorOver:player];
        CHECK(@"reject leaves editor unchanged", !editor.navigationItem.rightBarButtonItem.enabled);
        [editor performSelector:@selector(findInfo)];
    });
    STEP(visible([self reviewOver:[self editorOver:player]]), ^{
        UIViewController *editor = [self editorOver:player];
        UITableViewController *review = [self reviewOver:editor];
        [review tableView:review.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:0]];
        [review performSelector:@selector(use)];
    });
    STEP(![self editorOver:player].presentedViewController && visible([self editorOver:player]), ^{
        UIViewController *editor = [self editorOver:player];
        NSArray<UITextField *> *fields = [editor valueForKey:@"fields"];
        CHECK(@"Use only fills selected fields; no overlay write", [fields[0].text isEqual:@"One More Time"] &&
            [fields[2].text isEqual:@"Discovery (Remastered)"] && !SGLocalFileEditFor(kURI) && sg_covers == 0);
        CHECK(@"accepted values retain dirty/discard guard", editor.modalInPresentation && editor.navigationItem.rightBarButtonItem.enabled);
        shot(@"accepted-unsaved");
        STEP(editor.navigationItem.rightBarButtonItem.enabled, ^{
            [editor performSelector:@selector(save)];
            CHECK(@"existing Save publishes the URI-keyed overlay", [SGLocalFileEditFor(kURI)[@"album"] isEqual:@"Discovery (Remastered)"]);
        });
    });
    STEP(!player.presentedViewController && visible(player), ^{ SGLocalFilePresentEditor(player, kURI); });
    STEP(visible([self editorOver:player]), ^{
        [self editorOver:player].navigationController.sheetPresentationController.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge;
        [[self editorOver:player] performSelector:@selector(findInfo)];
    });
    STEP(visible([self reviewOver:[self editorOver:player]]), ^{ [[self reviewOver:[self editorOver:player]] performSelector:@selector(use)]; });
    STEP(![self editorOver:player].presentedViewController && [[self editorOver:player] valueForKey:@"cover"] != nil, ^{
        UIViewController *editor = [self editorOver:player];
        UIImage *cover = [editor valueForKey:@"cover"];
        CHECK(@"Use downloads cover only on demand, fills picked cover without saving", sg_covers == 1 && cover &&
            MAX(cover.size.width, cover.size.height) == 1200 && !SGLocalFileEditFor(kURI)[@"cover"]);
        shot(@"accepted-cover");
        STEP(visible(editor) && editor.navigationItem.rightBarButtonItem.enabled, ^{
            [editor performSelector:@selector(save)];
            CHECK(@"Save sends picked cover through existing cover store", SGLocalFileEditFor(kURI)[@"cover"] != nil);
        });
    });
    STEP(!player.presentedViewController && visible(player), ^{
        [NSUserDefaults.standardUserDefaults setBool:NO forKey:SGKeyLocalFileSuggest];
        SGLocalFilePresentEditor(player, kURI);
    });
    STEP(visible([self editorOver:player]), ^{
        UIViewController *editor = [self editorOver:player];
        CHECK(@"off hides Find Info", editor.toolbarItems.count == 0);
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyLocalFileSuggest];
        SGLocalFileSaveEdit(kURI, @{}, nil, NO);
        [editor dismissViewControllerAnimated:YES completion:nil];
    });
    STEP(!player.presentedViewController && visible(player), ^{ SGLocalFilePresentEditor(player, kURI); });
    STEP(visible([self editorOver:player]), ^{
        UIViewController *editor = [self editorOver:player];
        ((UITextField *)[editor valueForKey:@"fields"][0]).text = @"Pending Files";
        sg_holdSearch = YES;
        [editor performSelector:@selector(findInfo)];
    });
    STEP(sg_pendingSearch != nil, ^{ [[self editorOver:player] pickCoverFromFiles:YES]; });
    STEP(visible([self editorOver:player].presentedViewController), ^{
        UIViewController *editor = [self editorOver:player];
        [editor dismissViewControllerAnimated:YES completion:nil];
    });
    STEP(![self editorOver:player].presentedViewController && visible([self editorOver:player]), ^{
        UIViewController *editor = [self editorOver:player];
        sg_pendingSearch = nil;
        ((UITextField *)[editor valueForKey:@"fields"][0]).text = @"Pending Photos";
        [editor performSelector:@selector(findInfo)];
    });
    STEP(sg_pendingSearch != nil, ^{ [[self editorOver:player] pickCoverFromFiles:NO]; });
    STEP(visible([self editorOver:player].presentedViewController), ^{
        UIViewController *editor = [self editorOver:player];
        [editor dismissViewControllerAnimated:YES completion:nil];
    });
    STEP(![self editorOver:player].presentedViewController && visible([self editorOver:player]), ^{
        UIViewController *editor = [self editorOver:player];
        sg_pendingSearch = nil;
        ((UITextField *)[editor valueForKey:@"fields"][0]).text = @"Blocked Review";
        [editor performSelector:@selector(findInfo)];
        [editor performSelector:@selector(cancel)]; // dirty editor presents its real discard/keep-editing guard
    });
    STEP(sg_pendingSearch && visible([self editorOver:player].presentedViewController), ^{
        CHECK(@"pending lookup reaches discard confirmation race", sg_pendingSearch && !sg_pendingSearch.stopped);
        [sg_pendingSearch finishLoading];
    });
    STEP(((UIBarButtonItem *)[self editorOver:player].toolbarItems[1]).enabled, ^{
        UIViewController *editor = [self editorOver:player];
        CHECK(@"both picker presentation boundaries were exercised", sg_filesBoundaryChecked && sg_photosBoundaryChecked);
        CHECK(@"answer behind another controller is dropped and button reset", !sg_conflictingPresentation &&
            ((UIBarButtonItem *)editor.toolbarItems[1]).enabled && [editor.presentedViewController isKindOfClass:UIAlertController.class]);
        sg_holdSearch = NO;
        sg_pendingSearch = nil;
        NSLog(@"[harness] %@: %d failed", sg_failures ? @"FAIL" : @"PASS", sg_failures);
        exit(sg_failures ? 1 : 0);
    });
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGHarnessApp.class));
    }
}
