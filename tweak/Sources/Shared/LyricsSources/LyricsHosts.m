#import "LyricsHosts.h"
static NSString *const kBiniFileHost = @"lrc.red";
static NSString *const kLyricsRequestOrigin = @"Retrine.Lyrics.RequestOrigin";

BOOL SGLyricsProviderURLAllowed(NSURL *url) {
    return [url.scheme.lowercaseString isEqualToString:@"https"] && !url.user && !url.password &&
        (!url.port || url.port.integerValue == 443) && url.host &&
        [SGLyricsProviderHosts() containsObject:url.host.lowercaseString];
}
void SGLyricsMarkRequest(NSMutableURLRequest *request) {
    [NSURLProtocol removePropertyForKey:kLyricsRequestOrigin inRequest:request];
    if (SGLyricsProviderURLAllowed(request.URL))
        [NSURLProtocol setProperty:request.URL.absoluteString forKey:kLyricsRequestOrigin inRequest:request];
}
BOOL SGLyricsRequestIsMarked(NSURLRequest *request) {
    return SGLyricsProviderURLAllowed(request.URL) &&
        [[NSURLProtocol propertyForKey:kLyricsRequestOrigin inRequest:request] isEqual:request.URL.absoluteString];
}
BOOL SGLyricsBiniFileURLAllowed(NSURL *url) {
    return SGLyricsProviderURLAllowed(url) && [url.host.lowercaseString isEqualToString:kBiniFileHost];
}

NSSet<NSString *> *SGLyricsBlockedProviderHosts(void) {
    // Genius.m and SGGeniusSearchURL: search and song embeds share this host.
    static NSSet *hosts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ hosts = [NSSet setWithObject:@"genius.com"]; });
    return hosts;
}

NSSet<NSString *> *SGLyricsProviderHosts(void) {
    static NSSet *hosts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableSet *all = [SGLyricsBlockedProviderHosts() mutableCopy];
        [all addObjectsFromArray:@[
            @"lyrics-api.binimum.org", kBiniFileHost, // BiniLyrics
            @"music.bugs.co.kr", @"m.bugs.co.kr", // Bugs
            @"auth.deezer.com", @"pipe.deezer.com", @"api.deezer.com",
            @"www.genie.co.kr", @"dn.genie.co.kr",
            @"krcs.kugou.com", @"lyrics.kugou.com",
            @"lrclib.net",
            @"lyricsplus.binimum.org", @"lyricsplus.prjktla.my.id",
            @"apic-appmobile.musixmatch.com",
            @"music.163.com", // NetEase
            @"p1.petitlyrics.com",
            @"u.y.qq.com",
            @"api.spicylyrics.org",
            @"unison.boidu.dev",
        ]];
        hosts = [all copy];
    });
    return hosts;
}
