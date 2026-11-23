#import <Foundation/Foundation.h>
#import "LinkURL.h"
#import "InboundLinks.h"

@interface PendingRequest : NSObject <SGLinkCancellation>
@property (nonatomic) BOOL cancelled;
@end
@implementation PendingRequest
- (void)cancel { self.cancelled = YES; }
@end

@interface LegacyDispatcher : NSObject
@end
@implementation LegacyDispatcher
- (void)setMainUILoaded:(BOOL)loaded {}
- (void)navigateToURI:(id)uri options:(long long)options interactionID:(id)interaction {}
@end
@interface ModernDispatcher : NSObject
@end
@implementation ModernDispatcher
- (void)setMainUILoaded:(BOOL)loaded {}
- (void)navigateToURI:(id)uri options:(long long)options reason:(id)reason completionHandler:(id)completion resultHandler:(id)result {}
@end
@interface MissingReadiness : NSObject
@end
@implementation MissingReadiness
- (void)navigateToURI:(id)uri options:(long long)options interactionID:(id)interaction {}
@end
@interface NavigationReason : NSObject
@end
@implementation NavigationReason
- (id)initWithSourceApplication:(id)source interactionID:(id)interaction { return [super init]; }
@end

static BOOL supersession(void) {
    NSString *album = @"spotify:album:4yP0hdKOZPNshxUOjY0cZj";
    NSArray *cases = @[
        @[@"direct", album, @[album]],
        @[@"invalid", @"vitrine:internal:startgroupsession", @[]],
        @[@"short", @"https://spotify.app.link/new", @[album]],
        @[@"queued", album, @[album]],
        @[@"cold", album, @[album]],
    ];
    for (NSArray *test in cases) {
        NSMutableArray<SGLinkResolved> *replies = [NSMutableArray array];
        NSMutableArray<PendingRequest *> *requests = [NSMutableArray array];
        NSMutableArray<NSString *> *opened = [NSMutableArray array];
        SGInboundLinks *links = [[SGInboundLinks alloc] initWithResolver:^id<SGLinkCancellation>(NSURL *url, SGLinkResolved reply) {
            [replies addObject:[reply copy]];
            PendingRequest *request = [PendingRequest new];
            [requests addObject:request];
            return request;
        } opener:^BOOL(NSURL *url) { [opened addObject:url.absoluteString]; return YES; }];
        BOOL cold = [test[0] isEqual:@"cold"];
        [links setReady:!cold];
        [links acceptURL:[NSURL URLWithString:cold ? @"spotify:track:0sf12qNH5qcw8qpgymFOqD" : @"https://spotify.link/old"]];
        if ([test[0] isEqual:@"queued"])
            replies[0]([NSURL URLWithString:@"https://open.spotify.com/track/0sf12qNH5qcw8qpgymFOqD"], nil);
        [links acceptURL:[NSURL URLWithString:test[1]]];
        if (cold) {
            [links setReady:YES];
        } else {
            if (!requests[0].cancelled) {
                NSLog(@"FAIL supersede %@: old request was not cancelled", test[0]);
                return NO;
            }
            if ([test[0] isEqual:@"short"])
                replies[1]([NSURL URLWithString:@"https://open.spotify.com/album/4yP0hdKOZPNshxUOjY0cZj"], nil);
            if (![test[0] isEqual:@"queued"])
                replies[0]([NSURL URLWithString:@"https://open.spotify.com/track/0sf12qNH5qcw8qpgymFOqD"], nil);
        }
        __block BOOL drained = NO;
        dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; CFRunLoopStop(CFRunLoopGetMain()); });
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 5, false);
        if (!drained || ![opened isEqual:test[2]]) {
            NSLog(@"FAIL supersede %@: opened %@", test[0], opened);
            return NO;
        }
    }
    return YES;
}

int main(void) {
    @autoreleasepool {
        // Each row states the external-input contract, not the app's trusted tab-navigation grammar.
        NSArray *cases = @[
            @[@"url", @"vitrine:track:0sf12qNH5qcw8qpgymFOqD", @"spotify:track:0sf12qNH5qcw8qpgymFOqD"],
            @[@"url", @"retrine:track:0sf12qNH5qcw8qpgymFOqD", @"spotify:track:0sf12qNH5qcw8qpgymFOqD"],
            @[@"url", @"vitrine://track/0sf12qNH5qcw8qpgymFOqD", @"spotify:track:0sf12qNH5qcw8qpgymFOqD"],
            @[@"url", @"vitrine://https://open.spotify.com/album/4yP0hdKOZPNshxUOjY0cZj?si=x", @"spotify:album:4yP0hdKOZPNshxUOjY0cZj"],
            @[@"url", @"vitrine://open.spotify.com/track/0sf12qNH5qcw8qpgymFOqD", @"spotify:track:0sf12qNH5qcw8qpgymFOqD"],
            @[@"url", @"https://open.spotify.com/intl-ko/playlist/37i9dQZF1DWVmX5LMTOKPw?si=x", @"spotify:playlist:37i9dQZF1DWVmX5LMTOKPw"],
            @[@"url", @"spotify:artist:0sf12qNH5qcw8qpgymFOqD", @"spotify:artist:0sf12qNH5qcw8qpgymFOqD"],
            @[@"url", @"spotify:show:0sf12qNH5qcw8qpgymFOqD", @"spotify:show:0sf12qNH5qcw8qpgymFOqD"],
            @[@"url", @"spotify:episode:0sf12qNH5qcw8qpgymFOqD", @"spotify:episode:0sf12qNH5qcw8qpgymFOqD"],
            @[@"url", @"https://open.spotify.com/user/spotify", @"spotify:user:spotify"],
            @[@"url", @"spotify:user:old.name-123", @"spotify:user:old.name-123"],
            @[@"url", @"https://open.spotify.com/embed/track/0sf12qNH5qcw8qpgymFOqD?action=download&context=spotify:internal:x", @"spotify:track:0sf12qNH5qcw8qpgymFOqD"],
            @[@"url", @"spotify://eevee/open.spotify.com/track/0sf12qNH5qcw8qpgymFOqD", @"spotify:track:0sf12qNH5qcw8qpgymFOqD"],
            @[@"url", @"spotify://eevee/https%3A%2F%2Fopen.spotify.com%2Ftrack%2F0sf12qNH5qcw8qpgymFOqD", @"spotify:track:0sf12qNH5qcw8qpgymFOqD"],
            @[@"url", @"https://spotify.link/hRkBrwub9xb", @"https://spotify.link/hRkBrwub9xb"],
            @[@"url", @"vitrine://spotify.app.link/invite?token=a%2Fb", @"https://spotify.app.link/invite?token=a%2Fb"],
            @[@"url", @"https://open.spotify.com/socialsession/3o9uY8HJoj1IzCZs29YGcB?si=x&action=play", @"https://open.spotify.com/socialsession/3o9uY8HJoj1IzCZs29YGcB"],
            @[@"url", @"vitrine:internal:startgroupsession", NSNull.null],
            @[@"url", @"vitrine:debug:menu", NSNull.null],
            @[@"url", @"vitrine:jam:play", NSNull.null],
            @[@"url", @"spotify:session:join", NSNull.null],
            @[@"url", @"spotify:socialsession:3o9uY8HJoj1IzCZs29YGcB", NSNull.null],
            @[@"url", @"vitrine:webview:https%3A%2F%2Fexample.com", NSNull.null],
            @[@"url", @"spotify:settings", NSNull.null],
            @[@"url", @"spotify:auth:login", NSNull.null],
            @[@"url", @"spotify:account:delete", NSNull.null],
            @[@"url", @"spotify:download:0sf12qNH5qcw8qpgymFOqD", NSNull.null],
            @[@"url", @"spotify:add-to-playlist:0sf12qNH5qcw8qpgymFOqD", NSNull.null],
            @[@"url", @"spotify:unknown:0sf12qNH5qcw8qpgymFOqD", NSNull.null],
            @[@"url", @"spotify:collection:tracks", NSNull.null],
            @[@"url", @"spotify://eevee/track/0sf12qNH5qcw8qpgymFOqD", NSNull.null],
            @[@"url", @"spotify://eevee/spotify:track:0sf12qNH5qcw8qpgymFOqD", NSNull.null],
            @[@"url", @"spotify:track:abc", NSNull.null],
            @[@"url", @"spotify:track:0sf12qNH5qcw8qpgymFOqD:play", NSNull.null],
            @[@"url", @"spotify:track:0sf12qNH5qcw8qpgymFOqD?play=true", NSNull.null],
            @[@"url", @"https://open.spotify.com/track/0sf12qNH5qcw8qpgymFOqD/extra", NSNull.null],
            @[@"url", @"https://open.spotify.com/track/0sf12qNH5qcw8qpgymFOq%2F", NSNull.null],
            @[@"url", @"https://open.spotify.com/internal/startgroupsession", NSNull.null],
            @[@"url", @"https://open.spotify.com/socialsession/play", NSNull.null],
            @[@"url", @"https://open.spotify.com/user/name%3Ainternal", NSNull.null],
            @[@"url", @"https://accounts.spotify.com/track/0sf12qNH5qcw8qpgymFOqD", NSNull.null],
            @[@"url", @"https://foo.spotify.com/track/0sf12qNH5qcw8qpgymFOqD", NSNull.null],
            @[@"url", @"https://spotify.com/track/0sf12qNH5qcw8qpgymFOqD", NSNull.null],
            @[@"url", @"https://foo.spotify.link/invite", NSNull.null],
            @[@"url", @"https://spotify.link.evil.example/invite", NSNull.null],
            @[@"url", @"https://open.spotify.com@evil.example/track/0sf12qNH5qcw8qpgymFOqD", NSNull.null],
            @[@"url", @"https://evil@open.spotify.com/track/0sf12qNH5qcw8qpgymFOqD", NSNull.null],
            @[@"url", @"https://open.spotify.com:8443/track/0sf12qNH5qcw8qpgymFOqD", NSNull.null],
            @[@"url", @"http://open.spotify.com/track/0sf12qNH5qcw8qpgymFOqD", NSNull.null],
            @[@"url", @"file:///tmp/song", NSNull.null],
            @[@"url", [@"vitrine:track:" stringByPaddingToLength:4097 withString:@"a" startingAtIndex:0], NSNull.null],
            @[@"url", [@" " stringByPaddingToLength:4097 withString:@" " startingAtIndex:0], NSNull.null],
            @[@"shared", @"Listen: spotify:track:0sf12qNH5qcw8qpgymFOqD", @"spotify:track:0sf12qNH5qcw8qpgymFOqD"],
            @[@"shared", @"Listen: https://open.spotify.com/track/0sf12qNH5qcw8qpgymFOqD?si=x", @"spotify:track:0sf12qNH5qcw8qpgymFOqD"],
            @[@"shared", @"Try vitrine:internal:startgroupsession", NSNull.null],
            @[@"shared", @"Try spotify:jam:play", NSNull.null],
            @[@"shared", @"Try spotify:webview:https://open.spotify.com/track/0sf12qNH5qcw8qpgymFOqD", NSNull.null],
            @[@"shared", @"Try vitrine:settings:account", NSNull.null],
            @[@"shared", @"Try spotify:unknown:0sf12qNH5qcw8qpgymFOqD", NSNull.null],
            @[@"shared", [@"https://open.spotify.com/track/0sf12qNH5qcw8qpgymFOqD " stringByPaddingToLength:65537 withString:@"a" startingAtIndex:0], NSNull.null],
            @[@"shared", [@"한" stringByPaddingToLength:22000 withString:@"한" startingAtIndex:0], NSNull.null],
            @[@"https", @"https://open.spotify.com/track/x", @YES],
            @[@"https", @"https://spotify.link/x", @YES],
            @[@"https", @"https://spotify.app.link/x", @YES],
            @[@"https", @"https://foo.open.spotify.com/x", @NO],
            @[@"https", @"https://foo.spotify.app.link/x", @NO],
            @[@"https", @"http://spotify.link/x", @NO],
            @[@"handoff", @"https://open.spotify.com/socialsession/3o9uY8HJoj1IzCZs29YGcB", @"retrine://https://open.spotify.com/socialsession/3o9uY8HJoj1IzCZs29YGcB"],
            @[@"handoff", [@"https://spotify.link/x?q=" stringByPaddingToLength:4096 withString:@"a" startingAtIndex:0], NSNull.null],
            @[@"trusted", @"spotify://collection/tracks", @"spotify:collection:tracks"],
            @[@"trusted", @"spotify:collection:tracks", @"spotify:collection:tracks"],
            @[@"url", @"spotify://collection/tracks", NSNull.null],
            @[@"url", @"vitrine://https//open.spotify.com/intl-ko/playlist/37i9dQZF1DXcBWIGoYBM5M?si=delivery-probe", @"spotify:playlist:37i9dQZF1DXcBWIGoYBM5M"],
            @[@"url", @"vitrine://https//open.spotify.com.evil.example/playlist/37i9dQZF1DXcBWIGoYBM5M", NSNull.null],
            @[@"url", @"vitrine://https//open.spotify.com/internal/startgroupsession", NSNull.null],
        ];
        for (NSArray *test in cases) {
            id actual;
            if ([test[0] isEqual:@"shared"]) actual = SGSpotifyLinkInSharedText(test[1]).absoluteString;
            else if ([test[0] isEqual:@"trusted"]) actual = SGSpotifyURIFromText(test[1]).absoluteString;
            else if ([test[0] isEqual:@"https"]) actual = @(SGIsSpotifyHTTPSURL([NSURL URLWithString:test[1]]));
            else if ([test[0] isEqual:@"handoff"]) actual = SGRetrineURLForSpotifyURL([NSURL URLWithString:test[1]]).absoluteString;
            else actual = SGPublicSpotifyURLFromText(test[1]).absoluteString;
            id expected = test[2];
            if (![(actual ?: (id)NSNull.null) isEqual:expected]) {
                NSLog(@"FAIL %@: got %@, expected %@", test[0], actual, expected);
                return 1;
            }
        }
        for (NSArray *test in @[
            @[(id)LegacyDispatcher.class, NSNull.null, @YES],
            @[(id)ModernDispatcher.class, (id)NavigationReason.class, @YES],
            @[(id)ModernDispatcher.class, NSNull.null, @NO],
            @[(id)MissingReadiness.class, (id)NavigationReason.class, @NO],
            @[NSNull.null, (id)NavigationReason.class, @NO],
        ]) {
            Class dispatcher = test[0] == NSNull.null ? Nil : test[0];
            Class reason = test[1] == NSNull.null ? Nil : test[1];
            if (SGSupportsSpotifyLinkDispatch(dispatcher, reason) != [test[2] boolValue]) {
                NSLog(@"FAIL unsupported dispatcher capability boundary");
                return 1;
            }
        }
        if (!supersession()) return 1;
        NSLog(@"PASS %lu input cases, five dispatcher cases and five supersede cases", (unsigned long)cases.count);
    }
    return 0;
}
