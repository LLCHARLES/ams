#import "TrackMenu.h"
#import "NativeAdmission.h"
#import "TrackDownload.h"
#import "Localization.h"
#import <objc/runtime.h>
#import <stdatomic.h>
#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

// The 9.1.90 legacy adapter builds the shared Spotify sheet. Its track factory
// has an explicit selected NSURL and NSString, unlike ContextMenuViewController,
// whose ObjC metadata exposes no selected track. No player, KVC or timing lookup.
// Class: _TtC37ContextMenu_PlatformLegacyAdapterImpl16PresenterFactory.
// Track factory IMP 0x10655389c; generic entity factory IMP 0x103ed4e34.
// SPTContextMenuAction protocol: title @16@0:8, performAction @16@0:8;
// optional iconImage/accessibilityIdentifier @16@0:8, isDisabled B16@0:8.
// SPTShowEntityContextMenuAction.performAction (0x1041971fc) permits nil.

@interface SAPTrackMenuAction : NSObject {
    atomic_bool _used;
}
@property(nonatomic,copy) NSString *uri, *trackTitle;
- (NSString *)title;
- (id)performAction;
@end

#if TARGET_OS_IPHONE
static void menuMessage(NSString *message) {
    static __weak UIAlertController *shown;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (shown.presentingViewController) { shown.message = message; return; }
        UIWindow *window = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive ||
                ![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *candidate in ((UIWindowScene *)scene).windows)
                if (candidate.isKeyWindow) { window = candidate; break; }
            if (window) break;
        }
        UIViewController *presenter = window.rootViewController;
        while (presenter.presentedViewController) presenter = presenter.presentedViewController;
        if (!presenter) return;
        // The native action may run during the sheet's dismissal. Wait for its
        // actual transition rather than silently dropping a rejection message.
        if (presenter.isBeingDismissed && presenter.transitionCoordinator) {
            [presenter.transitionCoordinator animateAlongsideTransition:nil
                completion:^(id<UIViewControllerTransitionCoordinatorContext> context) { menuMessage(message); }];
            return;
        }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:
            SAPL(@"settings.pixie.manager.title",@"Pixie Download Manager") message:message
            preferredStyle:UIAlertControllerStyleAlert];
        alert.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        [alert addAction:[UIAlertAction actionWithTitle:SAPL(@"common.ok",@"OK")
            style:UIAlertActionStyleDefault handler:nil]];
        shown = alert;
        [presenter presentViewController:alert animated:YES completion:nil];
    });
}
#else
static void menuMessage(NSString *message) {}
#endif

@implementation SAPTrackMenuAction
- (instancetype)init {
    if ((self = [super init])) atomic_init(&_used, false);
    return self;
}
- (NSString *)title { return SAPL(@"settings.pixie.menu.download",@"Download"); }
- (NSString *)accessibilityIdentifier { return @"spotifyglass.pixie.downloadTrack"; }
- (BOOL)isDisabled { return atomic_load(&_used) || SAPTrackDownloadActive(); }
- (id)performAction {
    if (!atomic_exchange(&_used, true)) SAPDownloadTrack(self.uri, self.trackTitle, ^(NSString *message) {
        menuMessage(message);
    });
    return nil;
}
#if TARGET_OS_IPHONE
- (UIImage *)iconImage { return [UIImage systemImageNamed:@"arrow.down.circle"]; }
#endif
@end

static NSArray *actionsForTrack(id uri, id title, id actions) {
    NSString *value = [uri isKindOfClass:NSURL.class] ? [uri absoluteString] :
                      [uri isKindOfClass:NSString.class] ? uri : nil;
    if (actions && ![actions isKindOfClass:NSArray.class]) return actions;
    // Some callers reuse their input array. Never duplicate or retarget our
    // previously captured action; a fresh presenter gets a fresh one-shot action.
    NSMutableArray *result = [NSMutableArray array];
    for (id action in actions) if (![action isKindOfClass:SAPTrackMenuAction.class]) [result addObject:action];
    if (!SAPIsMusicTrackURI(value)) return result.count == [actions count] ? actions : [result copy];
    SAPTrackMenuAction *action = [SAPTrackMenuAction new];
    action.uri = value;
    action.trackTitle = [title isKindOfClass:NSString.class] ? title : nil;
    [result addObject:action];
    return [result copy];
}

void SAPInstallTrackMenu(void) {
    if(!SAPRuntimeProfileAdmitted())return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Protocol *protocol = NSProtocolFromString(@"SPTContextMenuAction");
        if (!protocol) return;
        class_addProtocol(SAPTrackMenuAction.class, protocol);
        Class cls = NSClassFromString(@"_TtC37ContextMenu_PlatformLegacyAdapterImpl16PresenterFactory");
        SEL track = NSSelectorFromString(@"contextMenuPresenterForTrackWithTrackURI:trackName:trackMetadata:playable:imageURL:artists:albumName:albumURI:viewURI:contextSourceURI:metadataTitle:logContext:options:actions:");
        Method method = class_getInstanceMethod(cls, track);
        if (method && !strcmp(method_getTypeEncoding(method),
            "@124@0:8@16@24@32B40@44@52@60@68@76@84@92@100@108@116")) {
            IMP original = method_getImplementation(method);
            class_replaceMethod(cls, track, imp_implementationWithBlock(^id(id receiver,
                id uri, id name, id metadata, BOOL playable, id image, id artists,
                id album, id albumURI, id viewURI, id contextURI, id metadataTitle,
                id logContext, id options, id actions) {
                return ((id (*)(id, SEL, id, id, id, BOOL, id, id, id, id, id, id, id, id, id, id))original)(
                    receiver, track, uri, name, metadata, playable, image, artists, album,
                    albumURI, viewURI, contextURI, metadataTitle, logContext, options,
                    actionsForTrack(uri, name, actions));
            }), method_getTypeEncoding(method));
        }
        SEL entity = NSSelectorFromString(@"contextMenuPresenterForHeaderImageURL:headerImagePlaceholder:imageStyle:title:subtitle:metadataTitle:actions:entityURL:options:");
        method = class_getInstanceMethod(cls, entity);
        if (method && !strcmp(method_getTypeEncoding(method), "@88@0:8@16@24q32@40@48@56@64@72@80")) {
            IMP original = method_getImplementation(method);
            class_replaceMethod(cls, entity, imp_implementationWithBlock(^id(id receiver,
                id image, id placeholder, NSInteger style, id title, id subtitle,
                id metadataTitle, id actions, id uri, id options) {
                return ((id (*)(id, SEL, id, id, NSInteger, id, id, id, id, id, id))original)(
                    receiver, entity, image, placeholder, style, title, subtitle,
                    metadataTitle, actionsForTrack(uri, title, actions), uri, options);
            }), method_getTypeEncoding(method));
        }
    });
}
