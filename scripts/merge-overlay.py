#!/usr/bin/env python3
"""Merges plist/ overrides into the IPA's Info.plist.

usage: merge-overlay.py <overlay.plist> <Info.plist from the IPA> <out.plist>
       merge-overlay.py --apply <overlay.plist> <Info.plist to update>
       merge-overlay.py --self-test

A key in plist/ replaces Spotify's own of that name, which is what every override except two wants.
The Bonjour services the Connect discovery browses are appended to Spotify's list, Spotify's own
local network wording is kept where it has one, and an App Transport Security (ATS) exception the
overlay adds is merged under Spotify's own ATS policy instead of replacing it: Spotify's
NSAllowsArbitraryLoads and per-domain settings are never relaxed or dropped by this build.

The only ATS exception plist/liquid-glass.plist adds is insecure HTTP for the Tailscale IPv4 range
(100.64.0.0/10). Since iOS 17 ATS refuses HTTP to a bare IP address even with
NSAllowsLocalNetworking (Apple's NSAllowsLocalNetworking and NSExceptionDomains documentation says
individual IP addresses and CIDR ranges belong in NSExceptionDomains), so a Tailscale host that
Safari or curl reaches over HTTP is refused inside the app. The range is what the OpenAI-compatible
address accepts (OpenAITranslate.m's SGOpenAICompletionURL); nothing else in the app is affected.
"""
import plistlib
import sys


def merge_ats(app_ats, overlay_ats):
    """Spotify's ATS policy with the overlay's additions.

    The app's own keys always win, and an exception dictionary the app already has for a domain is
    kept exactly as it is: the overlay may add a domain Spotify does not name, never relax one it
    does. That keeps this build from ever turning on insecure HTTP for a host Spotify already
    configured (api.spotify.com and the rest)."""
    app_ats = app_ats if isinstance(app_ats, dict) else {}
    overlay_ats = overlay_ats if isinstance(overlay_ats, dict) else {}
    merged = dict(app_ats)
    domains = dict(app_ats.get('NSExceptionDomains') or {})
    overlay_domains = overlay_ats.get('NSExceptionDomains')
    for domain, values in (overlay_domains if isinstance(overlay_domains, dict) else {}).items():
        if not isinstance(values, dict) or domain in domains:
            continue
        domains[domain] = dict(values)
    if domains:
        merged['NSExceptionDomains'] = domains
    for key, value in overlay_ats.items():
        if key != 'NSExceptionDomains':
            merged.setdefault(key, value)
    return merged


def merge(app, overlay):
    """The overlay to hand the injector: every override, with Bonjour services and ATS merged."""
    overlay = dict(overlay)
    services = list(app.get('NSBonjourServices') or [])
    services += [s for s in overlay.get('NSBonjourServices') or [] if s not in services]
    if services:
        overlay['NSBonjourServices'] = services
    else:
        overlay.pop('NSBonjourServices', None)
    if app.get('NSLocalNetworkUsageDescription'):
        overlay.pop('NSLocalNetworkUsageDescription', None)
    if 'NSAppTransportSecurity' in overlay:
        ats = merge_ats(app.get('NSAppTransportSecurity'), overlay['NSAppTransportSecurity'])
        if ats:
            overlay['NSAppTransportSecurity'] = ats
        else:
            overlay.pop('NSAppTransportSecurity')
    return overlay


def self_test():
    spotify = {'NSAllowsArbitraryLoads': False, 'NSAllowsLocalNetworking': True,
               'NSExceptionDomains': {'api.spotify.com': {'NSExceptionMinimumTLSVersion': 'TLSv1.2'}}}
    ours = {'NSExceptionDomains': {'100.64.0.0/10': {'NSExceptionAllowsInsecureHTTPLoads': True},
                                   'api.spotify.com': {'NSExceptionAllowsInsecureHTTPLoads': True}},
            'NSAllowsArbitraryLoads': True, 'NSAllowsLocalNetworking': False}
    merged = merge_ats(spotify, ours)
    assert merged['NSAllowsArbitraryLoads'] is False, 'arbitrary loads must stay off'
    assert merged['NSAllowsLocalNetworking'] is True, 'local networking must stay on'
    assert merged['NSExceptionDomains']['api.spotify.com'] == {'NSExceptionMinimumTLSVersion': 'TLSv1.2'}, \
        "an existing domain's dictionary is kept exactly as Spotify set it, never relaxed"
    assert 'NSExceptionAllowsInsecureHTTPLoads' not in merged['NSExceptionDomains']['api.spotify.com']
    assert merged['NSExceptionDomains']['100.64.0.0/10'] == {'NSExceptionAllowsInsecureHTTPLoads': True}, \
        'the tailnet range is added'
    assert merge_ats(None, None) == {}
    assert merge_ats(None, {'NSExceptionDomains': {}}).get('NSExceptionDomains') is None
    assert merge_ats({'NSAllowsArbitraryLoads': False}, {}) == {'NSAllowsArbitraryLoads': False}
    assert merge_ats(spotify, {}) == spotify
    assert merge_ats(spotify, {'NSExceptionDomains': {'100.64.0.0/10': 'junk'}}) == spotify
    # Merging twice changes nothing more.
    assert merge_ats(merged, ours) == merged

    app = {'NSBonjourServices': ['_spotify-connect._tcp'], 'NSLocalNetworkUsageDescription': 'Spotify words',
           'NSAppTransportSecurity': spotify}
    overlay = {'NSBonjourServices': ['_spotify-connect._tcp', '_googlecast._tcp'],
               'NSLocalNetworkUsageDescription': 'Ours', 'NSMotionUsageDescription': 'Ours',
               'NSAppTransportSecurity': ours}
    result = merge(app, overlay)
    assert result['NSBonjourServices'] == ['_spotify-connect._tcp', '_googlecast._tcp']
    assert 'NSLocalNetworkUsageDescription' not in result
    assert result['NSMotionUsageDescription'] == 'Ours'
    assert result['NSAppTransportSecurity']['NSAllowsArbitraryLoads'] is False
    assert result['NSAppTransportSecurity']['NSExceptionDomains']['100.64.0.0/10']
    assert merge({'NSBonjourServices': []}, {'NSBonjourServices': []}) == {}
    print('overlay merge: Spotify ATS policy kept, Bonjour/local network words unchanged, '
          '100.64.0.0/10 exception added')


def main(argv):
    if '--self-test' in argv:
        self_test()
        return 0
    if len(argv) != 3:
        print(__doc__.split('\n\n')[1], file=sys.stderr)
        return 2
    apply = argv[0] == '--apply'
    overlay_path, app_path = argv[1:] if apply else argv[:2]
    with open(overlay_path, 'rb') as f:
        overlay = plistlib.load(f)
    with open(app_path, 'rb') as f:
        app = plistlib.load(f)
    result = merge(app, overlay)
    if apply:
        result = {**app, **result}
    with open(argv[2], 'wb') as f:
        plistlib.dump(result, f)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
