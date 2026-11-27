#import "LinkURL.h"

NSURL *SGSpotifyURIFromText(NSString *text) {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length) return nil;
    NSURL *url = [NSURL URLWithString:trimmed];
    if ([url.scheme.lowercaseString isEqualToString:@"spotify"]) {
        if (!url.host) return url;
        NSURL *public = SGPublicSpotifyURLFromText(trimmed);
        if (public) return public;
        NSURLComponents *parts = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        NSString *path = [parts.percentEncodedPath stringByReplacingOccurrencesOfString:@"/" withString:@":"];
        return [NSURL URLWithString:[NSString stringWithFormat:@"spotify:%@%@%@%@",
            parts.percentEncodedHost, path,
            parts.percentEncodedQuery ? [@"?" stringByAppendingString:parts.percentEncodedQuery] : @"",
            parts.percentEncodedFragment ? [@"#" stringByAppendingString:parts.percentEncodedFragment] : @""]];
    }
    return SGPublicSpotifyURLFromText(trimmed);
}

const NSUInteger SGMaximumInboundURLBytes = 4096;
const NSUInteger SGMaximumSharedTextBytes = 65536;

static BOOL bounded(NSString *text, NSUInteger bytes) {
    return [text isKindOfClass:NSString.class] && text.length <= bytes &&
           [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= bytes;
}

static BOOL matches(NSString *text, NSString *pattern) {
    return text.length && [text rangeOfString:pattern options:NSRegularExpressionSearch].location != NSNotFound;
}

static BOOL spotifyHost(NSString *host) {
    return [@[@"open.spotify.com", @"spotify.link", @"spotify.app.link"] containsObject:host.lowercaseString];
}

BOOL SGIsSpotifyHTTPSURL(NSURL *url) {
    if (!url || !bounded(url.absoluteString, SGMaximumInboundURLBytes)) return NO;
    NSURLComponents *parts = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    return [parts.scheme.lowercaseString isEqualToString:@"https"] && spotifyHost(parts.host) &&
           !parts.user && !parts.password && (!parts.port || parts.port.integerValue == 443);
}

BOOL SGSpotifyURLNeedsResolution(NSURL *url) {
    return SGIsSpotifyHTTPSURL(url) && ![url.host.lowercaseString isEqualToString:@"open.spotify.com"];
}

static NSURL *publicPage(NSArray<NSString *> *pieces) {
    if (pieces.count != 2) return nil;
    NSString *root = pieces[0], *identifier = pieces[1];
    if ([root isEqualToString:@"user"]) {
        // Legacy profile IDs are not base62 resource IDs; accept one bounded URI-unreserved token.
        if (!matches(identifier, @"\\A[A-Za-z0-9._~-]{1,255}\\z") ||
            [identifier isEqualToString:@"."] || [identifier isEqualToString:@".."]) return nil;
    } else {
        if (![@[@"track", @"album", @"artist", @"playlist", @"show", @"episode"] containsObject:root] ||
            !matches(identifier, @"\\A[A-Za-z0-9]{22}\\z")) return nil;
    }
    return [NSURL URLWithString:[NSString stringWithFormat:@"spotify:%@:%@", root, identifier]];
}

static NSURL *publicWebURL(NSString *text) {
    NSURL *url = [NSURL URLWithString:text];
    if (!SGIsSpotifyHTTPSURL(url)) return nil;
    NSURLComponents *parts = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (SGSpotifyURLNeedsResolution(url)) {
        if (!matches(parts.percentEncodedPath, @"\\A/[A-Za-z0-9_-]+\\z")) return nil;
        parts.fragment = nil;
        return parts.URL;
    }
    if (![parts.percentEncodedPath hasPrefix:@"/"]) return nil;
    NSMutableArray *pieces = [NSMutableArray array];
    for (NSString *piece in [[parts.percentEncodedPath substringFromIndex:1] componentsSeparatedByString:@"/"]) {
        NSString *decoded = piece.stringByRemovingPercentEncoding;
        if (!decoded.length) return nil;
        [pieces addObject:decoded];
    }
    if (matches(pieces.firstObject, @"\\Aintl-[A-Za-z]{2}(-[A-Za-z]{2})?\\z"))
        [pieces removeObjectAtIndex:0];
    if (pieces.count == 2 && [pieces[0] isEqualToString:@"socialsession"] &&
        matches(pieces[1], @"\\A[A-Za-z0-9]{22}\\z")) {
        // Keep the public HTTPS invitation; only Spotify's own Jam handler may offer to join.
        return [NSURL URLWithString:[@"https://open.spotify.com/socialsession/" stringByAppendingString:pieces[1]]];
    }
    if ([pieces.firstObject isEqualToString:@"embed"]) [pieces removeObjectAtIndex:0];
    // Share queries are not navigation options. In particular, never forward action/context parameters.
    return publicPage(pieces);
}

NSURL *SGPublicSpotifyURLFromText(NSString *text) {
    if (!bounded(text, SGMaximumInboundURLBytes)) return nil;
    text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!text.length || [text rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound ||
        [text rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound ||
        [text containsString:@"\\"]) return nil;
    NSURLComponents *parts = [NSURLComponents componentsWithString:text];
    NSString *scheme = parts.scheme.lowercaseString;
    if ([scheme isEqualToString:@"https"]) return publicWebURL(text);
    // Old shared links and current handoffs use the same parser.
    BOOL handoff = [scheme isEqualToString:@"retrine"] || [scheme isEqualToString:@"vitrine"];
    if (!handoff && ![scheme isEqualToString:@"spotify"]) return nil;
    NSString *rest = [text substringFromIndex:parts.scheme.length + 1];
    if (![rest hasPrefix:@"//"]) return publicPage([rest componentsSeparatedByString:@":"]);
    rest = [rest substringFromIndex:2];
    // LaunchServices drops the empty-port colon in retrine://https://… during handoff.
    if (handoff && [rest.lowercaseString hasPrefix:@"https//"])
        return publicWebURL([@"https://" stringByAppendingString:[rest substringFromIndex:@"https//".length]]);
    BOOL eevee = [scheme isEqualToString:@"spotify"] && [rest hasPrefix:@"eevee/"];
    if (eevee) rest = [rest substringFromIndex:@"eevee/".length];
    if ([rest.lowercaseString hasPrefix:@"https%3a%2f%2f"]) {
        rest = rest.stringByRemovingPercentEncoding;
        if (!rest || [rest rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return nil;
    }
    if ([rest.lowercaseString hasPrefix:@"https://"]) return publicWebURL(rest);
    NSString *host = [rest componentsSeparatedByString:@"/"].firstObject;
    if (spotifyHost(host)) return publicWebURL([@"https://" stringByAppendingString:rest]);
    if (eevee) return nil;
    return publicPage([rest componentsSeparatedByString:@"/"]);
}

NSURL *SGSpotifyLinkInSharedText(NSString *text) {
    if (!bounded(text, SGMaximumSharedTextBytes)) return nil;
    NSURL *whole = SGPublicSpotifyURLFromText(text);
    if (whole) return whole;
    // Include legacy handoffs, but not an embedded HTTPS substring inside a rejected action URI.
    NSRegularExpression *uris = [NSRegularExpression regularExpressionWithPattern:@"\\b(?:https|spotify|retrine|vitrine):[^\\s<>\"']+"
                                                                         options:NSRegularExpressionCaseInsensitive error:NULL];
    for (NSTextCheckingResult *match in [uris matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
        NSURL *url = SGPublicSpotifyURLFromText([text substringWithRange:match.range]);
        if (url) return url;
    }
    return nil;
}

NSURL *SGRetrineURLForSpotifyURL(NSURL *url) {
    NSURL *valid = SGPublicSpotifyURLFromText(url.absoluteString);
    NSString *handoff = nil;
    if ([valid.scheme isEqualToString:@"spotify"])
        handoff = [@"retrine:" stringByAppendingString:[valid.absoluteString substringFromIndex:@"spotify:".length]];
    else if (SGIsSpotifyHTTPSURL(valid))
        handoff = [@"retrine://" stringByAppendingString:valid.absoluteString];
    return bounded(handoff, SGMaximumInboundURLBytes) ? [NSURL URLWithString:handoff] : nil;
}
