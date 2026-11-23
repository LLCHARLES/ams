#import <Foundation/Foundation.h>

extern const NSUInteger SGMaximumInboundURLBytes;
extern const NSUInteger SGMaximumSharedTextBytes;

// Trusted, user-configured tabs may name internal Spotify pages. Never use this for external ingress.
NSURL *SGSpotifyURIFromText(NSString *text);

// Untrusted input: a public page URI, a public HTTPS Jam invitation, or an unresolved short URL.
NSURL *SGPublicSpotifyURLFromText(NSString *text);
BOOL SGIsSpotifyHTTPSURL(NSURL *url);
BOOL SGSpotifyURLNeedsResolution(NSURL *url);
NSURL *SGSpotifyLinkInSharedText(NSString *text);
NSURL *SGRetrineURLForSpotifyURL(NSURL *url);
