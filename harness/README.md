# Harnesses in CI

`.github/workflows/harness.yml` runs the offline macOS / Mac Catalyst checks on
`macos-latest` for pull requests. Pushes to `main` and the weekly full run are
checked on the maintainer's own Mac runner from the private Retrine-CI repository,
so a push here runs no Mac job: `.github/workflows/private-checks.yml` only starts
that repository's poll, which checks the newest commit against the last one it
checked (its own schedule is the fallback). Each harness builds
**and runs** its checks; failure does not cancel the other jobs.

CI has two jobs. `plan` (ubuntu) reads the changed files and asks
`scripts/harness-plan.py` which harnesses a change needs: a change selects a
harness when it touches `harness/<dir>/` or any file that harness's build
scripts and sources reach — every repo path named in a build/check script
(`-I ../autoeq/shim`, `VENDOR=../../vendor/audio`, `$SRC/...`), every file
under such a directory, plus transitive quoted imports. A new directory a
build script starts using is picked up without editing the script. Every harness runs
when the changed list cannot be determined, when a change touches `.github/workflows/harness.yml`,
`.github/actions/` or `tweak/Makefile`, or when a changed path is no longer
in the checkout (a deletion, or a rename's old name: the diff is taken with
`--no-renames`), since a harness may still use it. Other `.github/` files follow the normal
path rules. For edits to `scripts/harness-plan.py`, CI sets `HARNESS_PLAN_BASE` to the
PR merge base or the private check's baseline. If only the `HARNESSES` list literal
differs, new or edited entries are selected by name alongside path matches; removing an
entry selects nothing by itself. Any edit outside the literal or uncertain comparison
(including a missing base, unreadable source or duplicate name) runs everything.
Reordering entries common to both versions also runs everything, since lookup uses the
first matching name or directory. The shortcut requires the running registry to equal
the head literal, so entries derived or modified after it cannot be missed.
A harness with no tweak
dependency is always selected, with a warning. The selected harnesses are
packed into at most five shards by greedy weight and run as
`Harnesses <shard>` jobs with a 45-minute timeout. Each shard containing a Theos harness uses
the setup-Theos action; its caches contain build tools/output, never
credentials or test data.

On PRs, odd attempts use `macos-latest` and even attempts use `macos-26-intel`.
Host, Catalyst and simulator harnesses build for the runner's architecture;
iPhone device libraries still target arm64. On same-repo PRs the Ubuntu watchdog
watches for up to 20 minutes and cancels only if **all planned Mac jobs** have
been queued for at least 90 seconds. Linux jobs aren't watched. Forks and
Dependabot PRs wait for GitHub's natural starvation failure.

`.github/workflows/runner-starvation-retry.yml` retries the **whole PR run**,
at most once: if `macos-latest` starves, the second and final attempt uses
`macos-26-intel` without a watchdog. A retry requires either GitHub's
`was not acquired by Runner` annotation on every unsuccessful workload with no
steps, or a successful or cancelled watchdog's warning naming the exact cancelled
Mac jobs, all without runners or steps and with other workloads successful. It
does not retry mixed failures, superseded runs or a SHA no longer at the PR head. The
last attempt waits in the queue normally. The privileged retry workflow runs
default-branch inline code only; it doesn't check out PR code or read artifacts.

Locally, the same script explains and runs selections from the repo root:

```sh
python3 scripts/harness-plan.py explain tweak/Sources/Shared/LockScreenLyrics/SGLyricsClip.m
python3 scripts/harness-plan.py run --names "Pitch" "Palette"
```

The runner locks each harness directory and shared preferences domains for the
whole build and run, printing a waiting line on contention while unrelated
harnesses can run in parallel. Invoking a `build.sh` or check script directly
bypasses these locks.
SIGINT/SIGTERM stop and reap the harness process group before unlocking;
SIGKILL cannot be handled and may leave children running after the kernel
releases the runner's locks.

`plan --changed-from <file|->` prints the selection, shards and matrix JSON.
Selected assertion-based entries use isolated iOS simulators. No phone, Spotify
installation, API credentials or visual review is used.

CI entries do not build mutants. Mutation proofs belong to check creation, not
ordinary runs; Liveprog's `--mutations` and the player's manual Automix script
are explicit opt-ins. `local-files/suggest-sim.py` runs only its assertion scenario
and shuts down/deletes its own simulator. Harness scripts default THEOS to `$HOME/theos`.

Run the commands in the workflow locally on an Apple Silicon Mac with Xcode.
The individual READMEs describe assertions and boundaries. Image/video output
is included only when the executable also checks the result and fails nonzero.
An offline fixture does not establish live-service or device compatibility.

## Included scripts and modes

All paths below are relative to `harness/`. Build-only scripts are followed by
their check executable in the workflow.

| Script | Mode / reason |
| --- | --- |
| `album-counts/check.sh` | Spotify album play counts: cover-layout migration, URI identities, malformed and failed replies, cache bounds, and the authenticated transport's origin, redirect and size limits, with request doubles. |
| `album-credits/build.sh` | Artist-credit matching assertions. |
| `album-notes/build.sh` | Album notes against replayed catalog fixtures, and the page's note placement and footer heights over Spotify collection doubles. |
| `artist-artwork/build.sh` | Artist match and one-attempt identity rules against replayed catalog fixtures, plus the 30 MB clip cap and the Low Data policy. |
| `appearance-accent/check.sh` | Catalyst Automatic accent ownership: page in front, playing cover, picked colour, real UIKit push/pop/tab/modal, and the player's Follow the cover combinations. |
| `appearance-page/rows-check.sh` | Appearance rows of both looks, including the explicit-badge switches, the redesign's glass choices (unset and out-of-range values) and Saved mark carrying Plain checkmark's old switch over. |
| `audio-effects/build.sh` | `route`, `presets` and `format`: isolated settings, preset-file and audio-format text assertions. |
| `auto-translation-settings/check.sh` | Real Catalyst settings callbacks with fake providers. |
| `autoeq/build.sh` | Default offline index/preset fixtures, not `online`. |
| `clean-links/build.sh` | Pure URL-cleaning assertions. |
| `connection-test-settings/check.sh` | Catalyst lifecycle assertions with a fake backend. |
| `driver/auth-check.sh` | Foundation driver-token rotation, header and diagnostic-redaction checks; runs with `driver/phone-check.py`. |
| `driver/command-check.sh` | Driver command classification and log-cursor sequence with the real log buffer. |
| `fluid-clip/build.sh` | Generated cover/video, decoded-frame and loop assertions. |
| `haptics/build.sh` | `build/track`: synthetic ISRC/protobuf/catalog assertions. |
| `head-gestures/build.sh` | Synthetic motion traces with expected gestures. |
| `listening-stats/build.sh` | Synthetic imports, calendar cases and 100k-row checks. |
| `local-files/build.sh` | Isolated metadata and imported LRC checks, the cover resolver, and the native cover watcher (`watcher.m`) updating to system artwork that arrives after its retries. |
| `local-files/suggest-build.py` | Find Info's pure parts on the Mac: query cleaning, the three-second duration window, ranking, JSON parsing and size caps, artwork URL rewriting, and that accepting only fills the editor. |
| `lyrics/translation-check.sh` | Catalyst lyrics-menu assertions, not screenshots alone. |
| `lyrics-clip/build.sh` | Default synthetic still/animated clips with decode assertions, and the Messages and Vinyl scenes (`scenes`). `regression.sh` checks visible-frame geometry and contrast. |
| `lyrics-pip/build.sh` | Catalyst PiP text decision (`LyricsPiPText.m`) for synthetic lines and positions, plus frame fitting checks (`LyricsPiPFrame.m`) and sample frame PNGs. |
| `lyrics-sources/build.sh` | Offline provider/parser/language fixtures. |
| `lyrics-sources/state-build.sh` | Real keeper and concurrent source walk with fake replies. |
| `lyrics-store/build.sh` | Foundation codec, isolated disk reads/writes/deletion, and oldest-first count/byte pruning; builds into a temporary directory and runs the checks itself. |
| `lyrics-translation/build.sh` | Default checks include `check-ai.m`; also `--auto-retry-only`. |
| `lyrics-translation/ondevice-kept-check.sh` | Catalyst Swift check: on-device translation keeps target-language lines as completed results. |
| `meaning-translate/build.sh` | Catalyst meaning sheet's Translate / Show Original over translation doubles for every provider route: stale replies, dismissal, duplicate taps, retry, language change, attribution kept. |
| `motion/build.sh` | Generated Canvas cuts and synthetic protobuf replies. |
| `native-declutter/check.sh` | Production native section classification, isolated heading histories and marker-priority/snapshot checks with Foundation view doubles; no simulator. |
| `now-playing/build.sh` | Logos setter hooks with the system setter replaced, lyrics off/on; displayed-piece and rest deadlines, speed changes through metadata resends and player-first seeks, late lyrics, interleaved artwork-Off cleanup, idle dispatches and defaults reads, and the Live Activity queue limit. |
| `palette/build.sh` | Generated image with asserted edge/main colors. |
| `palette/field-check.sh` | Catalyst player field palette requests across mode changes and stale replies; the flow layer's stepped drift, held and resumed. |
| `pitch/build.sh` | Synthetic sine pitch/speed assertions, no song argument. |
| `player/queue-check.sh` | Playing Next history, selection and cover delivery, including cancellation and a retry after an offline failure. |
| `python3 player/ui-check.py shuffle heat` | One simulator build checks per-track style selection, the missing-clip stand-in and its heat override. Creates and deletes a `PlayerUI-` simulator unless `--udid` names a booted one. |
| `player/title-notification-check.sh` | Player labels enabled live from an all-off launch and landscape title notifications, using offline fixtures. |
| `player/title-style-check.sh` | Catalyst: the player's title and artist type through the real `PlayerTitle.x`, Korean text, Spotify's setters, lyrics 17/17 and Spotify's family kept. |
| `player/progress-check.sh` | Catalyst: tracker cadence and visibility, first-reveal values, Spotify's own pause, and coverage published after a late opening morph without another layout. |
| `player/buffering-check.sh` | Catalyst: podcast loading band aligned to the chapter bar in both directions; unchanged frame without a chapter bar. |
| `now-playing-bar/check.sh` | Catalyst title and artist split through Logos: device and plain lines, neighbour pages, unknown tracks, and live title setting changes with the same player state; Translate song titles switched from an all-off launch through its row's notification, read off the title the bar's own layout shows; the iPad capsule growing no nearer than 16 pt to a split tab's circle, and a hidden split bar's circle limiting nothing; the device button left on the DJ request sheet's bar. `NPB_SHOTS=<dir>` writes those fixtures as PNGs. |
| `album/cover-check.sh` | Album artwork reading and hero rendering, including late images from a replaced header view. |
| `bash harness/album/motion-visibility.sh <simulator UUID>` | Album and artist header clip rates across viewport changes, plus clip and Fluid field motion through injected heat, cooling and Low Power Mode notifications. Uses a local ffmpeg clip on a booted simulator. |
| `artwork-clear/build.sh` | Clearing downloaded animated covers and artist answers in a sandboxed Caches folder: size, alert, Cancel, leased clips, stale transfers and lookups, failure reporting; songs, chosen covers, edits and lyrics untouched. |
| `fonts/build.sh` | Catalyst `FontLibrary.m` and the Free fonts page with Core Text faked at its two entry calls: installed families register off main, publish on main, never twice, and a removal is never overridden by a late publish; the real Font page (free and imported families) opens and the Free fonts page finishes a download while registrations are held, a block queued on main runs before each release, and the previews and the chosen font update after; a hidden Font page reloads nothing. |
| `gesture-hold/check.sh` | Mac check of the hold-to-play-faster helpers (`GestureHold.m`): defaults, index to speed, clamping, independence from the double tap, label and announcement text. |
| `liveprog-guard/run.py` | Mac run of the real effects engine with EEL2 Liveprog scripts: CPU-budget trips and the click-free bypass, re-enable reset, the two-second compile/@init deadline and abandoned-VM cleanup, no allocation on the render path. Manual mutation proofs require `--mutations`. |
| `library/rows-check.sh` | Simulator executable through Logos: the Library row separator spans from the artwork's text edge, mirrored right to left. |
| `home-podcasts/check.sh` | Catalyst Home filter menu through Logos: the Podcasts and audiobooks switch shown and hidden, audiobook chips, return to the default chip once, live flip; the pill's Friday ring only on a Friday, its turn's pace, fading and stopping with the pill as the row scrolls, stopping and resuming as Reduce Motion is switched, staying still once hidden. |
| `home-header/check.sh` | Catalyst Home header through Logos: the filter pill and the avatar 6pt apart, and the page's tint across its whole width, through an iPad's turns, window resizes, a feed that arrives after the page's last pass and a replaced page view. |
| `playlist/creator-check.sh` | Simulator executable through Logos: the playlist header's creator lookup keeps one-character names and skips the facepile's initial. |
| `playlist/rows-check.sh` | Simulator executable through Logos: the playlist track row separator spans from the artwork's text edge, mirrored right to left. |
| `playlist/chip-check.sh` | Catalyst: the playlist chip row keeps its touches while moving, fades over 24 pt while pinned, and returns on the reverse scroll; unrelated siblings are untouched. |
| `player/lyrics-layout-check.sh` | Catalyst, `PlayerLyrics.x`'s measurements as compiled: the lyric viewport and its controls keep the player's own bounds while the cover cell pages between tracks. |
| `player/repeat-check.sh` | Production repeat-mode transition (`SGPlayerAdvanceRepeat`) extracted from `PlayerState.x`: every flag combination, command order and returned answer; no simulator. |
| `player/upcoming-tracks-check.sh` | Production upcoming-track parsing (`SGURIString`, `SGPlayerUpcomingTracks`) extracted from `PlayerState.x` and run against Foundation doubles; no simulator. |
| `player-lyric-line/build.sh` | Catalyst fitting (shrink and whole-word portions) and the line's wait/re-arm rules for synthetic lines and positions. |
| `player-lyric-line/margin-check.sh` | Catalyst: both Spotify lyric preview classes reach the player's 32 pt margin in either layout direction, but keep their native width in a narrow column or outside the player. |
| `adblock/build.sh` | The real `AdHubs.x` hook through Logos against a Hub builder double: explicit ad metadata is removed only with Hide ads on, upsells only with Hide upsells on, in all four switch combinations. |
| `player-visualiser/build.sh` | Catalyst `PlayerVisualiser.m` under stubs: the Lyrics visualizer clears its words when the lyrics are replaced by unsynced ones, and the display link asks the screen's full rate while drawing skips to 60/30/15 Hz. With `PlayerLyricStages.m`: Poster's and Cut's word reveal, the untimed fallback, the parameters' defaults, clamping and removal, the halftone made once per artwork (a failed one final, an older job never replacing a newer), and Reduce Motion. `SHOTS=<folder>` writes `poster.png` and `cut.png`. |
| `player-refinements/check.sh` | Catalyst rolling-digit rules, column reuse, repeated setters without attributed-text reads, repair after an external edit, detached visibility observers, and the real roll on a label in a window, plus Star add button and Saved mark (the old Plain checkmark switch, and Dot) through Logos. |
| `prefs/check.sh` | Foundation preference validation plus counter persistence and file-hash checks (`counters.m`), and the Load ahead gate read through `SGEnabled` for wrong kinds and stock reset (`optional-work.m`). |
| `radio-modes/build.sh` | Foundation Spotify mocks, spoofing off/on. |
| `rtl/check.sh` | Simulator executable of its own, run left to right and then right to left: the glowing switch's knob, a slider row's value and title, a page row's value and chevron, a row's color swatch and value, the Sing card's column and play, the mic's upright slider, a recap story bar and its back and forward tap regions, and a gliding title's start and direction, each mirrored or kept as the direction asks. Its simulators are named `RetrineRTLCheck-<pid>`; a run deletes any of that name a cancelled run left. |
| `settings-bars/build.sh` | Catalyst `SGInsetForBars` over a 6,000-view mock window: walks counted across repeated layouts, inset follows a bar resized, hidden, removed, added, or a table moved to another window. |
| `settings-search/build.sh` | Mod Settings search: page-at-a-time index on a real run loop, keywords below titles, recent places by setting name across looks and languages. |
| `sing/render-regressions-build.sh` | Mac build of `SGSingEngine.m` with audio doubles: placed vocals keep float headroom through downstream attenuation, and the room reverb goes idle once Sing stops feeding it. |
| `sing/build.sh` | `spatial`: model-free lead, spatial and decoder assertions. |
| `sleep-timer/build.sh` | Fake player and clock: no pre-fade polling, quarter-second fade phase, expiry on resume after the clock jumps, gain restoration and track/album cases. |
| `song-audio/build.sh` | Per-song speed, pitch, pitch-follow and reverb records in two processes, with the player and the audio setters as doubles. |
| `spicy-lyrics/build.sh` | Offline parser, cache and retry fixtures. |
| `ui-refinements/badge-check.sh` | Both looks: ordinary views unclassified while off, badges masked on enable and unchanged reattachment, detached masks restored, geometry and VoiceOver kept. |
| `update/offline-check.sh` | Catalyst cached-release selection, no network. |
| `visualiser/build.sh` | Synthetic spectrum and PCM waveform assertions. |

## Excluded scripts

This inventory includes the offline scripts above and the simulator/service scripts below.
Simulator use alone does not exclude a check; `scripts/harness-plan.py` is the
authoritative entry list. Visual-only simulator scenarios are not promoted to CI
by merely compiling them.

| Script | Reason |
| --- | --- |
| `addtab/build.sh` | iOS simulator UI. |
| `album/build.sh` | iOS simulator UI. |
| `album/layout-check.py` | iOS simulator UI: the album header through a text-size change, a narrowed iPad window and Cover beside turning off, the artist line beside the cover with its faces, no text measured on header passes with nothing changed, and the Card cover drawn smaller under the pinned download and ⋯ capsule (left to right, right to left, Full screen untouched). |
| `appearance-page/build.sh` | iOS simulator UI. |
| `artist/build.sh` | iOS simulator UI. |
| `audio-effects-page/build.sh` | iOS simulator UI. |
| `audio-effects/build-import.sh` | iOS simulator import page. |
| `audio-effects/build-output.sh` | iOS simulator output control and render gate. |
| `audio-effects/build-sim.sh` | iOS simulator audio chain. |
| `clean-links/build-sim.sh` | iOS simulator share/pasteboard hooks. |
| `connect/build.sh` | Opens loopback sockets; excluded by the no-network requirement. |
| `driver/build.sh` | iOS simulator driver app. |
| `haptics-page/build.sh` | iOS simulator UI. |
| `home-tiles/build.sh` | iOS simulator UI. |
| `haptics/build-sim.sh` | iOS simulator audio/haptics hooks. |
| `head-gestures/sim/build.sh` | iOS simulator hooks and teaching UI with a fake motion manager: both Nothing actions stop the stream; another listener, teaching or paused Play/Pause recognition can still use it. |
| `launch/build.sh` | Requires an untracked flag table extracted from a Spotify IPA. |
| `library/build.sh` | iOS simulator UI. |
| `library/compact-check.sh` | iOS simulator UI. |
| `listening-stats/build-sim.sh` | iOS simulator UI. |
| `live-activity-page/build.sh` | iOS simulator UI. |
| `local-files/lyrics/build.sh` | iOS simulator local lyrics UI; `page` checks pause, seek, resume and foreground highlight, and `race` checks stale lookup rejection and an idle plain sheet. |
| `local-files/sim/build-sim.sh` | iOS simulator editor and screenshots. |
| `local-files/suggest-sim.py` | iOS simulator Edit info with Find Info against network fixtures: review sheet, Use, the picked cover's 1200 px bound, save through the overlay. |
| `lossless/build.sh` | iOS simulator decoder probe. |
| `lossless/handoff-build.sh` | iOS simulator audio chain. |
| `lyrics/build.sh` | iOS simulator lyrics UI; `-frameRateCheck 1 -song plain` checks the live display link and instrumental break animations with Smooth lyrics unset, off, and on. `-plainIdle 1 -song static` checks zero settled ticks, scrolling, five-second holds on pause and zero-speed stall, resume, and late timed replacement. |
| `lyrics-page/build.sh` | iOS simulator settings UI. |
| `menu/build.sh` | iOS simulator UI. |
| `mod-settings/build.sh` | iOS simulator settings UI. |
| `mod-settings/light-check.sh` | iOS simulator screenshots in Light and Dark Mode: the mod's alerts dark over a window in the system's appearance, as Spotify's is. |
| `morph/build.sh` | iOS simulator visual rendering. `morph/check.sh` checks the opt-in Music-like close against 9.1.90's compact transition doubles: staged geometry, velocity release, cancellation with the reversed fraction, and the off path's old numbers. |
| `native-player/build.sh` | iOS simulator UI; `sponsorblock` checks SponsorBlock's progress bar marks (`../sponsorblock/markers-check.m`, also run by `player/`'s `sponsorblock` scenario). |
| `onboarding/build.sh` | iOS simulator UI; generates fixture release notes only inside its output directory. |
| `page-previews/build.sh` | iOS simulator: the five page settings with their preview cards, in a simulator of the run's own; asserts what VoiceOver reads and writes PNGs. |
| `glass-choices/check.py` | iOS simulator screenshots judged with Pillow, in a simulator of the run's own: the redesign's glass in each material and tint, touch response on and off with the glass inside its button and in a holder beside it (Home's pill), Reduce Transparency, choices changed after a launch under Reduce Transparency staying the launch's, and Saved mark's Dot over reused, unsaved and saved-again rows. |
| `player/build.sh` | iOS simulator player UI; `timerow` checks subpixel progress sets and the held scrub capsule; `seek` checks the exact value delivered by a same-pixel tap; `lyric-line-chip-live` checks the idle lyric clock, paused seeks, late chip movement and the first visible line after full lyrics close; `lyric-line-long` checks that crossing the final portion boundary during placement does not skip the last words. |
| `playlist/build.sh` | iOS simulator UI. |
| `search/check.sh` | iOS simulator UI: the Browse page's cards closed up under the header and the list's end moved up with them. |
| `shortcuts/build.sh` | iOS simulator App Intents. |
| `sing/build-sim.sh` | iOS simulator audio chain and external model/voice. |
| `sing/button/build.sh` | iOS simulator mic-button UI; `-cardCheck 1` checks visible graph glide, no offscreen or inactive level reads, and visible and VoiceOver text after metadata-only reports. |
| `sing/download/build.sh` | Downloads the model over the network. |
| `spatial-page/build.sh` | iOS simulator UI. |
| `speed/build.sh` | iOS simulator audio chain; the normal-speed position check requires zero track reads with the speed clock idle. |
| `system-menu/build.sh` | iOS simulator UI. |
| `system-menu/pinned-check.sh` | Catalyst: the pinned ⋯'s claim through the real `SGRPinnedMore`, none from a press let go off it, the button and page from a tap before Spotify's ⋯ runs; drawn in the header info, its tap still gets the real `PlaylistMenu.x` Sort and Mix onto the taken sheet. |
| `tabbar/build.sh` | iOS simulator UI. |
| `tabbar/capture.sh` | iOS simulator screen recording, for a visual review frame by frame. |
| `tabbar/fade-check.sh` | iOS simulator UI. |
| `tabbar/glass-check.py` | iOS simulator screenshots judged with Pillow: the listener's glass on the tab bar's platters (main and split, expanded and minimized) and the now playing card, against Regular and None, and the tabs and the card's button taking taps with touch response on and off. |
| `tabbar/ipad-check.sh` | iPad simulator UI: tab names whole beside their glyphs, the fade down to the container's foot. |
| `update/build.sh` | iOS simulator and live GitHub requests. |

Excluded modes of otherwise included scripts: AutoEq `online` and translation
`--bing-live` contact services; full Sing needs a downloaded model and voice;
the audio-effects engine and haptics analyzer need external song/scoring inputs.
Optional user-supplied images, songs, saved provider replies and videos are not
used. Lyrics clips' `motion` scenarios require additional video/FFmpeg fixtures;
the default clip assertions remain enabled.
