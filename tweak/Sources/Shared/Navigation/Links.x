// The dispatcher is a singleton the app builds at startup; -setMainUILoaded: is the last call of its
// setup (objc-methods.txt:38809).
#import "Core/SGCore.h"
#import "Headers/SPTLinkDispatcherImplementation.h"
#import "Links.h"
#import "InboundLinks.h"
#import <objc/message.h>
#import <objc/runtime.h>

static __weak SPTLinkDispatcherImplementation *sg_linkDispatcher;
static SGInboundLinks *sg_inboundLinks;
static char sg_consumedContextsKey, sg_consumedActivitiesKey;

static BOOL acceptInbound(NSURL *url) {
    return [sg_inboundLinks acceptURL:url];
}

id SGLinkDispatcher(void) {
    return sg_linkDispatcher;
}

// 9.1.88 dropped -navigateToURI:options:interactionID:. In 9.1.78 it only wraps
// -navigateToURI:options:reason:completionHandler:resultHandler:, which every version has, with the reason
// [[SPTUBINavigationReason alloc] initWithSourceApplication:nil interactionID:<its interactionID>] and no handlers
// (read off the 9.1.78 binary), so later versions get the same. A nil reason crashes: Swift reads it as an enum.
BOOL SGOpenSpotifyURI(NSURL *uri) {
    SPTLinkDispatcherImplementation *dispatcher = sg_linkDispatcher;
    if (!uri || !dispatcher) return NO;
    if ([dispatcher respondsToSelector:@selector(navigateToURI:options:interactionID:)]) {
        [dispatcher navigateToURI:uri options:0 interactionID:nil];
        return YES;
    }
    SEL full = NSSelectorFromString(@"navigateToURI:options:reason:completionHandler:resultHandler:");
    // alloc and init by hand, outside ARC: init consumes what alloc made and returns its own +1.
    Class reasonClass = NSClassFromString(@"SPTUBINavigationReason");
    SEL init = NSSelectorFromString(@"initWithSourceApplication:interactionID:");
    id reason = nil;
    if ([reasonClass instancesRespondToSelector:init]) {
        void *raw = ((void *(*)(Class, SEL))objc_msgSend)(reasonClass, @selector(alloc));
        reason = CFBridgingRelease(((void *(*)(void *, SEL, id, id))objc_msgSend)(raw, init, nil, nil));
    }
    if (![dispatcher respondsToSelector:full] || !reason) return NO;
    ((void (*)(id, SEL, NSURL *, long long, id, id, id))objc_msgSend)(dispatcher, full, uri, 0, reason, nil, nil);
    return YES;
}

#pragma mark - asking before opening

// The chain a spotify: link takes in 9.1.78, read off the binary: -[SPTLinkDispatcherImplementation
// navigateToURI:…] hands it to the URI scheme dispatcher, whose "spotify" handler is the dispatcher's
// -spotifyLinkHandler (SPTSpotifyLinkHandler). That one passes the cleaned URI to its
// -URISubtypeRegistry (SPTURISubtypeRegistryImplementation), which keeps the handlers of its -handlers
// hash table that answer -URISubtypeHandlerCanHandleURI: YES and opens with the first by priority;
// pages go through Navigation's PageResolverURISubtypeHandler. With no taker, -handleSpotifyURL:
// tries again once with -remapURI: (its fallback resolver's URI), and only then shows the alert.
static id sg_send(id target, NSString *selector) {
    SEL sel = NSSelectorFromString(selector);
    if (![target respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(target, sel);
}

static id sg_send1(id target, NSString *selector, id arg) {
    SEL sel = NSSelectorFromString(selector);
    if (![target respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL, id))objc_msgSend)(target, sel, arg);
}

// The class of the first handler that takes `uri`, nil for none. A handler whose name says it only
// listens (Jam's SGSNavigationURIHandledEventSource) is not asked, so a question is not taken for a
// navigation.
static NSString *takerFor(id<NSFastEnumeration> handlers, NSURL *uri, NSUInteger *asked) {
    SEL canHandle = NSSelectorFromString(@"URISubtypeHandlerCanHandleURI:");
    for (id handler in handlers) {
        NSString *name = NSStringFromClass([handler class]);
        if ([name containsString:@"EventSource"] || ![handler respondsToSelector:canHandle]) continue;
        (*asked)++;
        if (((BOOL (*)(id, SEL, id))objc_msgSend)(handler, canHandle, uri)) return name;
    }
    return nil;
}

SGLinkRoute SGSpotifyURIRoute(NSURL *uri, NSString **via) {
    if (via) *via = nil;
    if (!uri) return SGLinkRouteNone;
    id linkHandler = sg_send(sg_linkDispatcher, @"spotifyLinkHandler");
    id handlers = sg_send(sg_send(linkHandler, @"URISubtypeRegistry"), @"handlers");
    if (![handlers conformsToProtocol:@protocol(NSFastEnumeration)]) return SGLinkRouteUnknown;
    @try {
        NSURL *clean = sg_send(uri, @"spt_normalizedSpotifyURI");
        if (![clean isKindOfClass:NSURL.class]) clean = uri;
        NSUInteger asked = 0;
        NSString *taker = takerFor(handlers, clean, &asked);
        if (!taker) {
            NSURL *remapped = sg_send1(linkHandler, @"remapURI:", clean);
            if ([remapped isKindOfClass:NSURL.class] && ![remapped isEqual:clean]) {
                taker = takerFor(handlers, remapped, &asked);
                if (taker) taker = [NSString stringWithFormat:@"remap %@ %@", remapped.absoluteString, taker];
            }
        }
        if (!asked) return SGLinkRouteUnknown;
        if (via) *via = taker;
        return taker ? SGLinkRouteOpens : SGLinkRouteNone;
    } @catch (NSException *e) {
        SGLog(@"links: asking about %@ threw %@", uri, e.reason);
        return SGLinkRouteUnknown;
    }
}

// Authentication and accessory callbacks use Spotify's other schemes; their existing handlers stay.
static BOOL isInboundLink(NSURL *url) {
    // Continue accepting handoffs from before the rename.
    return [@[@"spotify", @"retrine", @"vitrine", @"https", @"http"] containsObject:url.scheme.lowercaseString];
}

static BOOL isRegisteredCallback(NSURL *url) {
    for (NSDictionary *type in NSBundle.mainBundle.infoDictionary[@"CFBundleURLTypes"])
        for (NSString *scheme in type[@"CFBundleURLSchemes"])
            if ([scheme.lowercaseString isEqualToString:url.scheme.lowercaseString]) return YES;
    return NO;
}

static BOOL (*originalOpenURL)(id, SEL, UIApplication *, NSURL *, NSDictionary *);
static BOOL inboundOpenURL(id self, SEL cmd, UIApplication *app, NSURL *url, NSDictionary *options) {
    if (isInboundLink(url)) return acceptInbound(url);
    return isRegisteredCallback(url) && originalOpenURL(self, cmd, app, url, options);
}

static BOOL (*originalActivity)(id, SEL, UIApplication *, NSUserActivity *, id);
static BOOL inboundActivity(id self, SEL cmd, UIApplication *app, NSUserActivity *activity, id restore) {
    if ([activity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb]) return acceptInbound(activity.webpageURL);
    return originalActivity(self, cmd, app, activity, restore);
}

static NSSet<UIOpenURLContext *> *consumeLinkContexts(NSSet<UIOpenURLContext *> *contexts) {
    NSMutableSet *callbacks = [NSMutableSet set];
    for (UIOpenURLContext *context in contexts) {
        NSURL *url = context.URL;
        if (isInboundLink(url)) acceptInbound(url);
        else if (isRegisteredCallback(url)) [callbacks addObject:context];
    }
    return callbacks;
}

static void replaceDelegateMethod(Class cls, SEL sel, IMP replacement, IMP *original) {
    if (*original) return;
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) return;
    *original = method_getImplementation(method);
    if (!class_addMethod(cls, sel, replacement, method_getTypeEncoding(method)))
        class_replaceMethod(cls, sel, replacement, method_getTypeEncoding(method));
}

%hook UIApplication
- (void)setDelegate:(id)delegate {
    if (delegate) {
        Class cls = object_getClass(delegate);
        replaceDelegateMethod(cls, @selector(application:openURL:options:), (IMP)inboundOpenURL, (IMP *)&originalOpenURL);
        replaceDelegateMethod(cls, @selector(application:continueUserActivity:restorationHandler:), (IMP)inboundActivity, (IMP *)&originalActivity);
    }
    %orig;
}
%end

// A cold scene receives its links in connection options, before the dispatcher is necessarily ready.
%hook UISceneConnectionOptions
- (NSSet<UIOpenURLContext *> *)URLContexts {
    NSSet *consumed = objc_getAssociatedObject(self, &sg_consumedContextsKey);
    if (consumed) return consumed;
    NSSet *contexts = %orig;
    NSSet *callbacks = consumeLinkContexts(contexts);
    objc_setAssociatedObject(self, &sg_consumedContextsKey, callbacks, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return callbacks;
}
- (NSSet<NSUserActivity *> *)userActivities {
    NSSet *consumed = objc_getAssociatedObject(self, &sg_consumedActivitiesKey);
    if (consumed) return consumed;
    NSSet *activities = %orig;
    NSMutableSet *remaining = [NSMutableSet set];
    for (NSUserActivity *activity in activities) {
        if ([activity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb]) acceptInbound(activity.webpageURL);
        else [remaining addObject:activity];
    }
    objc_setAssociatedObject(self, &sg_consumedActivitiesKey, remaining, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return remaining;
}
%end

%hook SPTLinkDispatcherImplementation
- (void)setMainUILoaded:(BOOL)loaded {
    %orig;
    sg_linkDispatcher = (SPTLinkDispatcherImplementation *)self;
    [sg_inboundLinks setReady:loaded];
}

%end

// UIKit installs Spotify's scene delegate without calling UIScene.setDelegate:.
@interface SGSpotifySceneDelegate : UIResponder <UIWindowSceneDelegate>
@end

%group SGSceneLinks
%hook SGSpotifySceneDelegate
- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)contexts {
    NSSet *callbacks = consumeLinkContexts(contexts);
    if (callbacks.count) %orig(scene, callbacks);
}
- (void)scene:(UIScene *)scene continueUserActivity:(NSUserActivity *)activity {
    if ([activity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb]) acceptInbound(activity.webpageURL);
    else %orig;
}
%end
%end

%ctor {
    if (!SGSupportsSpotifyLinkDispatch(NSClassFromString(@"SPTLinkDispatcherImplementation"),
                                      NSClassFromString(@"SPTUBINavigationReason"))) {
        SGLog(@"links: dispatcher unsupported; original inbound handlers retained");
        return;
    }
    sg_inboundLinks = [[SGInboundLinks alloc] initWithResolver:^id<SGLinkCancellation>(NSURL *url, SGLinkResolved completion) {
        return SGResolveSpotifyPublicLink(url, completion);
    } opener:^BOOL(NSURL *url) { return SGOpenSpotifyURI(url); }];
    %init;
    %init(SGSceneLinks, SGSpotifySceneDelegate = NSClassFromString(@"MusicApp_ContainerWiring.SpotifySceneDelegate"));
    SGRequireClasses(@[@"SPTLinkDispatcherImplementation"]);
}
