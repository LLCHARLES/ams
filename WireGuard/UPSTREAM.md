# WireGuard source provenance

Ported from SUB2-8687/vitrine `main` at
`3bf218e9b3b6c6f3e717a2bda8a6ed4d9b29e1b0` (GPL-3.0), including the original
kes158/vitrine commits `efb9dd02a644d8aab3113c02fd675c65e8b2b776`,
`1fbd7d158ec0f62cc35ff29e8eeefdef021637ca` and
`9f44ee7cb8bcbe72effcca7fec3f76ba28a84123`.

Originally adapted from kes158/YTMusicUltimate, commit
`5291c728c1dc57909b915dcb421e8ba4f49e8819`, GPL-3.0 (repository LICENSE).
https://github.com/kes158/YTMusicUltimate/tree/5291c728c1dc57909b915dcb421e8ba4f49e8819

The Go engine, Objective-C session/profile core, settings form and test fixtures
retain that license. Google-specific transport patches are replaced by Spotify
delegate diagnostics and main-image TCP import rebinding. Dependency license
texts are in THIRD_PARTY_LICENSES.txt. The port uses Retrine's existing
Localizable.strings table; there is no WireGuard.strings table.

Only source is imported. Dependencies are fetched by Go using go.mod/go.sum;
build-ios.sh always builds the archive from source (no prebuilt-library switch).
The indirect wintun Go module is MIT; it is Windows-only and is not linked on
iOS/macOS. Its license is included for completeness; no Wintun driver/DLL ships.
wireguard-go is MIT, gVisor and google/btree are Apache-2.0 (gVisor also carries
MIT files), and x/crypto, x/net, x/sys, x/time and the Go runtime are BSD-3-Clause.
These are GPL-3.0-compatible, subject to retaining notices and providing the
corresponding source. This is a source/license inventory, not a legal opinion.

The fork accepted future versions after a structural scan. This port rejects
unlisted versions: SGWGTargets.inc is the single version/UUID evidence table
consumed by the scan and runtime version gate. See docs/wireguard.md for scope.
