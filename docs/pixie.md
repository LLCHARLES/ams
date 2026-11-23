# Pixie native downloads

Retrine IPA builds include Pixie's native download manager by default and require an exact
[supported target](#supported-targets). Use `PIXIE=0` to build without it.

## Building

```sh
make release                                # primary Spotify 9.2.0
make release IPA=ipa/Spotify-9.1.90.ipa     # compatibility lane
```

These produce `out/retrine-<version>-pixie.ipa` and
`out/retrine-<version>-pixie-spotify-9.1.90.ipa`, separately from the input and ordinary
Retrine output. An explicit `IPA=` overrides the Pixie primary target.
`make build` and `make install` use the same overlay (the latter also signs and installs).
The direct pipeline includes Pixie unless given `--no-pixie` or `PIXIE=0`.
`make quick` reuses the last full IPA; rebuild it with the desired setting to change variants.

## Supported targets

Packaging accepts the exact decrypted Spotify **9.2.0** (`920002054`) and
**9.1.90** (`919002269`) profiles. Main and SpotifyShared UUIDs are recorded in
`NativeDownloads/targets/spotify-9.2.0.json` and `spotify-9.1.90.json`.
Version, build, both UUIDs, instruction windows, import bindings and unused executable
padding are checked before the base build; requested Pixie mismatches fail closed.

**Downloads work on the supported 9.2.0 IPA.** Its profile admits the runtime
using the verified Eevee `0d9feaa` manager layout, including the eight-byte
quota-field shift. The host also routes nebula account attributes through Pixie's
conversion. Downloading, keeping a download across an app restart, and deleting
it were verified on a real device. Jailbreak packaging remains 9.1.90-only.

All builds reject existing Pixie
payloads, partial overlays, malformed inputs and encrypted executables.
The finished Retrine IPA is checked again and overlaid after App Intents merging, before
any installation. The companion build needs Xcode's iPhoneOS SDK and `ldid`; application
entitlements are preserved and the complete ZIP is verified before atomic publication.

## In the app

Settings → Retrine reuses Pixie's existing runtime attachment for **Pixie Download Manager**
and **Send log**. Downloads stay in Spotify's offline storage; Pixie 1.4 also offers
separate, explicit audio-export actions.

Music-track context menus gain **Download**, bound to the selected track rather than
the currently playing one. The manager's **Add single-track downloads to Liked Songs**
switch defaults off and applies to subsequent individual downloads, including the
current-track action. When enabled, an accepted or already-present download also
requests an add to Liked Songs; album downloads do not. The manager's **Download
current track's album** saves that album to Your Library first when it is not there,
and sends the download only once Spotify confirms the save (within 30 seconds):
Spotify accepts a download for an album outside the library and then never starts
it. A save that fails or is not confirmed sends no download, and removing the
download later does not remove the album from the library. Canceling or removing a
download never removes a like. Library-add errors are reported separately from
download status. Menu routing and library changes still need real-device acceptance;
the host regressions check captured track identity and the verified 9.1.90 API.

## Diagnostics and privacy

Release builds enforce `SAP_ENABLE_WAV_CAPTURE=0`. Diagnostics default off; enabling them
persists across launches. Action recording also respects this switch. Reports can contain
track URIs, device identifiers and listening/download history: **inspect before sharing.**
Unstructured Eevee debug logs are excluded because their credential safety is unknown.
Existing About diagnostics remain available and are included through `SGWriteDiagnosticsFile`.

Pixie's `SAPL` uses Retrine's localization keys and Korean/English resources, following the
app's language with the same checked English fallback. `scripts/check-strings.py` also checks
Pixie's keys and placeholders. Long-term offline licence renewal remains unverified.

## Provenance and credits

`NativeDownloads/` imports the sources, tests, patch tools and assets from
[Glongq/Vitrine-Pixie](https://github.com/Glongq/Vitrine-Pixie) at exact commit
[`2632bdf9081665b9fd78e71cea2878edc6aae73c`](https://github.com/Glongq/Vitrine-Pixie/tree/2632bdf9081665b9fd78e71cea2878edc6aae73c/NativeDownloads),
under GPL-3.0 with existing notices retained. Upstream credits Pixie development/integration
to OpenAI Codex under Glongq's direction, and device testing/feedback to Glongq; earlier
work comes from Glongq/EeveeSpotifyReincarnated. Selected companion fixes are pinned to
Eevee [`0d9feaa9008e53b06382c61fffcb5cfcfceb2981`](https://github.com/Glongq/EeveeSpotifyReincarnated/tree/0d9feaa9008e53b06382c61fffcb5cfcfceb2981).
Its Vitrine host overlay patch was **not** applied.

Local adaptations add preflight/atomic build integration, entitlement preservation,
init-family ownership safety, nonblocking diagnostic notifications and diagnostics privacy guards.
Jailbreak packaging supports only the exact 9.1.90 profile (rootful and rootless);
9.2.0 DEBs are rejected. Both Pixie package formats include the root GPL license
and `NativeDownloads/vendor/M4A-NOTICES.md`. Jailbroken-device execution remains unverified.

## Checks

Focused checks on an Apple Silicon Mac (no installation):

```sh
python3 -B NativeDownloads/tests/build_guard.py ipa/Spotify-9.1.90.ipa
python3 -B NativeDownloads/tests/track_api_binary.py
python3 -B NativeDownloads/tools/test_single_track.py
python3 -B NativeDownloads/tools/test.py
SPOTIFY_TEST_IPA="$PWD/ipa/Spotify-9.1.90.ipa" python3 -B NativeDownloads/tools/test_native_restrictions.py
```

`tools/test.py` and `tools/test14.py` share one current runner, including the
exact-target admission and frozen-golden checks. These use the clean target IPAs.

The optional UI fixtures need an already booted iPhone simulator:
`python3 NativeDownloads/tools/test_retrine_settings_ui.py` (iOS 26 or newer) and
`python3 NativeDownloads/tools/test_retrine_init.py` (Retrine root rows and init ownership).
`python3 NativeDownloads/tools/test_trace_platform.py` exercises the production notification
observers for nonblocking background posts and disabled/stale-generation delivery.
After simulator checks, run `xcrun simctl shutdown all` and
`osascript -e 'tell application "Simulator" to quit'`.
