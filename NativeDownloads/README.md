# Pixie binary profiles

`targets/spotify-*.json` owns target fingerprints, instruction expectations and
cave allocations and primary/compatibility artifact policy. `targets/runtime-1.2.json`
retains the shared ABI/layout facts used by the migrated 1.4 companion.
`tools/pixie_target.py` loads immutable targets explicitly;
there is no process-global/environment-selected target. Selection requires
the exact short version, bundle build, main UUID and SpotifyShared UUID.

| Spotify | Build | Packaging | Runtime layout |
| --- | --- | --- | --- |
| 9.1.90 | 919002269 | Enabled | Verified old target |
| 9.2.0 | 920002054 | Primary IPA enabled | Runtime admitted using pinned Eevee layout and static setter proofs below |

IPA packaging may patch a 9.2.0 executable. Jailbreak remains 9.1.90-only.
Changing the profile's enabled flag is not runtime-layout verification.

IPA builds include Pixie by default and require an enabled exact profile.
The primary 9.2.0 artifact is
`out/retrine-<version>-pixie.ipa`; the compatibility artifact is
`out/retrine-<version>-pixie-spotify-9.1.90.ipa`. Make's Pixie default input follows
the JSON primary target if present, then the first `ipa/*.ipa`; an explicit `IPA` overrides discovery.
An unsupported version, build or UUID is fatal when Pixie is requested.
`PIXIE=0` / `--no-pixie` explicitly excludes it. WireGuard admission is independent
and unchanged. Every lane, including default and explicit exclusion, rejects
existing companion payloads, native dependencies and partial overlays.
Malformed or encrypted inputs always fail.

Packaging generates all compiler headers into its private temporary include
directory. Angle-bracket includes select those files ahead of `src/`; source
header snapshots are only the 9.1.90 defaults for standalone fixtures. Builds
never rewrite source headers. Cross-profile header sets are rejected before
compilation. Runtime admission also checks both loaded image UUIDs and bundle
metadata before allowing native mutation.
The constructor, jailbreak writer/import installer, hook installers and public
mutation APIs share `SAPRuntimeProfileAdmitted`; an unsupported host does not
rewrite configuration caches, issue offline/library commands or persist settings.
Jailbreak packaging also uses a private temporary workspace per invocation.

## Focused checks

Run under the repository build lock, for example:

```sh
/usr/bin/lockf -k /tmp/vitrine-build.lock env -u MAKELEVEL THEOS=$HOME/theos \
  python3 -B NativeDownloads/tests/patch_goldens.py
```

Other focused scripts: `tests/profiles.py`, `tests/track_api_binary.py`,
`tests/profile_runtime.py`, `tests/native_admission.py`,
`tests/runtime_effects.py`, `tests/packaging_admission.py`, `tests/golden_mutation.py`,
`tests/key_mode_runtime.py`, `tests/native_trace_patch.py`, and
`tests/build_guard.py ipa/Spotify-9.1.90.ipa`. `tests/jailbreak_support.py` checks
that the DEB bootstrap reports readiness only after both patches and imports succeed.
They are also included in the
native suite where applicable. If a supplied IPA exists, failures to extract,
assemble or validate it are failures, not skips.

On a booted disposable iPhone simulator, set `SIMULATOR_UDID` to its UUID.
`tools/test_retrine_init.py` opens Pixie from both the old and new mod roots
and checks init ownership. `tools/test_retrine_settings_ui.py` exercises the
localized settings UI on iOS 26 or newer.

The 1.4 host runner is `tools/test14.py`: 57 compiled fixtures plus eight script
fixtures, selected individually with `--fixture`. Its default runs all 65, not
just the compiled fixtures. The script fixtures cover artwork caching, encrypted
export, Apple M4A encoding, library ZIP packaging, native restrictions/trace ABI,
entitlement preservation and sideload dependency resolution. Pass `--build-dir`
with a fresh temporary directory and remove its generated artifacts afterwards.

The frozen 9.1.90 goldens cover the entire patched executable (fixed-zero trace
and selectable-key variants) and the four existing generated headers, before
signing. They do not promise identical signatures or a byte-identical companion
dylib after runtime fixes. Never regenerate the expected hashes from a changed
patcher.

### 9.2.0 runtime-layout provenance

The target JSON owns admission; its generated headers feed the existing
`SAPRuntimeProfileAdmitted` and `nativeState` gates. Both layout and reservation
gates are open for the exact 9.2.0 identity. No runtime checks or offsets were
removed or bypassed; 9.1.90 and jailbreak policy are unchanged.

The adopted layout is EeveeSpotifyReincarnated
`0d9feaa9008e53b06382c61fffcb5cfcfceb2981`.
Its commit `5f7b82e4de89121d1cd1dd6e224b67ad2c9cce52` records downloads refused
with the old quota fields, then fixes `0x2b8..0x2d8` to `0x2c0..0x2e0`.
Before opening the gates, generated 9.2.0 offsets and every manager subfield
read by our adapter were compared with that pinned source; all match:

| Fields | Matching offsets | Eevee source at the pinned commit |
| --- | --- | --- |
| Wrapper manager; manager vtable; first method | wrapper `+8`; manager `+0`; vtable `+0` | `NativeDownloads/src/Spotify/NativeOfflineAdapter.m:204-215` |
| Current tracks; current episodes | `0x2b8`, `0x2bc` | `NativeDownloads/src/Spotify/NativeOfflineAdapter.m:237-241` |
| Music limit; music duration; episode limit; episode duration; ABP duration | `0x2c0`, `0x2c8`, `0x2d0`, `0x2d8`, `0x2e0` | `NativeDownloads/src/Spotify/NativeOfflineAdapter.m:237-241` |
| Online; connection allows offlining; track license expired; episode license expired; disk full | `0x221`, `0x222`, `0x224`, `0x225`, `0x229` | `NativeDownloads/src/Spotify/NativeOfflineAdapter.m:252-260` |
| Sync level; allow Spotify tracks; token flag | `0x238`, `0x23c`, `0x248` | `NativeDownloads/src/Spotify/NativeOfflineAdapter.m:252-260` |
| Provider; provider vtable; request slot (test-only lookup) | manager `0x290`; provider `+0`; vtable `+0x10` | `NativeDownloads/src/Spotify/NativeOfflineAdapter.m:546-547` |

Only the quota/reservation block moves: `0x2b0 + 8 = 0x2b8`.
Queue base `0x220` and provider `0x290` do not move. Eevee's
`NativeDownloads/src/Generated/TargetProfile.h:12` supplies the shift.
Trace reads also match: wrapper `+8`, descriptor file ID `+4`
(`NativeDownloads/src/Diagnostics/NativeKeyTrace.m:98-106`), and owner descriptor
`+0x120` (`NativeDownloads/src/Generated/ExportSites.h:4`), which our
`generate_target.layout_headers` derives from the target's instruction window.

Local static evidence comes from the clean supplied 9.2.0 IPA:
`tests/profiles.py:test_complete_caves_branches_and_abi` pins setter LDR bytes at
`0x1022d7cb8`, `0x1022d7cbc`, `0x1022d7ccc`, `0x1022d7cdc`, `0x1022d7cec`;
their decoded fields are respectively `0x2c8`, `0x2c0`, `0x2d8`, `0x2d0`, `0x2e0`.
`tests/target_foundation.py:test_concurrent_headers_and_compiled_manager_shift`
executes a read through generated block offset 696 (`0x2b8`).
Reservations, queue and ownership use the cited upstream layout evidence, not
an inference that the setter proves them.

This enables the upstream layout without a new local device capture.
Static proofs and host admission are not evidence of account authorization or
offline playback; no device/library mutation is part of these tests.
The separate host-side nebula account-attributes wiring is also necessary:
Eevee commit `5f7b82e4de89121d1cd1dd6e224b67ad2c9cce52` records download
`NOT_ALLOWED (23)` before that integration. Do not infer offline usability from
an archive containing the companion and valid static patches.

## Target foundation interface

Target data is adapted from Glongq/Vitrine-Pixie
`2632bdf9081665b9fd78e71cea2878edc6aae73c` and EeveeSpotifyReincarnated
`0d9feaa9008e53b06382c61fffcb5cfcfceb2981`, GPL-3.0. The JSON files retain the
upstream native/trace schema and add exact admission metadata. The 9.1.90 export
sites come from that baseline's `patch_export14.py`/`patch_export15.py`; the 9.2.0
export sites and ABI-2 emitter come from Eevee's target/`patch_export.py`.
The source-built companion is now 1.4; no upstream prebuilt library is used.
The host-test drivers and `signing_metadata.py` / `fix_sideload_dependencies.py`
also derive from the pinned Vitrine-Pixie source. The packager uses these helpers
instead of duplicate inline signing/dependency rewrites: embedded XML entitlements
are retained even when `codesign -d` cannot read an ldid signature, and an optional
replacement Retrine dylib resolves Substrate relative to its own loader.

`companion_build.build_companion` consumes `pixie_target.PROFILES` / `load_target(path)` and passes a
target explicitly to `generate_target.generate_headers(folder, target)` and
`validate_headers(folder, target)`. The CLI requires both `--target` and
`--output`; it refuses the source tree. Compiler include order must put this
invocation-owned folder before `src`. `Generated/TargetProfile.h` contains the
exact identities, the native address macros and `SAP_TARGET_MANAGER_FIELD_SHIFT`;
the retained runtime reads the resulting `SAPProfileQuotaBlockOffset`.
Native patch headers plus `ExportObservationV2Patch.h` and
`ExportMediaUnsealPatch.h` are emitted together. Export window facts are
available as `target.export_windows` for the later companion layout headers.

`build_retrine_9190.prepare_foundation(native, target)` produces an in-memory
static 1.4 image and report, including export observations. It is **not** a
packaging bypass: callers must first admit the IPA's complete identity tuple.
The packager installs the native overlay and export observations together with
their source-built 1.4 consumer.
All declared allocations, including the 9.2.0 text-tail caves, are checked at
their complete emitted lengths after import injection. Export-only partial
overlays are rejected even when version/build metadata is changed.

Run `python3 -B NativeDownloads/tests/target_foundation.py` under the build lock,
alongside the focused admission checks above. It checks both supplied images,
export replay and branch/resolver targets, complete write boundaries, dyld import
binding, malformed export inputs and simultaneous independent header generation.
Its compiled manager fixture distinguishes the 9.1.90 offset from the 9.2.0 +8
offset; it does not exercise a real Spotify manager on 9.2.0.
