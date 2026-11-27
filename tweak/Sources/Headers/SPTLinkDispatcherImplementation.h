// Spotify's link dispatcher, a singleton the app builds at startup; the route the app itself takes
// for a link it opens.
#import <Foundation/Foundation.h>

@interface SPTLinkDispatcherImplementation : NSObject
- (void)navigateToURI:(NSURL *)uri options:(long long)options reason:(id)reason completionHandler:(id)completion resultHandler:(id)result;
@end
