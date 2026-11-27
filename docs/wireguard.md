# App-local WireGuard / proxy

**Routes the inspected Spotify paths through the tunnel/proxy and blocks
installed guarded paths when it cannot. It is not a leak-proof or device-wide
VPN.** Do not use this feature as a security boundary for all
traffic from the app or device.

IPA builds include it by default: top-level `make build`, `make release`,
`make install`, `make quick` and direct pipeline/quick script invocations use
`WIREGUARD=1`. These builds require the Go release pinned in `WireGuard/go.mod`.
`WIREGUARD=0` excludes its sources, Go companion library, extra frameworks,
license resource and Mod Settings row and does not require Go.
Direct `tweak/Makefile` builds still default to `WIREGUARD=0` for development,
compile-only CI and harnesses.
Mode changes invalidate the link output without recompiling the settings source;
disabled → enabled → disabled works without cleaning, retaining the output path
used by `make quick`. A `WIREGUARD=0` build **drops all enforcement despite any saved runtime opt-in**.

When compiled in, it remains off until the user imports a profile or saves a
proxy, explicitly enables it, then restarts. Import never enables it. It applies
to both Retrine looks. Proxy routing needs iOS 17+ and the Network.framework
proxy APIs; Retrine's ordinary deployment floor is unchanged.

The Go runtime is not linked into the host or tweak. Both IPA variants embed
`Frameworks/libsgwg.dylib` as a signed sibling of `spotifyglass.dylib`, **not**
as a cyan injection input. Quick rebuilds replace/remove the sibling too.
Off launches and external proxy startup don't load it. The first engine
operation loads it once; this includes deliberately opening WireGuard settings
to inspect a stored profile, importing one before enabling, or requesting
redacted diagnostics. These use the same parser/redactor, not a second copy in
Objective-C. Loading them neither enables a route nor removes the restart
requirement. Do not unload a running Go runtime. The loader uses the absolute
main-bundle Frameworks path and refuses process and main-executable dyld search
overrides before opening it. Only CoreSimulator's process `DYLD_ROOT_PATH` is
exempt, never a root path embedded in the host. The packaging pipeline checks
the finished host has no `LC_DYLD_ENVIRONMENT` commands.
It validates the bridge version, size and required functions before use. A
failure cannot start a tunnel or validate an import; diagnostics return only
a fixed loader error, never the unredacted report.

The engine retains normal Go heap growth (`GOGC=100`) with a **64 MiB soft
Go-managed memory limit**. This gives bursts room without paying for more
frequent collections below the budget. It is not a hard bound on live data,
native allocations, or process footprint.

## Ownership and readiness

`Shared/WireGuard/SGWGCore.m` owns the launch state, Keychain, listener and
Foundation hooks. `SGWGAdmission.m` validates the inspected build/images.
`SGWGNative.m` installs Spotify-image import guards through `Core/SGRebind`.
`SGWGTransport.m` observes delegates, without enforcing routing.
`SGWGSettingsController.m` owns the form/recovery notice; `App/ModSettings.x`
only supplies its row. No audio/render-thread hooks or logging are added.

A saved opt-in arms the feature **before** checking capabilities. Installed
guards remain armed even if another guard cannot install. Readiness is
published atomically only after session guards, native-slot completeness,
version/build/both image UUIDs, proxy APIs and engine/proxy startup pass.
An absent or deferred native slot prevents readiness. The extended rebinder
counts every matching slot. Permitted `sendto`/`sendmsg` traffic calls the captured
predecessor, preserving Connect's multicast relay in either installation order.
The rebinder recognizes registered call-through chains on readiness refresh;
the existing `SGRebindImport` wrapper retains its other callers' behavior.
Native guards for existing slots are installed before add-image registration.
Registration replays existing images while readiness is still false;
one validation after both callbacks are installed covers that snapshot.
Subsequent image add/remove callbacks revoke readiness, then
recheck on the serial utility queue. Deferred slots are rechecked periodically.
This does not intercept pre-initializer traffic or make dyld updates a
transaction with arbitrary app traffic.

Guards that can install without newer proxy APIs continue denying on
unsupported systems. An unhookable entry point is **not** magically protected:
the UI reports incomplete guards, not a working VPN.

The UI distinguishes inspected-path guards installed, engine started, and
handshake age (no handshake means health unconfirmed). Engine startup alone is
not evidence of a healthy tunnel. A recovery notice offers **Turn off in-app
VPN**, effective next launch; it does not disable current enforcement and is
not relied on for enforcement.

## Hook inventory and failure boundary

All hooks below are omitted when runtime opt-in is off.

| Owner / entry | Routing or denial |
| --- | --- |
| Core: `+[NSURLSessionConfiguration defaultSessionConfiguration]`, `ephemeralSessionConfiguration`, `backgroundSessionConfigurationWithIdentifier:` | Apply proxy with failover disabled and local-address/availability URL protocols. Missing proxy APIs or unavailable readiness blocks covered web loads. Background transfers run outside URLProtocol and are **not covered**. |
| Core: `+[NSURLSession sessionWithConfiguration:]`, `sessionWithConfiguration:delegate:delegateQueue:`, `sharedSession` | Copy/reapply configuration at creation; shared session is a guarded replacement. |
| Core: `-[NSURLSession initWithConfiguration:delegate:delegateQueue:delegateDispatchQueue:]` and its actual local-session implementation | Reapply to the designated initializer's copied configuration, preserving delegates/queues and raw init ownership. Full return/argument encodings must match. |
| Core: `+[NSData dataWithContentsOfURL:]`, `dataWithContentsOfURL:options:error:`, applicable real class-cluster `initWithContentsOfURL:` / `initWithContentsOfURL:options:error:` implementations | HTTP(S) uses a guarded session without lyrics provenance. Non-web URLs preserve original behavior. Preserve mutable results, init ownership and errors. Main-thread and armed-unavailable loads fail immediately. Background synchronous loads have one eight-second deadline, independent completion queue, synchronized terminal state and cancellation on timeout. Do not call synchronous loading APIs from a render thread. |
| Core: `-[NSMutableURLRequest setAssumesHTTP3Capable:]`, `-[NSURLRequest assumesHTTP3Capable]` | Force false only with matching full ABI, including BOOL argument/return. TCP proxying does not carry QUIC. |
| Core: local-address URL protocol | Reject HTTP(S) literal IPs, localhost/`.localhost`/`.local` names that CFNetwork might exempt. This lexical check is **not an SSRF boundary**. |
| Core: lyrics direct URL protocol | Intentional, user-chosen uncovered path for marked Retrine lyrics requests only: default is no exception; “Direct for blocked sources only” allows HTTPS `genius.com` (search and embeds); “All lyrics sources direct” allows only the exact provider hosts in `Shared/LyricsSources/LyricsHosts.m`. Unmarked requests remain guarded. No subdomain inheritance, trailing-dot aliases, HTTP, userinfo, non-443 ports, Spotify or arbitrary response-provided URLs. Exempt requests use a private direct session and are not denied by tunnel readiness. |
| Native: imported `nw_connection_create` in Spotify and SpotifyShared | Copy TCP parameters, attach non-failover proxy context, preserve original endpoint and TLS identity. Unready, non-TCP or missing APIs use a denied loopback endpoint, not the requested remote address. Local discovery is exempt. |
| Native: imported `getaddrinfo` | Remote names use tunnel DNS only when usable; otherwise fail. Numeric/local names retain the original resolver. External-proxy mode has no engine DNS and denies remote-name lookup. |
| Native: imported `connect` | **Deny all remote BSD TCP/UDP**, including while the tunnel is healthy. No caller-fd SOCKS handshake, flag mutation or relay remains. Invalid sockaddr lengths return `EINVAL`. Local destinations retain original behavior. |
| Native: imported `sendto`, `sendmsg` | Deny remote datagrams, including port 53. Validate sockaddr lengths before casts and suppress SIGPIPE for allowed sends; failure to set the socket option fails the send. |
| Transport: `URLSession:task:didCompleteWithError:` and `URLSession:dataTask:didReceiveData:` on `SPTCoreURLSessionDataDelegate`, `_TtC26Connectivity_HttpClientKit20HttpClientURLSession`, `SPTDataLoaderService` | Count status/error category/bytes, then forward. Full ABI mismatch skips observation, not routing guards. |

Uncovered paths include background sessions, web sign-in, AVURLAsset,
pre-initializer traffic/existing sockets, imports in other images, unhooked
network APIs, local-network exemptions and playback on other Connect devices.
Local native exemptions include loopback, link-local and multicast, not
arbitrary RFC1918 addresses. WebSocket behavior is not certified by URLProtocol.
There is no system VPN, Network Extension, TUN, route change or VPN entitlement.
The engine's UDP socket and Apple's framework sockets are not rebound.

**Lyrics requests** is read for each new request, including on existing sessions;
no restart is required. Requests already started keep their route. Direct sites
see the user's real IP and the song being looked up. This choice never exempts
Spotify's own hosts; the existing coverage limitations above still apply.
`SGWGCore.m` retains ownership of routing and guards. Its direct URLProtocol
requires both lyrics-request provenance bound to the exact URL and an allowed
HTTPS host, without userinfo or a non-443 port. Unmarked traffic to these same
hosts remains guarded. BiniLyrics response-provided files must be on `lrc.red`.
The one-hop ephemeral session has no cookie, credential or URL cache stores and
uses the owned request's deadline. Only its exact private configuration and
copies made by the routing hooks are exempt, not unrelated reentrant construction.
Every redirect is marked only after fresh URL validation and handed back
to the original session/delegate and classified afresh; it is never followed by
the direct session. Revoked permission between selection and start cancels the
request. Non-exempt requests keep the existing non-failover proxy and readiness
denial. The synchronous NSData path has no provenance and retains readiness denial
and rejection of main-thread I/O. The host list
includes adapter search, auth and download hosts, not referer-only domains or
developer dashboards; new remote-supplied file hosts stay tunneled until reviewed.

BSD denial may prevent Spotify playback. Do not add a transparent relay merely
to make a playback test pass; record the limitation until a separately reviewed
design addresses caller-fd ownership and asynchronous semantics.

## Exact admission

Retrine supports Spotify 9.1.90, 9.2.0 (release base) and 9.2.2. Its install warning does not block launch.
WireGuard uses a separate exact-build check. Only
`tweak/Sources/Shared/WireGuard/SGWGTargets.inc` admits WireGuard targets:

| Version / build | Evidence |
| --- | --- |
| 9.1.90 / 919002269 | Local static IPA scan: main `fbce22c17e1b3e0d9be866ff9291943e`, shared `2e074234cfc63f0e9255c9881824167a`. |
| 9.1.94 / 919401928 | Fork static evidence only: main `1dfddfa139c03735b9a5fdfa475f4700`, shared `2c12ca8c48ad33f8af6569c084a6324f`. Not Retrine playback certification. |
| 9.2.0 / 920002054 | Local static IPA/ABI scan: main `b49e75781d8635d38bb57daf68fed8a8`, shared `30bac55f8361373aad607f0535395641`. |
| 9.2.2 / 920202587 | Local static scan: main `bedf0071845d39bbb2d096f9a8095e66`, shared `527ccb30a88f3dadb1b985336d3bcad6`; both delegate callbacks on all three owners and all five required imports present. No device routing test. |

The 9.2.0 qualification repeats the 9.1.90 source inventory and binary scan.
`SGWGTransport.m` is the only Spotify-class consumer: its three delegates each
retain both selectors in the hook inventory, with full encoding
`v40@0:8@16@24@32` in both supplied IPAs. `dyld_info -objc` class/selector/IMP
records joined to `otool -ov` encodings establish receiver-specific ABI, not
global string presence. The 9.2.0 completion/data IMPs are respectively
`0x1026fdb80`/`0x106e143c4` (SPTCoreURLSessionDataDelegate),
`0x106dd04fc`/`0x1067ff610` (HttpClientURLSession), and
`0x2c12e4`/`0x2c1008` (SPTDataLoaderService in SpotifyShared).
`SGWGNative.m` uses the five named system imports above, all present in the main
image in both versions; neither shared image imports these five symbols.
The installer permits zero slots in SpotifyShared, but not the main image.
No Spotify ivar, fixed code offset, vtable or instruction patch is used by
WireGuard. Core hooks target Apple Foundation/Network APIs and retain their
runtime ABI/capability checks; static Spotify qualification cannot certify those
OS implementations or live import-slot readiness.

On an iOS 26.5 clone of the logged-in simulator, the no-Pixie 9.2.0
WireGuard build reached a real Proton US exit with a recent handshake,
`guards: installed; ready: yes`, six delegate hooks and five of five native
slots guarded (none deferred). Playback advanced on “Coullion (Fool)” and,
after Next, “Johnnie Can't Dance” (7.8 → 15.4 seconds); observed Spotify media
bytes rose from 460,649 to 12,623,297. Native mode also relaunched, handshook
and resumed playback; neither look showed the target-version warning.
This is simulator evidence, not device certification or proof of all routes.
The simulator conversion required removing its duplicate tweak load command
from the disposable app. Clipboard import blocked in UIKit's pasteboard read,
before the importer; acceptance instead called the production Keychain importer
and enable API through the debugger, removed the temporary profile copy, then
restarted. Device file/clipboard import, lock-screen playback and broken-profile
recovery remain to be checked.

Both runtime and preflight validate version, **CFBundleVersion and both UUIDs**.
Unlisted/future versions are rejected. Preflight also requires original bundle
ID, decrypted thin arm64 Mach-O, delegate selectors and native imports.
ZIP and extracted-app reads are bounded to 1 MiB for Info.plist and 512 MiB per
executable. Enabled `make quick` validates the actual cached app before building
or installing, even when its source IPA has been moved away.
Static presence cannot prove runtime ABI, import-slot installation or playback.
Simulator platform conversion does not relax production admission.

## Credentials and engine boundary

Profiles/passwords use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
Locked/unavailable Keychain results retry on a utility timer without foreground
UI; missing, malformed or permanent errors stay blocked. Authenticated proxies
never silently substitute empty credentials. Passwords are bound to normalized
(kind, host, port, username), cleared on identity changes. HTTP CONNECT sends
credentials without proxy-hop TLS; prefer HTTPS or WireGuard on untrusted links.
Origin TLS and HTTPS-proxy system trust are unchanged.

Clipboard-originated profile data is cleared before validation, including
failures. Temporary document copies are removed. No automatic enable follows
import. The parser rejects scripts, unknown/duplicate fields, invalid keys,
multiple peers, missing default routes/DNS and profiles over 64 KiB.

The loopback listener uses random per-launch authentication, at most 32 clients
awaiting authentication, a three-second auth deadline and immediate excess
rejection. After authentication, destination names are resolved through tunnel
DNS; **every** candidate must be public unicast under the engine policy before
any connection is made. Dial uses those exact validated addresses, not a second
hostname lookup. Private, loopback, link-local, unspecified, multicast and
restricted special-use ranges are refused. Trusted profile DNS servers are a
separate resolver configuration, not permitted client TCP destinations.
Endpoint hostnames necessarily use host DNS before the tunnel exists.

Decoded keys/PSK and generated UAPI reside in mutable byte buffers and are
cleared after `IpcSetOperation`, including failed startup. This does not promise
erasure of every transient Foundation/parser/upstream WireGuard copy or of the
live engine's necessary session keys.

Diagnostics store categories/counters, not URLs, keys or headers. Copied text is
redacted. A user-triggered country check displays the exit IP; never capture a
profile/key in logs, screenshots or test reports.

## Building and verification

`WireGuard/go.mod` pins the exact Go release (currently **1.27.4**).
`build-ios.sh` and CI enforce that version with `GOTOOLCHAIN=local`; no automatic
toolchain upgrade. Dependencies come from `go.mod`/`go.sum`, never prebuilt
libraries. Use an isolated official darwin-arm64 toolchain with its published
SHA-256 verified when Go is not installed; remove its caches afterwards.

```sh
(cd WireGuard && go mod verify && go test ./...)
python3 -B harness/wireguard/test_transport_scan.py
bash harness/wireguard/check-admission.sh
bash harness/wireguard/check-readiness.sh
python3 -B scripts/spotify-transport-scan.py ipa/Spotify-9.1.90.ipa --wireguard-compatible
python3 -B scripts/spotify-transport-scan.py ipa/Spotify-9.2.0.ipa --wireguard-compatible
python3 -B harness/wireguard/run_macos.py --live-profile /path/to/private.conf --expect-country US
bash WireGuard/build-ios.sh
(cd tweak && /usr/bin/lockf -k /tmp/vitrine-build.lock env -u MAKELEVEL THEOS=$HOME/theos gmake)
python3 -B harness/wireguard/check-build-mode.py disabled
(cd tweak && /usr/bin/lockf -k /tmp/vitrine-build.lock env -u MAKELEVEL THEOS=$HOME/theos WIREGUARD=1 gmake)
python3 -B harness/wireguard/check-build-mode.py enabled
(cd tweak && /usr/bin/lockf -k /tmp/vitrine-build.lock env -u MAKELEVEL THEOS=$HOME/theos gmake)
python3 -B harness/wireguard/check-build-mode.py disabled
bash harness/wireguard/check-connect-chain.sh
python3 -B scripts/check-strings.py --sync
```

The macOS harness uses the user's real Proton US profile, copies it only into a
temporary directory, compares the Mac's direct exit with the tunnel's US exit,
checks handshake/HTTPS/ranges/Foundation paths, then injects bad endpoint and
peer-key faults and checks a direct sentinel for zero hits. Spotify admission
and native rebinding are test doubles in that harness: they are not evidence
of real Spotify playback. No synthesized WireGuard test peer is retained.
External-proxy fixtures remain separate from provider testing.

Device/simulator acceptance must use a clone, never the original logged-in
simulator. Import, enable, restart, country check, uncached Free-account
playback/skip and broken-profile recovery all require actual interaction.
Go tests and successful compile-only fixtures do not certify those outcomes.

Third-party license inventory and provenance: `WireGuard/UPSTREAM.md` and
`WireGuard/THIRD_PARTY_LICENSES.txt`. The eight modules are MIT, Apache-2.0 or
BSD-3-Clause, compatible with GPL-3.0 with notices/corresponding source retained.
Windows-only Wintun is not linked into the iOS/macOS library. CI pins Theos and
third-party actions, uses read-only repository permissions, and publishes no
provider profile. English/Korean use the existing Localizable.strings table.
