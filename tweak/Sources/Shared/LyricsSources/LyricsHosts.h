#import <Foundation/Foundation.h>

// Exact DNS names only, no suffix/subdomain inheritance. HTTPS is enforced by
// the routing caller. Remote-supplied URLs do not extend these allowlists.
FOUNDATION_EXPORT NSSet<NSString *> *SGLyricsProviderHosts(void);
FOUNDATION_EXPORT NSSet<NSString *> *SGLyricsBlockedProviderHosts(void);
BOOL SGLyricsProviderURLAllowed(NSURL *url);
void SGLyricsMarkRequest(NSMutableURLRequest *request);
BOOL SGLyricsRequestIsMarked(NSURLRequest *request);
BOOL SGLyricsBiniFileURLAllowed(NSURL *url);
