# Working on the mod

## Layout

    tweak/                      the Theos project: Makefile, control, the bundle filter plist
    tweak/Sources/Core/         what every file builds on: logging, preferences, view-tree walking, glass panes, the
                                look this launch runs (SGUIMode.h), the forced-flag registry (SGFlagForce.h), whether
                                optional advance work may run (SGOptionalWork.h, with the Load ahead switch's key), the screen the app is showing
                                (SGTopController.h, shared by the phone driver and the keyboard) and C
                                functions Spotify imports hooked by rebinding its import slots (SGRebind.h)
    tweak/Sources/Headers/      reverse-engineered Spotify classes, one header each, only the selectors used
    tweak/Sources/Settings/     the Mod Settings framework: SGPage (a page on Spotify's stack), SGModPage (sections
                                of rows: switches, choices, sliders, links, rows shown only while a choice
                                asks for them, and rows grayed out while the switch they wait on is off, a tap
                                on one nudging that switch), SGPageStyle (the system Settings look), SGGlowSwitch,
                                SGMarquee (a title that glides side to side when it is too long, for every layer)
    tweak/Sources/Shared/       what works the same with either look, see Layers below
    tweak/Sources/Native/       tweaks on Spotify's own screens, running only while Redesigned UI is off
    tweak/Sources/Redesigned/   the redesign, running only while Redesigned UI is on
    tweak/Sources/App/          what brings the layers together: Mod Settings' root and composed pages, the Mod page,
                                backup and signing, the welcome tour
    tweak/Sources/Diagnostics/  screen dumps, the tree server, the phone driver and the main thread hang sampler of FLEX builds
    extension/LiveActivity/     the Live Activity widget, a WidgetKit extension of its own
    extension/AppGroups/        a dylib loaded by Spotify and its widget, Siri and notification extensions that moves
                                Spotify's App Groups and its extension-credentials keychain group into groups the
                                re-signed IPA has; without it the widget stays a placeholder and Siri asks to verify
    scripts/                    pipeline.sh (build + inject), build-extension.sh (the widget extension, without an
                                Xcode project), merge-appintents.py (the widget's intents into Spotify's), insert-dylib.py (a load command into
                                Spotify's extensions), install.sh (sign + install), record-trees.py, record-session.py,
                                dump-log.sh, extract-flags.py, check-layers.sh (the one-way imports between layers)
    trees/                      recorded view trees, one per screen; the input for every new hook. trees/clean/ holds
                                the numbered snapshots per screen of record-session.py, taken of Spotify as it came
    plist/                      Info.plist overrides merged into the app (turns UIDesignRequiresCompatibility off; the
                                Bonjour services are added to Spotify's own list by pipeline.sh)
    vendor/                     AutoFLEX deb; audio/, the third-party C of the audio effects (libbs2b, WDL's EEL2) and
                                the EEL2 parser of the mod's own, built by its own Makefile into a static library the
                                tweak links (its README names the upstream commits and the licenses)
    ipa/, out/                  decrypted Spotify IPA in, built IPAs out (both gitignored)

`tweak/Sources/Shared/Flags/SGFlagList.m` is generated from the IPA and gitignored, as are the
recorded trees: both are read out of Spotify's own binary and belong to whoever built them.

## SponsorBlock

`Shared/SponsorBlock/` skips community-marked podcast segments under either look. Mod Settings ›
Premium, ads & privacy › SponsorBlock has an off-by-default switch, also offered separately
from No ads in the welcome tour. Under Categories & behavior, choose Auto-skip, Ask, Show only
or Off for each category. `spotifyglass.sponsorblock.behavior.<category>` stores that choice
(0–3). If absent, read `spotifyglass.sponsorblock.category.<category>` without modifying
either key: on means Auto-skip, off means Off. With neither key, Sponsors, Self-promotion
and Interaction reminders auto-skip and the rest are off. The master, behaviors, manual seek,
minimum duration, skip haptics and progress bar switch are read at launch.
The API's Spotify episode-ID mapping, hash-prefix request, category set and skip/Undo boundaries
are adapted from EeveeSpotifyReincarnated (GPL-3, `0d9feaa`, also touched in `51cb2dc`).
The expanded rules follow upstream Vitrine (`d48c5f3b`); no custom toast, polling,
submissions, voting or mute actions are used.

`SGPlayerStateObserver.playerStateDidReport:` supplies the clock on main; the existing
`SGPlayer()` / `seekTo:` API performs the seek in seconds. There is no player-service hook,
audio-thread work, polling timer or display link. Between sparse reports there is at most
one main-queue wake. The playback rate and the next Auto/Ask start determine its deadline;
a seek into an actionable range gets one immediate landing check. Neither deadline nor
requested target authorizes playback: the wake, fetch completion and snackbar taps read
Spotify’s timestamped running position. Data older than our seek cannot confirm it. If
the wake cannot confirm a landing it looks again every 0.25 seconds for up to two seconds
after the seek, then waits for another report; a stale report keeps the deadline; a fresh contradictory
report establishes a manual seek and replaces the deadline. Pause, loading, music, disabling or having
no actionable boundary ahead leaves no timer running. Only `spotify:episode:` or an exact
`https://open.spotify.com/episode/` URI qualifies, including video podcasts; music is untouched.
Overlapping or adjacent Auto-skip segments form one continuous range; Ask, Show only and
Off never bridge automatic ranges. The first qualifying report or boundary wake within
it seeks to its furthest end plus 0.05 seconds (bounded by the episode duration), marking all
members handled and showing one notice. A stale pre-seek sample cannot trigger another
skip even if its extrapolated position has crossed the target. Segments shorter than the selected minimum (one second
by default) or outside the episode
duration cannot join a range; the final 0.25 seconds of a range are left alone.
Each UUID is skipped at most once while that episode remains in the recent-episode cache.
Spotify's existing timed action snackbar (`SPTSnackbarInternalPresenterImplementation`)
offers Skip for Ask. Respect manual seeks (on by default) also asks if the first report
after resuming is inside an automatic range or playback jumps there (more than two seconds
from the expected position at the reported speed). The model distinguishes its own seek
landings. An expired Skip cannot seek back into a range the listener has left.
After a skip the same snackbar supplies Undo, seeking to 0.25 seconds before
the whole range without re-skipping any member. Undo requires live evidence of the skip;
non-overlapping later ranges remain eligible. An Undo from another episode/playback visit does nothing.
The snackbar signatures are checked before installing its capture hook; if unavailable,
the feature logs once and stays disabled rather than skipping without Undo. Statistics count
one skip per seek and the remaining seconds skipped (not the seek padding). Undo subtracts
both, unless the counters have since been reset. Vibrate on skip defaults on and uses the
existing light Skip feedback when Vibrations › Controls is enabled.

`SGSponsorBlockVisibleSegments()` and `SGSponsorBlockEpisodeDuration()` are main-thread
readers for the progress bar. Subscribe to `SGSponsorBlockSegmentsDidChangeNotification`
on main (object: session), then read again; position reports alone don't change the
snapshot. It includes eligible individual Auto-skip, Ask and Show only segments in seconds,
not the merged skip ranges. Music has an empty list and zero duration. Gate rendering with
`SGSponsorBlockMarkersEnabled()` (launch-read `spotifyglass.sponsorblock.overlay`, default
on with SponsorBlock). These readers do not install any slider hooks.

`SponsorBlockMarkers.m` draws them on Spotify's progress slider
(`_TtCO17NowPlaying_ECMKit11ProgressBar6Slider`), after upstream's `SGSponsorBlockOverlay`: one view per
slider of SponsorBlock's standard category colors (upstream's defaults, not editable), placed by start/end
over the track, mirrored right to left. It sits behind the slider's own drawing, under the thumb: just above
Spotify's episode bar (`ProgressBar.AudioView`, chapters included, its frame and rounding) when the slider
holds one, else at the back on the slider's track rect; it takes no touches and VoiceOver skips it. It is
placed again only on the change notification (segments or duration) or when a layout pass finds the
slider's bounds, track, direction or episode bar changed; no timer or display link. A song, or no segments,
leaves nothing in the slider. Each look hooks the slider's layout and window entry in its own file, only
with the switch on: Native/Player/PlayerScrub.x at 0.7 opacity on Spotify's track, where the opaque played
fill covers the marks it passes when there is no episode bar; Redesigned/Player/PlayerControls.x at 0.8
under the translucent rail, as AutoMix's bands, taking the scrubbed track's height. `harness/native-player`
(`sponsorblock`, `sponsorblock-off` launch arguments) and `harness/player` (`HARNESS_SCENARIO` of the same
names) run `harness/sponsorblock/markers-check.m` against the real session and compare the drawn window.

Privacy: an ephemeral HTTPS GET to `/api/skipSegments/<prefix>` on the configured server
(default `https://sponsor.ajay.app`) sends only
the first **five hexadecimal characters of SHA-256 of the bare Spotify episode ID**,
`service=Spotify`, selected category identifiers as JSON, and the `X-CLIENT-NAME:
Retrine-SponsorBlock/1` header, plus normal HTTP/TLS metadata (including the network IP).
Neither the full episode ID nor account tokens, title, playback position, cookies or Spotify
headers are sent. The response's full `videoID` is matched locally, so hash-prefix collisions
cannot select another episode's segments. Requests and parsing run off main with a six-second
request/resource limit and a 2 MiB response cap; redirects, credential storage and cookies are
disabled. A custom HTTPS base needs a host and cannot include credentials, a query or a
fragment. Invalid stored addresses use the default; clear the server field to restore it.
The server address is install-local: settings export omits it, import cannot change it, and
diagnostic export redacts it. Changing the server affects new requests. The session keeps
only the four most recently visited episodes, including handled UUIDs and empty/failure
results; an evicted episode is looked up on return. Replies from a previous visit are
discarded. At most 200 segments per episode are accepted, with UUIDs of at most 128 UTF-16
code units. A failed lookup logs once while cached, without UI or automatic retries.
`harness/sponsorblock/build.sh` exercises fixture decoding, selection, skip/Undo, stale replies,
music/off isolation, failure caching, migration, Ask, markers, stats and request privacy
without a network or Spotify account. `harness/onboarding/sponsorblock-check.sh` renders
the settings and tour opt-in in English and Korean.

## Layers

The mod has two looks, picked by Redesigned UI at the top of Mod Settings: Spotify's own screens with the mod's
tweaks on them, or the redesign, which starts from a clean sheet. What does not draw on Spotify's
screens works under both. So the sources are four layers, each a directory of features:

    Shared/       works the same with either look
    Native/       Spotify's own screens tweaked; every %ctor starts with `if (!SGNativeUI()) return;`
    Redesigned/   the redesign; every %ctor starts with `if (!SGRedesignedUI()) return;`
    App/          Mod Settings' root and the pages that combine the layers, the Mod page, the tour

`SGRedesignAvailable()` (Core/SGUIMode.h) says whether the OS has the redesign's material, iOS 26 and up:
it is Liquid Glass, and `UIGlassEffect` is the system's, so on an older OS the glass calls fall back to a
blur and the redesign runs untested against an older UIKit (issue #37, an iOS 17 scene-update watchdog).
Below 26 the Redesigned UI switch stores `SGKeyRedesignUntested` instead, and turning it on shows what
the redesign risks there and restarts Spotify from the alert; the tour offers the redesign card too, Legacy
picked, with the same warning under the cards. `SGRedesignedUIStored()` answers YES below 26 only with
that key set. A launch with the redesign below 26 leaves a mark that the main queue takes off after 15 s
or as Spotify first leaves the front, so a launch that hung is followed by one in the native look, with both switches off. The stored key
is left alone on iOS 26, so a phone that updates gets its redesign back.

The two looks never run together, so each hooks the same Spotify class in its own way, and a part of
the look is edited on its own side without touching the other: where both need the same thing, each
has its own copy (the tab bar's composition and its editor, the lyrics page's glass, the soft top edge,
AMOLED, the accent color), under its own names (SG… native, SGR… redesign) and its own keys. The imports run
one way, Core <- Settings <- Shared <- Native | Redesigned <- App, and `scripts/check-layers.sh`, run
by tweak/Makefile before every build, fails on any other. A layer below that needs something from one
above takes it through a registry in Core (forced flags, SGFlagForce.h) or a function declared low and
defined high (SGOpenModSettings).

A feature is a directory in its layer holding everything about one area of the app:

    <Feature>.h            the keys of its switches, and the functions other files may call
    <Something>.x          the hooks, one file per screen or mechanism, each ending in its own %ctor
    <Feature>Settings.m    its Mod Settings page, or its sections for the page of the part it changes, built from
                           the rows in Settings/SGModPage.h; App/Pages.m puts them on the page
    <Model>.m              plain Objective-C the hooks and the page share, where there is any

Shared:

    AdBlock/      EeveeSpotify's ad blocking: the ad and upsell services silenced (AdServices.x), ad components out of the
                  Hub JSON (AdHubs.x) and the feeds (Feeds.m), Premium pop-ups dropped (AdPopups.x), and the responses
                  rewritten on the way in (AdNetwork.x, Premium.m over the protobuf walker in Protobuf.m, which refuses a varint over 64 bits), with crossfade
                  and automix switched on in the player core, the core and Settings both kept on the audio.crossfade
                  prefs rather than the account's Playback Settings, and crossfade's switch kept in step with its
                  slider (Crossfade.x).
                  Spotify 9.2.0 has no v1/customize: the account attributes come from nebula/v1/configuration/attributes
                  and the remote config from remote-config-resolver/v3/configuration. On 9.2 and later Spoof Premium
                  sends both without cache validators and rewrites them with the same attributes and flag rules
                  (SGPatchAccountAttributes, SGPatchRemoteConfiguration), after Pixie's offline values when Pixie is
                  loaded; a bodiless 304 passes as the server sent it. 9.1.x keeps the customize path
                  (EeveeSpotifyReincarnated 5f5c7ea, 7a8c573; harness/adblock/offline-check.m splitCases).
                  Hide ads also cancels ad tasks before resume, including terminal /ads routes, without
                  Spoof Premium or its startup delay; Esperanto matching still uses whole tokens.
                  SPTDataLoaderService, HttpClientURLSession and SPTCoreURLSessionDataDelegate all receive
                  one synthesized empty HTTP 200 response, empty data and one successful completion for
                  blocked ads, including pre-send cancellation. An existing response is not delivered
                  twice. An asynchronous response decision returns data/completion to the session's
                  delegate queue; a rejected response completes as canceled instead. Unknown delegates
                  and completion-handler requests retain Foundation's cancellation contract.
                  EeveeSpotifyReincarnated 43b9ca3/350aa15 supplied those gaps; d4daa49 supplied six
                  additional -load targets verified in the decrypted 9.1.90 binary: AdsBaseSwift,
                  AudioAdPictureInPictureCoordinator, RewardedAdFetchController, OnDemandAdEventLogger,
                  AdOnAppOpen and EmbeddedPlaylist. AdServices.x installs each service only if its class,
                  instance selector and void/object ABI match; an inherited method is replaced only on
                  the target class. View fallbacks also require UIView ancestry and a matching selector.
                  Embedded CTA cards retain registerScrollProviderIn:, not a nonexistent -load.
                  The upstream realtime, instrumentation, element, native-element, shuffle-toggle and
                  full-song services have no Objective-C -load in 9.1.90, so their new hooks are not ported
                  (including 2a9d4ae). Targets without -load in either supported build are not installed. DI services,
                  regulatory notices and 9.2-only renames are untouched.
                  Run harness/adblock/build.sh for Hub, DJ, service-guard and pre-send checks; run
                  python3 -B scripts/audit-ad-services.py ipa/Spotify-9.1.90.ipa for class/selector coverage.
                  The audit adapts Eevee 1010573/7a617a7/e2abe5a: every discovered intended service must
                  have an installed selector with compatible ABI and the independently specified
                  ads/upsells gate, or an explicit protected/no-load exemption, with no-load
                  exemptions checked against the binary. It includes AudioAd services.
                  This is static 9.1.90 evidence, Foundation doubles and a real macOS URLSession with
                  a local URLProtocol transport, not device playback evidence.
                  With Spoof Premium on, the DJ's eligibility check answers yes, which keeps the full DJ with requests; a
                  Free account is then told "DJ is not available in your country" at each start while the DJ plays on, so
                  that dialog alone is closed before it shows (DJ.x: a PopUpPresentableContainer whose title equals the
                  region dialog's title in Spotify's own SPTStrings.bundle, English and the app's languages; read once;
                  closed through SPTEncorePopUpPresenter without clearing its queue). Any other pop-up, or a missing title
                  in the strings, is left alone. Checked by harness/adblock/dj-check.py.
                  With Spoof Premium on, RadioModes.m requests shuffle and repeat overrides for radio/autoplay in either look:
                  only restrictions made entirely of radio, endless_context and autoplay are allowed.
                  Raw reason sets remain intact when Spotify copies its state. Positive radio evidence survives
                  empty optimistic updates only for the same playbackId/contextURI; explicit non-radio reasons revoke it. The matching
                  command's ESP request gets overrideRestrictions before the core receives it; other restrictions
                  and commands stay as Spotify supplied them. The hooks install together only when the expected
                  runtime signatures match. Checked by harness/radio-modes/; its README records device evidence.
                  On 9.1.90, autoplay continuation reports {autoplay} for all three toggles; despite the serialized
                  override, the core answers Code=101 and leaves shuffle/repeat as Spotify set them there.
                  Normal album/playlist/search playback and the tested Dawn FM track-menu radio playlist have
                  empty reason sets and toggle normally without an override.
    AlbumQueue/   With Spoof Premium on, adds Add to Queue to an album page's header menu when Spotify leaves
                  that row out, under either look. The Creative Work page's template.creativeWork.uri is read
                  by named Swift reflection and checked against the header's menu button; a track menu is
                  never inferred from the page it happens to be on. Native marks the header button just before
                  UIKit dispatches its registered touch-up or primary action (target/selector or UIAction);
                  the redesign marks the original button before its pinned mirror fires it. One marker is
                  consumed by one menu. Spotify's context resolver supplies the ordered track URIs, including
                  repeats, then SPTPlayerQueueWrapperImpl's queueMultipleTracks:loggingParams: submits them
                  with Spotify's own queue handling. Account attributes and restrictions are unchanged.
                  A missing page or malformed response fails before submission; paginated answers are
                  currently rejected rather than queueing part of an album. Checked by harness/album-queue/;
                  Spotify 9.1.90 simulator evidence and the remaining device checks are in its README.
    Privacy/      telemetry blocking and its counters, and the tracking taken off shared open.spotify.com links
                  (CleanLinks.x over the cleaner in CleanLinks.m), a Messages compose body included
    ArtistBlock/  tracks by blocked artists skipped as they start (ArtistSkip.x), the list and the Blocked artists page under Player;
                  single songs blocked from the redesigned player's ⋯ menu (Block This Song, kept by URI on the phone and
                  active whatever the artist switch says) are skipped the same way and unblocked by a swipe on Player ›
                  Blocked Songs. Artist and song skips share one budget: after five skips in ten seconds the track is left to
                  play, so a queue that is all blocked cannot spin. With nothing blocked the now playing hook returns at once
                  (a flag kept in step with the list)
    Flags/        Spotify's remote-config flags: the provider hook, the generated table, the All flags page and the Labs page;
                  Labs also offers AI badges and its dependent Likely AI badges, both off by default
                  (unlike Chroma). They enable Spotify's own classification badges on artists, search and rows;
                  off leaves the server's values alone. They use the forced-flag registry and require a restart.
                  Mod › Storage uses that registry for ios-settings-connectivitypageplugin-impl.show_cache_limit_item
                  (on by default, off after a reset). It exposes Spotify's control without setting a limit.
                  On 9.1.90 the provider pins ios-reprise-liquid-glass-override.mode to default in both looks (after an All flags
                  override) and logs the server's own value once, as a force_disabled would take the glass off the redesign.
                  It also pins 9.1.90's ios-navigationui-tabbar-impl.is_liquid_glass_tab_bar_enabled off in both looks.
    Gestures/     the double tap zones on the player: the grid, what each cell does, the recognizer (each look hooks it on);
                  and the hold on either side of the cover (GestureHold.m): `spotifyglass.gestures.hold`, on until
                  switched off, and `spotifyglass.gestures.hold.speed`, 1.5×, 2× (the default) or 3×, read when a hold
                  begins, the speed from before the hold restored on release; harness/gesture-hold/
    Lyrics/       Newly measured layouts in the redesign compute sung/active lines from the current playback
                  position before placement, including restyles and resizes; previews, plain lyrics and unknown
                  positions skip the refresh. No new timer is used.
                  The lyrics engine for the redesign's Apple Music style lyrics and the lock screen: lines read from
                  color-lyrics and the published player state (KaraokeSource.x), words timed by Spotify's syllable clocks
                  when a song has them and otherwise by estimate inside Spotify's line times (KaraokeTiming.m, which splits Thai, Lao, Khmer and Burmese at the system's dictionary words), which line to name where two voices sing at once (the one that came in first,
                  for the lock screen and the Live Activity), a line in another alphabet in the alphabet chosen, Latin
                  letters or Hangul, offline by Apple's transforms, kanji read the Japanese way in a song with kana
                  (Romanise.m; checked on the simulator by harness/lyrics' -romanise and on the Mac by
                  harness/hangul-pronunciation/), and the Lyrics page's parts. Lines are kept in time order
                  whatever order a source lists them in. LyricsStore.m also keeps received non-local lyrics and their
                  provider in binary versioned plists under Library/Application Support/Retrine/Lyrics, keyed by
                  SHA-256 of the track ID and excluded from iCloud backup. The default-on “Keep lyrics for offline
                  listening” reads these before asking any source, across relaunches and without a connection;
                  a provider's own translation lines and its credit links are kept with them (registered only once a
                  restored answer is accepted). Each translation line keeps the language it was picked under
                  (SGKaraokeLine.translationLanguage); when a specific Translation language is chosen, restored lines
                  whose language differs or is unknown lose their translation and keep the lyrics, so the source
                  for the chosen language is still asked. The live keeper applies the same rule when the target
                  changes and when a provider's worker result arrives, without changing the source's cached lines.
                  A community reply for a superseded target is ignored. Community translations, including cached
                  replies, pass through the keeper so offline saves and paused lock-screen notifications include
                  them. Under Any they are all kept. Generated translations and AI pronunciation stay with their own
                  stores. File work runs on one
                  utility queue. The store caps at 1000 tracks / 30 MiB. Sheets saved for Pixie downloads are
                  evicted first, oldest-modified first, whenever a playback write needs room; pruning playback-saved
                  entries to 90% of both caps happens at most once a minute (hits touch the date; a playback write
                  that would need it within that minute is skipped). Pin changes and Reload lyrics delete
                  the old file. Turning the switch off leaves files intact; “Delete saved lyrics” removes them and
                  shows the remaining size. The codec and eviction checks run in harness/lyrics-store.
                  The opt-in “Save lyrics for Pixie downloads” (PixieLyricsQueue.m, after EeveeSpotifyReincarnated
                  eddb1c2) needs that switch and Pixie: the companion reports verified download completions, the
                  downloaded IDs and verified removals, and one low-priority queue asks the usual sources for each
                  missing track without touching the player, saving into this store. Definite misses are kept per
                  track and source, temporary failures and rate limits wait until the next day or the server's
                  Retry-After, and a rejected key pauses that source. The ledger (PixieLyrics/queue.plist beside
                  Lyrics, backup-excluded, no credentials) survives relaunches; Delete saved lyrics also clears it and
                  keeps the downloads present at that moment from refilling. A removed download drops only a sheet
                  the queue saved. Spotify's own offline lyrics database is not written (harness/lyrics-sources). The Lyrics page's Delay (Timing, 0 to 1000 ms, either look)
                  shows every line that much later than the song, for Bluetooth headphones: whatever times lines
                  against the position takes it off first (the redesign's lyrics view and its word sweep, the lock
                  screen's line and artwork, the Live Activity, the native look's lyrics page for local files), and a
                  tap on a line seeks to its start plus the delay. Karaoke's audio, the scrubber and the lyrics preview
                  are left alone. It is read at every use, so a change applies at once (checked by harness/lyrics' -check).
                  In the redesign's Lyrics → Display section, “Smooth lyrics (120 Hz)” is on by default: the lyrics
                  display link and instrumental break animations request 80–120 Hz, preferring 120. Turning it off
                  requests 30–60 Hz, preferring 60, to use less battery. Only ProMotion displays show a difference.
                  The switch applies to the open page immediately. The link still pauses when nothing moves and
                  is put down during player transitions and while the app is inactive. Plain
                  (untimed) lyrics pause the link as soon as the rows in sight are filled, with no repeating poll: scroll,
                  layout, player and keeper events wake it. Keep screen on releases five seconds after playback stops
                  advancing, including a zero-speed stall, and is held again when playback advances. With EeveeSpotify injected (SGEeveeSpotifyInjected), its lyrics
                  answer Spotify's requests and the mod's sources and its own requests stand aside. On top of the Delay, an
                  offset per song (SGLyricsTrackOffsetMs, the newest 500) and one per output (SGLyricsRouteOffsetMs, by the
                  port's UID, none for the iPhone's own speaker), each -5000 to 5000 ms and set from the redesign's Sync
                  sheet, both cached in memory and the route read again on a route change. Pronunciation alphabet
                  (SGKeyLyricsPronunciationHangul, off; the row under Pronunciation on the redesign's Lyrics page)
                  picks Latin, today's readings, or Hangul, which reads Japanese and Chinese lines in Hangul offline.
                  Japanese goes through the reading
                  Romanise.m already had, then kana to Hangul by a table of its own: small kana combine with the kana
                  before them (きゃ 캬, てぃ 티), っ adds a final ㅅ to the syllable before (きって 킷테) and ん a final ㄴ
                  (さんぽ 산포), ー repeats the previous vowel as a syllable of its own (らー 라아), katakana reads as
                  hiragana, and the kana are aspirated throughout and voiced ones plain (か 카, が 가); Chinese keeps
                  Apple's Mandarin reading with its tones off and then pinyin to Hangul by Korean orthography's initial
                  and final table (zhong 중, xi 시, qu 취, si 쓰, er 얼), a syllable it cannot place left in Latin
                  letters. Only the source script's own runs are read, so an English word spelled like pinyin stays as
                  it is and other scripts keep their Latin reading. Every reading input (Hangul, hiragana, Latin and furigana
                  alike) is cut into segments of at most 4,000 UTF-16 units that never split a surrogate pair or a
                  combining sequence, a single grapheme over that budget passes through unchanged, and the segments'
                  readings are joined with their separators kept. Hangul replaces the Japanese reading; Korean lines are already Hangul. With Japanese reading set to
                  Hiragana, a Japanese song's kanji are read in hiragana instead of romaji, and Furigana
                  (SGKeyLyricsFurigana, off) gives each run of kanji its reading in hiragana with the okurigana left out
                  (SGLyricsFurigana, read from the whole line, so a kanji a source hands over alone is read in its
                  word). The redesign's lyrics view takes both readings from SGLyricsPrepareExtras (Romanise.m), run on its layout
                  worker and never on main, with the explicit reading choices copied as a snapshot for the job: the
                  generated pronunciation as timed words, each token of the line anchored by its range to the source
                  words it overlaps and taking their clocks (tokens inside one source word share one reading word, so no
                  sub-word time is invented), and the furigana. The result is immutable and kept by the line's text and
                  word clocks and the choices, 1,000 at most; Japanese is told by the song's language (LyricsLanguage.m),
                  and a provider's own pronunciation stays the first choice. LyricsLanguage.m tells a song's language from its lines (NaturalLanguage, kana meaning
                  Japanese), keeps one the user picks per track (the newest 500), and keeps rules per language: whether
                  its songs show the translation and the pronunciation, set from the lyrics' menu and applied as each
                  song in it comes in. SGLyricsReload drops everything kept for a track and asks again, a pin kept.
                  SGLyricsSimplifiedTitle takes trailing extras off a title ((feat. …), [Remastered], - Live Version,
                  fullwidth brackets and Korean ones too). A line can carry a cultural note (SGKaraokeLine.note). The
                  sync and state features are checked on the Mac by harness/lyrics-sources/state-build.sh
    LyricsPiP/    opt-in Picture in Picture lyrics over other apps (spotifyglass.lyrics.pip, off, restart
                  required). Both player more menus offer open/close, or activation guidance when disabled.
                  The redesign's Lyrics options menu and native full-screen lyrics corner button remain.
                  Its settings row opens a page with the enable switch and independent background controls.
                  Only a tap starts it; a retained shared engine
                  draws the current and next lines, available saved/source pronunciation and translation,
                  song metadata and the full provider credit into a bounded CPU pixel
                  buffer pool, following Spotify's clock minus the lyrics delay. Frame drawing and text
                  fitting live in LyricsPiPFrame.m, with the shared CPU background renderer. LyricsPiPStyle.m
                  supplies square (640×640, default), landscape (800×450) and portrait (480×720) layouts,
                  cover/metadata visibility, alignment and independent PiP font selection from existing
                  system, imported and library families (the font page asks for the downloaded and
                  imported families when it opens, and each one's row shows, without scrolling the
                  page, once it is registered; a PiP font whose family is not registered yet starts
                  the registration off main and draws in the system font until
                  SGFontLibraryChangedNotification lands,
                  and the app font Fonts.x registered at launch resolves at once; nothing in
                  LyricsPiPStyle.m registers with Core Text on main, checked by harness/fonts/).
                  Original, pronunciation and translation each
                  have size/weight controls; defaults are 40/semibold and 26/regular for both supplements.
                  Text wraps and shrinks within its own box, with visible ellipsis when it still cannot fit.
                  The native Layout/Text/Background settings page previews the production renderer.
                  Font and per-role size/weight pages keep that sample pinned above the settings while
                  editing; the weight menu stays on the page. The sample respects the lyrics screen's
                  translation/pronunciation switches without changing them or sending requests, and
                  a supplement's page explains when its line is hidden. Reset keeps background and
                  display switches intact.
                  Display/language rules govern supplements; opening PiP starts no translation or AI request.
                  Layout and typography changes update paused frames and resize the pool when needed.
                  Untimed lyrics never
                  claim a current line. Which text shows is decided in LyricsPiPText.m, checked on the Mac
                  by harness/lyrics-pip/. Its 4 Hz timer runs only while PiP is active and playing, and only
                  changed content or background is drawn. LyricsPiPBackground.m loads the current URI's
                  artwork through SGShownTrackArtwork and prepares backgrounds off main, rejecting stale
                  replies; late covers and paused settings changes refresh the frame. A frame the layer or pool turns away is retried every 0.1 s
                  while starting or active. Authoritative cover loads for PiP and lock-screen lyrics
                  get at most one immediate retry while the track/source and feature remain current.
                  A second failure keeps the shared solid fallback without recurring requests or
                  resetting the retry budget on unrelated settings changes.
                  Closing never pauses Spotify. PiP uses Spotify's existing
                  audio session unchanged; unsupported/failed starts show an alert. Returning to Spotify
                  offers linked provider credits. Skip controls acknowledge settled Spotify position reports
                  rather than command dispatch, preserve intent through seek loading, and never blindly resume
                  a paused song; timeout, track change and cancellation also release the pending completion.
                  The Live Activity ends while PiP is active and resumes
                  when enabled and playing, once Spotify is in front (ActivityKit cannot start behind
                  another app). No automatic start, translation generation or word highlighting.
    LyricsBackground/ shared CPU-only cover, monochrome, blur, album-color gradient and solid renderer,
                  with independent spotifyglass.lockscreen.background and spotifyglass.lyrics.pip.background
                  preference prefixes. Defaults: clear cover, 45% darkening, blur 20, solid RGB 18181B; the
                  lock screen's prefix defaults to the blurred cover at blur 60 (soft colour fields), and a
                  stored choice is kept. Darkening ranges from 0 to 85%, blur from 0 to 100 at a reference
                  width of 640; the color
                  picker is shown only for Solid. Sharp modes render at the target size, not through a small
                  blur buffer. Cache identity includes source, normalized style and raster size; no cover
                  uses a dark fallback. Rendering uses CoreGraphics and Accelerate, not background GPU work.
                  Checked by harness/lyrics-background/ and the PiP and lock-screen harnesses.
    LyricsSources/ the sources lyrics come from, asked in order or all at once and merged into the
                  best answer (LyricsSources.m, the list to drag in LyricsSourcesPage.m): Apple Music's TTML from
                  BiniLyrics.m (now lrc.red: first the TTML filed under Spotify's ISRC for the track, from
                  SGSpotifyISRC in Haptics/SystemMusicHaptics.x, else its search by name) and Unison.m, read by SGTTML.m,
                  which carries a second voice and the backing vocals (in a document whose root says byModel="true",
                  any prefix, a line with no x-bg span has its parenthesised runs of words moved to its backing row,
                  unless a run is never closed or nothing would be left of the line), and in its head Apple's translation and its
                  pronunciation of a line, each keyed to the line by its itunes:key or lrc:key, the pronunciation
                  timed word by word (the translation taken in the Lyrics page's language); Musixmatch.m, matched by
                  Spotify's track id with an anonymous token, word timed where it has richsync; NetEase.m, word timing from yrc for what the others only line time; LrcLib.m, open and
                  keyless and timed by the line, by the word where a record carries a Lyricsfile (Lyricsfile.m reads its YAML), the floor under the rest; its search answers with whole songs, so only a record that is the track (SongMatch.m) can win. SpicyLyrics.m, Spicy Lyrics' Developer Platform
                  by track id on the user's own publishable key (Keychain), syllable timed where it has a sync, with
                  its pronunciations and translations; its credit, which its terms require, shows whatever Show source
                  says and opens the uploader's and maker's pages from a tap (both looks), its answers and misses are
                  kept per track, a rate limit is waited out and a refused key is left for 10 min, its reason on the
                  source's row; checked on the Mac against harness/spicy-lyrics/. QQMusic.m (word timed QRC, asked as crypt=0 and read as base64 of UTF-8 or zlib, 1 MiB at most, its clocks
                  checked to be digits in time order; a payload that is not QRC, or has a malformed clock, reads as plain
                  LRC the way LRCLIB's does, and a reply with nothing is asked again without QRC) and KuGou.m (word timed KRC, unpacked with
                  zlib and read by NetEase.m's parser) for Chinese and other Asian songs, matched by title, singer
                  and length. A singer matches by SGLyricsSameArtist (SongMatch.m): joined credits and aliases in parentheses count,
                  and a name under four characters matches another name only at its edge or as a whole credit, never inside
                  it; NetEase.m also takes only a song whose title is the track's. Every provider reply is decoded, and the
                  QQ and KuGou ones parsed, on the transport's worker thread (SGLyricsGetJSONTransform), and only the finished
                  value goes to main, where the caches and the walk live; checked on the Mac against harness/lyrics-sources/. Also: LyricsPlus.m (word
                  and syllable timing, backing vocals, prjktla.my.id then binimum.org), Bugs.m and Genie.m (Korean catalogs, line timed;
                  Genie requests the desktop site to avoid a mobile redirect),
                  PetitLyrics.m (Japanese and some international catalogs, base64 plain text or WSY with word clocks retained;
                  type-2 binary sheets are requested as type-1 plain text, following Eevee, rather than claiming LRC timing;
                  title/artist and four-second duration matching, closest matching candidates tried asynchronously;
                  uses the shared cache, failure backoff and bounded transport, with XML parsing off main),
                  and Deezer.m on the user's own ARL in the Keychain, off until one is set, its JWT kept in memory and
                  renewed once on a refusal; their requests go through SGLyricsSourceRequest, which caps a reply at
                  2 MiB, follows no redirect and keeps no cookie. LRCLIB, LyricsPlus, Genie and BiniLyrics decode their
                  replies and build lines on a worker; finished results come back to the main thread for the cache
                  and the walk. TTML translations keep the language filter they were picked under
                  (SGKaraokeLine.translationLanguage, nil for Any or unknown). A track can be pinned to one LRCLIB record picked by
                  hand (SGLrcLibSearch, SGLyricsPickRecord, which prepares the record off the main thread and pins it only if
                  that pick is still current), asked by its id before the walk; Automatic (SGLyricsUnpin) drops
                  the pin and everything kept for the track. Each source can be held to the lyric types it gives
                  (SGKeyLyricsSourceTypes: any, synced only, word synced only), an answer it should not give being dropped
                  before the merge. How sources are asked (SGKeyLyricsAskMode) offers In order (0), stopping at
                  the first timed answer; Word timing first (1, default), asking sequentially for word timing
                  with ties going to source priority; and All at once (2), sending more requests in parallel
                  and keeping the first word-timed lines to arrive. Timed lines release the card while finer
                  timing is sought. All at once waits for synced page text alongside word-timed lines, or
                  exhaustion, and only accepts instrumental at exhaustion if no lyrics arrived.
                  A name search that finds nothing at all for a title carrying a film or soundtrack note
                  ("(From \"…\")", "- Original Soundtrack", "OST") is asked once more with the song's own title
                  (SGLyricsInvoke, SGLyricsBareTitleWithOptions; version notes such as Live or Remix stay), never
                  after a failure or a rejected match, nor for Spotify-ID or ISRC lookups. BiniLyrics prefers a
                  candidate whose duration is known and close, LRCLIB breaks equal-distance ties, and Spicy
                  lines with null bounds take them from their words.
                  The old Type first boolean migrates to 0/1. Saved source orders track known providers:
                  new providers are inserted once at their default relative position, without restoring disabled known
                  providers or enabling an empty order. PetitLyrics is inserted before LRCLIB. Unset
                  orders prioritize Imported lyrics, Spicy Lyrics, BiniLyrics, LyricsPlus, Musixmatch, Unison,
                  Deezer, NetEase, PetitLyrics, LRCLIB, Bugs, Genie, QQ Music, KuGou and Genius. Genius.m, last: untimed words for a track no
                  other source has, the song found by the search the line meanings share (SGGeniusSongIn in SongMatch.m, whose match LRCLIB's search shares too)
                  and the words read from its embed script, which is scraping (no API gives the text); checked on
                  the Mac against harness/genius-lyrics/. color-lyrics is answered with whichever won
                  (LyricsHook.x): Spotify's own 200 gets our lines swapped in; a track Spotify's metadata says has none has
                  its request sent to a donor track that does, so the reply is a real 200 (a 404 answered as a 200 in the
                  delegate alone never showed the card on 9.1.78); a 404 for a track not seen yet is held until the chain
                  answers. The card list the server sends per track (scrollsita) carries a lyrics section only for tracks
                  Spotify has lyrics for, so one is added to any list without it: that is what makes the player ask for the
                  lyrics and show the card. has_lyrics is forced on for every track, the walk starts at the track change
                  for it and the next, and the player's card-loading timeout flag is forced to its 5 s maximum while a
                  source is on. The next track's walk is optional advance work and stands down while Core's
                  SGOptionalWork.h says it must (Low Power Mode, serious or critical heat, no usable network, Low Data
                  Mode, or the Player page's Load ahead off); nothing is queued then. The up-next track is the player's first
                  future item when it is a track other than the current one (SGPlayerUpNextIn), and a change of it, or of
                  any setting, re-targets the walk (playerUpNextDidChange:), so a skip or a queue change asks for the new
                  next track. Lyrics are small,
                  so an expensive cellular network alone does not stop them. In the redesign, with a translation language chosen, lines kept for the lyrics view with
                  no translation of their own take Musixmatch's community translations (Musixmatch.m), whichever
                  source won, Spotify's own included: matched by the line's folded text, as copies kept in place of the
                  lines (KaraokeSource.x), which the view picks up. The default Word timing first mode asks
                  sequentially for word timing; In order and All at once follow the rules above.
                  Automatic answers remain provisional while outstanding work or a failed eligible source
                  could change the selection. Each provider invocation carries its own failure outcome,
                  including search/fetch subrequests. Missing lyrics and an unconfigured Spicy Lyrics or Deezer
                  credential are not failures; a credential read error or rejection is.
                  Each adapter (including a pinned LRCLIB lookup) has one five-second deadline across
                  its subrequests. Expiry cancels tracked tasks, falls through and ignores late delivery.
                  Sequential modes hedge an unanswered source after two seconds, showing a usable later
                  answer provisionally while earlier requests can still win under the selected priority/type
                  policy. Fast failures advance immediately. An eight-second initial-walk budget bounds
                  starting new work and releases the current answer; no usable answer means the retry state,
                  not a catalog miss. Already-started requests keep their own five-second deadlines: a usable
                  late reply replaces the retry state, and an eligible higher-priority reply replaces provisional lyrics.
                  These timing constants live together in LyricsSources.h: paired direct/Proton probes
                  measured 0.9–1.65 seconds per tunnel hop and about 2.5–3 seconds for multi-hop adapters.
                  All at once retains its arrival-based winner policy.
                  HTTP refusals (except explicit catalog 404 misses), empty transport bodies and malformed
                  JSON are failures, not permanent missing-track entries. Genius is skipped only when
                  usable lyrics exist, never merely because Spotify metadata promises lyrics.
                  LyricsPlus reads upstream RTO/BAD statuses even in a 404; Musixmatch's nested matcher
                  errors, QQ's search errors and Deezer's GraphQL errors/null track are failures too.
                  Healthy misses and missing timing capabilities still continue without marking the service
                  broken. Credential refusal uses the provider's existing one-time refresh where available,
                  then pauses it for ten minutes (credential changes clear Deezer/Spicy's pause); Spotify
                  waits for a different captured authorization rather than retrying the refused one.
                  When no usable answer exists and any source failed, the lyrics page offers
                  “Couldn't load lyrics · Retry” (“가사를 불러오지 못했어요 · 다시 시도”), separate from
                  genuine absence. Retry uses the shared keeper, so karaoke, PiP and lock-screen consumers
                  receive the same recovered sheet. Existing good sheets remain usable after a failure.
                  Both source and Spotify-loss retries stop after four backoff attempts; explicit retry
                  retires stale work rather than starting a recurring UI timer. WireGuard routing is unchanged.
                  Provisional sheets are shown but never saved offline. Only the relevant failed sources
                  are retried, after 10, 20, 40 and 60 seconds; an exhausted answer stays memory-only.
                  A recovered or confirmed winner is saved with its own credit for the next playback.
                  During the current playback, only a higher timing tier can replace the displayed sheet:
                  equal-tier priority changes, page text and credit wait until the track leaves playback,
                  including a transition to no track. Pause, backgrounding and seeking are not boundaries.
                  Translation refreshes cannot save provisional sheets or overwrite a pending winner.
                  Persistence authority belongs to the delivered sheet, survives source-cache eviction
                  with the keeper, and rejects late donor replies from an older sheet. A recovered track
                  name resumes deferred searches; page text is selected independently of karaoke timing.
                  Recovery and next-playback promotion preserve finer Spotify timing.
                  Reloading, choosing a source, returning to Automatic, pinning and eviction retire
                  the old recovery and its deferred writes. Existing offline entries are not migrated;
                  reload them from the player's ⋯ to ask the sources again.
                  Prefer word-by-word timing (off by default) changes In order mode only: it asks on for
                  word-timed lines, otherwise keeping the finest timing found with ties going to source priority.
                  In either sequential mode, a timed imported LRC above every source as finely timed ends the walk
                  too (#111); All at once keeps its first-word-timing race. The redesigned
                  player's ⋯ has Lyrics Source (LyricsPick.m): every source asked at once for the song playing, a pick
                  shown at once and kept in memory until Spotify quits, and Automatic putting back what the order chose
    LyricsTranslation/ a song's lines translated from the lyrics' corner menu, for the lines no source translated, three
                  ways, each its own item: on the iPhone by Apple's Translate (iOS 26, the song's language told by
                  NaturalLanguage, both languages downloaded: a missing pair brings up Apple's download sheet, and if they are
                  still missing the alert offers Open Settings) and by Apple
                  Intelligence's model (iOS 26 where it is on and speaks the language; permissive guardrails for changing
                  the user's own text, 12 lines a session, greedy and capped at 60 tokens a line, exactly one string a line by a generation schema; Translate retried once, as its first ask can fail while it loads), both in
                  OnDeviceTranslation.swift, the frameworks weak linked; and by Gemini on the user's own key (Keychain),
                  whose prompt and menu item say the lyrics go to Google. Translate on iPhone and Apple Intelligence each have a switch
                  on the Translation & AI page's Services (SGKeyLyricsTranslateOnDevice, SGKeyLyricsAppleIntelligence, both on), and off
                  leaves that translator out of the menu and out of automatic translation, which moves on to the next in its order.
                  A translation that reads the same as its line (SGLyricsBareText) is not drawn under it, on the lyrics page, the lock
                  screen or Picture in Picture, and the line still counts as translated. The translate items show for every song with Translate any song on (SGKeyLyricsTranslateEverySong, off), else only for a song NaturalLanguage finds in another language than the Lyrics page's (or the iPhone's): one distinct line in five it is at least 80% sure of, or two in another script (a verse in Hangul among English), not the whole song's guess (short lines sway that: Havana reads as Dutch), so songs half in English count and a repeated chorus weighs as one line; Translate on iPhone translates from the language most of those lines are in and leaves lines already in the target as they are. Apple Intelligence's lines show and are saved a batch at a time, only lines without a translation are sent, and a batch it turns down is skipped (asking again sends only those lines). SavedTranslations.m keeps generated mappings by the original line text in Application Support, without count eviction. Each line knows whether its translation was made here (SGKaraokeLine.translationMade); source translations stay intact, and syncing removes a generated translation only when its saved mapping was removed. The management page posts SGLyricsTranslationsDidChangeNotification after changes so open lyrics refresh. Gemini's reply read and checked on the Mac
                  against harness/lyrics-translation/. DeepL.m (the user's own key, free or pro endpoint by the key),
                  OpenAITranslate.m (any OpenAI-compatible chat endpoint, HTTPS, or HTTP for localhost, .local or a Tailscale IPv4 address; base URL and
                  model in the settings, the key in the Keychain), GoogleTranslate.m (Google Translate's keyless web
                  endpoint, off until switched on) and BingTranslate.m (Bing Translator's web page, keyless, off until
                  switched on: its IG, IID and abuse token read from the page, kept until 30 s before they expire and read
                  again when Bing answers a request with a statusCode) add their items to the same menu, with
                  ClaudeTranslate.m (Anthropic's Messages API, the user's own key and model) and presets for the
                  OpenAI-compatible service (OpenAI, OpenRouter, Groq, Perplexity, Pollinations or Custom). Gemini, Claude
                  and the OpenAI-compatible service each take one row of the Translation section, which opens its page
                  (AIModelsPage.m): the key and the model, and for the OpenAI-compatible service the preset, the address
                  and separate Check connection and Test translation actions. Model lists what the service offers for the saved key (Gemini's models that
                  generate content, Anthropic's /v1/models, the base URL's /models; one try, 20 s, 8 MiB), kept for the
                  launch by address and key, filtered as it is typed, pulled to load again, and Enter a model takes one by
                  hand for a service with no list. The IPA overlay adds the scoped Tailscale IPv4
                  100.64.0.0/10 HTTP exception required by newer ATS policies; scripts/merge-overlay.py
                  preserves Spotify's other transport policies rather than enabling arbitrary HTTP.
                  Model-list network failures distinguish ATS refusal, DNS, refused connections, timeout
                  and disconnection without exposing credentials. Gemini's model (SGKeyLyricsGeminiModel) defaults to gemini-4-hydrogen.
                  Its own settings page adds Thinking (Low, Medium, High; default Low) and Timeout (30–300 s;
                  default 120). These tune Gemini without replacing the fork's separate AI providers, and thinking
                  participates in Gemini's per-launch translation cache identity. AIServices.m
                  asks Gemini, Claude or that service for two other jobs, on the user's own key: how each line sounds,
                  in the translation language's letters, Latin letters or IPA (SGKeyLyricsPronunciationNotation), and a
                  one-sentence cultural note for the few lines a listener would miss (SGKeyLyricsCulturalNotes, off);
                  The lyrics menu keeps its translator choices after a generated translation, under Translate Again.
                  Lyrics → Translation & AI → Services has one shared Translation prompt row.
                  It edits the style instruction for Gemini, Claude and OpenAI-compatible lyric jobs;
                  titles, prose, pronunciation and cultural notes stay unchanged. The app retains the indexed-row
                  contract, exact count/order, empty rows and untrusted-lyrics rules. Edited text is explicitly
                  subordinate style guidance, followed by the fixed format/data rules. An unset prompt produces the
                  same request text as before. {language} is replaced literally with the target language, never
                  interpreted as a format string. Save accepts at most 4000 UTF-16 units; blank or default text
                  removes the setting, and invalid restored values use the default. Each job snapshots the
                  instruction into its per-launch memo identity, including repairs; saved track/language keys
                  are unchanged. Use Translate Again to replace an existing saved translation. Restore default
                  changes the editor's draft; Save applies it and Cancel discards it.
                  Switching service replaces generated translations as answers arrive, while source translations and
                  the previous answer to a failed line stay. Durable storage now uses the same JSON filenames in
                  Application Support/Retrine/{Translations,AI}, with backup-eligible, after-first-unlock protection.
                  There is no record-count eviction: active records, recovery copies and metadata share a 512 MiB
                  admission ceiling. No-ops remain allowed, and legacy migration is grandfathered. A save is durable
                  only after validated temporary-file write, flush, rename and parent-directory flush; failed saves
                  remain visible in memory with a warning, Retry and Export.
                  Migration copies the legacy Caches files without deleting them, preserves conflicting incoming
                  values in content-addressed recovery, verifies the destination and records its source digest.
                  Persistent suppression prevents deletion from being undone by migration. Delete all also attempts
                  to remove legacy copies and reports failures. Downgrades see the stale legacy snapshot, not new
                  durable saves; there is no two-way sync. Export before uninstalling or moving to another install.
                  The saved-translations row opens management: select/export/import/delete and restore recovery.
                  JSON uses a versioned namespace/opaque-filename/lines envelope; ZIP includes a manifest and recovery
                  records. Full exports split into independently importable volumes below 256 MiB and 10,000 entries.
                  Snapshot bodies are copied to disk one record at a time on the storage executor; summaries stream
                  directory entries and management displays 100-record pages, not the whole library in memory.
                  Storage readiness rechecks and protects its directories even after the root has been removed.
                  Import rejects duplicate JSON keys, duplicate identities, unsafe ZIP features/paths and corrupt
                  checksums before touching active data. Application is per-record atomic, with durable progress and
                  explicit partial results; Retry resumes an interrupted import. Merge keeps local keys and saves
                  conflicts in recovery; confirmed Replace preserves the complete previous record first.
                  Hide Translation applies to all songs; Remove Translation
                  deletes only the current song and target language, preserving its other languages and AI notes.
                  Shared job tokens invalidate late answers after removal, a newer request, or deleting all saved
                  translations, and both open lyrics views refresh from the same result. A failed disk write keeps its
                  answer in memory for the session; removing it clears that copy too. Requests need a tap unless Automatic translation is on.
                  Automatic translation is off by default (redesign only). Its Translation order can be dragged;
                  the default is Apple Translate, Bing, Google, DeepL, Gemini, Claude, the configured AI service,
                  then Apple Intelligence. Only available services are tried, once each in order, until all missing
                  lines are filled or the list ends. Each answer keeps earlier successful lines and source/saved
                  translations. A later Google, Bing, DeepL or on-device translator receives only the lines still
                  missing, mapped back by position; AI translators keep the whole song for context. Whether the
                  lyrics are in another language, and the song's language, are worked out off the main thread from
                  a snapshot of the lines and cached by text and target. Existing Google/Bing opt-ins and API keys still apply; no new service is enabled.
                  A visible current-song view starts one shared chain after its lines settle. Hidden translations,
                  a language rule set to off, and background/detached views do not start another request. A song
                  or display change stops the next fallback; an in-flight answer can still be cached without
                  revealing hidden text. Settings/target changes, removal and clearing saved results invalidate
                  old jobs. Automatic failures remain silent and are not retried on redraw; manual translation
                  remains available. A manual choice or removal suppresses automatic work for that song/target
                  until restart or an explicit automatic switch/order change (bounded session history: 2000 pairs).
                  Enabling the switch shows translations once; rearranging the order does not override Hide.
                  A compact note beside the lyrics menu names the working translator and completed missing lines;
                  a fallback updates that name. Partial, failed and paused work offers Retry for only that song and
                  language; a missing setup is explained separately and does not count as a failed provider. Finished
                  work hides the note, and a restored translation is never assigned a guessed provider. Status is
                  main-thread, generation guarded and bounded to 200 song/language pairs. Display-only changes do
                  not restart work. Only known local failures become connection/key/busy reasons; remote bodies
                  and credentials are never copied into the note.
                  New Gemini, Claude and OpenAI-compatible lyric translations use L0001<TAB>text rows.
                  Missing, duplicate, reordered or unknown IDs, extra rows and truncated/refused replies
                  invalidate the whole result instead of shifting translations between timestamps.
                  Each source entry remains one row: embedded tabs and newline characters become spaces,
                  with CRLF replaced by one space. Empty source rows must return empty values.
                  Existing saved translations keep their format and are not regenerated automatically.
                  Title, pronunciation and cultural-note requests explicitly retain JSON; on-device,
                  Google, Bing and DeepL translation protocols are unchanged.
                  Check connection, on the OpenAI-compatible service's page, makes one bounded GET /models
                  with an 8 MiB response cap and sends no translation. A readable model list does not prove
                  key validity on a public endpoint or that a selected model can translate. The separate
                  Test translation action sends one fixed short sentence using the saved address, model,
                  key and translation language, with a possible-charge notice. Both run only from a tap,
                  without retries, redirects, cookies or credential storage, with a 20 s limit; translation
                  responses are capped at 512 KiB. A second tap on the running check cancels it. Both rows
                  remain visible when a key is missing. Result alerts offer safe diagnostic details to copy:
                  observed status, tri-state results and allowlisted error domains/codes, never model names,
                  credentials, addresses or upstream free text. An unsent check remains unknown, not unreachable.
                  Service/target changes clear the UI results and cancel stale requests; completing after
                  leaving the page shows no popup.
                  Both AI results are kept per song in Caches/Retrine/AI beside the saved translations, which the Saved
                  translations row counts and deletes with them. AI completion refreshes every open view of that song,
                  including views sharing the same line objects. Failed writes keep the answer in the shared
                  32-entry memory cache; deleting saved results also clears it and cancels pending jobs.
                  TranslatedTitles.m shows the playing song's title and artist in the user's language
                  (SGKeyLyricsTranslateTitles, off), using local translation then the first enabled online service,
                  an artist in Latin letters left as it is. Track, original title/artist and target form its identity;
                  200 results and 2000 successful identities are remembered. Missing services consume no attempt;
                  failures permit one retry after 30 s on a later label update. Translator settings reset failed
                  attempts and invalidate pending replies. Their replies are checked on the
                  Mac against the same harness
    LyricsMeanings/ Genius's annotations for a song's lines (Meanings.h; Line meanings, spotifyglass.lyricsMeanings, off, else From
                  the artist, Artist and editors or Everyone), read per track from Genius's referents (up to 5 pages of 50) and
                  kept for the newest 40 tracks. Matching them to the lines (an annotation of a line sung twice explains it
                  wherever it is sung) runs on one serial worker queue over a snapshot of the lines' text, its result kept by
                  track, lines, level and referents in a cache of 40, and goes to main only if the level and the lines are still
                  the ones asked for; the redesign's lyrics view also drops an answer for another track or song language
    LockScreenLyrics/ the line being sung in the system's now playing, and on iOS 26 the lyrics as the lock screen's
                  full-screen artwork (LyricsArtwork.x). With pronunciation or romanization shown in the lyrics, both and
                  the Live Activity follow the lyrics' own order: the larger of the words and the pronunciation leads (the
                  now playing artist row has room for that one line) and the other goes under it in the artwork and the
                  Live Activity; a translation chosen for those places keeps its place, the native look shows no
                  pronunciation, and a change redraws at once, even paused, the clips dropped for new IDs. The artwork: a new artwork ID per line, its 3:4 H.264 clip (the line in bold
                  and the next one smaller, in the regular weight at 0.6 of its size and half white, over the selected
                  background, SGLyricsClip.m; left-aligned 8% of the screen's width in, wrapping at 84% of it, the block
                  centred 40% down and its top no higher than 17%, clear of the clock and the media controls;
                  the whole 3:4 frame is visible across the screen, starting about 10% down on the 1179×2556 reference,
                  so screen heights are mapped into the frame rather than assuming a centre crop) written only when the lock screen asks for it,
                  Still (one frame) or Animated (15 fps). Layout (SGKeyLockScreenLyricsLayout, under Lyrics style): Left
                  as above (the default), Centered (each line centred in the same column) or Poster (the line alone at
                  1.6 times the size in the heavy weight, left-aligned, its translation under it; at a rest the next
                  line alone in its place, dimmed), Messages or Vinyl (scenes of their own, drawn only between 17% and
                  65% of the screen and held as one frame under either style: Messages on black, the previous line a
                  grey bubble on the left, the current line a #0A84FF bubble on the right, a pill of three dots while a
                  next line is coming, never its words, sides swapped right to left, the current bubble at most 4
                  lines and the previous 2 after shrinking to 0.6; Vinyl on #0E0E0E, a still record of 45 to 60% of the
                  visible width with the cover as its round label, a lighter rim and a soft glow, the current line in
                  New York italic under it by default, the next line at 55% white; harness/lyrics-clip/ `scenes` and `regression.sh`). Over the artwork (last choice; default unchanged) keeps the cover sharp and
                  centre-filled, with the previous line, current line and translation over a broad side-anchored
                  Gaussian gradient with no flat box or cutoff, plus a subtle text shadow. On white, the current
                  line keeps at least 4.5:1 contrast and the dimmed lines 3:1. Still holds it, Animated gently
                  breathes the cover, including under Moving artwork with lyrics. Dim the whole artwork
                  (`spotifyglass.lockscreen.dimArtwork`, off; shown under Over the artwork) replaces that local shade:
                  the whole frame is the cover through the shared renderer's Blur at 20, or under Moving artwork with
                  lyrics each video frame blurred alike on the clip queue (falling back to the dimmed cover), darkened
                  evenly by one value per cover or clip, the least that keeps the line 4.5:1 and a dimmed line 3.3:1
                  against the brightest blurred pixel (four frames for a video), never under 30%; the look gains `d`.
                  In the first three layouts a block still too tall at the smallest size, whose
                  bottom would pass 65% of the screen, lets go of the line sung last, then the next line, then the
                  translation, and last keeps the whole lines of the line that fit from 17% down, the last ending in an
                  ellipsis. Fallbacks use the largest exact 3:4 raster within the screen's native width, both sides
                  divisible by 16; motion uses the largest even-sided exact 3:4 cut within the video.
                  Preview and video share that raster, including Every song's lyric-free fallback, and the shared
                  CPU renderer. Cover backgrounds load the current URI's metadata artwork through
                  SGShownTrackArtwork, not title-matched system artwork that may be a placeholder or the
                  previous song's cover. Missing or failed covers use the dark fallback; late results are
                  guarded by track, source URL and generation. Previews are drawn on a queue apart from the clips, and while the
                  lock screen is asking for the line showing (an ask for a line gone by does not count), the next line's
                  preview and clip are drawn ahead and a ready preview is handed over at once; from the thermal state Fair
                  up, a clip of many frames (over moving artwork, or Animated) is left for the lock screen's own ask, and
                  Low Power Mode draws nothing ahead. A clip being written stops as soon as its line is neither showing
                  nor the one drawn ahead. A freshly encoded on-demand motion clip checks the live line before
                  delivery, so a late timer cannot hand back a clip for a line already sung. From Serious up, and in Low Power
                  Mode, the lines go Still over the cover (no motion, no breath) under their own ID, and the chosen look
                  comes back once the phone cools or Low Power Mode is off, paused too; reaching Fair or Low Power Mode
                  also lets go of a many-frame clip queued or being drawn ahead. All lyric layouts follow the app font
                  applied at launch. The artwork ID includes its design or family so a new choice redraws the clip.
                  Each lyric ID normally owns one ordinary Now Playing artwork object, reused by ready-preview,
                  artist-row and Spotify/extras resends. Its synchronous handler uses a ready frame from this render
                  generation while a miss draws off main, never the plain cover. A new ID replaces the object;
                  turning lyrics off restores the
                  native artwork. Keep original widget cover (`spotifyglass.lockscreen.keepWidgetCover`, off by default)
                  keeps Spotify’s cover in the widget and Control Center. It applies immediately and can briefly expose
                  the cover between full-screen lyric clips. Picking another artwork mode also applies at once.
                  Moving artwork with lyrics (the choice's fifth value, 4) draws each line over the track's moving
                  artwork, which LockScreenMotion.x finds and hands over (SGLyricsArtworkSetMotion): the clip is the
                  stretch of the video the song is at while the line shows (its start taken round the video's length,
                  from the line's start to the next's plus a second, 2 to 8 s; a video no longer than that is written
                  whole, turned to start there, so its loop has no seam), at the video's own 3:4 cut and frame rate up
                  to 30 fps, with the line sung last dimmed above (dim, bright, dim). The video is decoded as BGRA, the
                  rows behind the words are blurred (Accelerate's tent blur, 16% of the width across, at most 127
                  pixels) and faded in, every row of the cut is darkened in one pass (0.25, and 0.6 across the words,
                  up to 0.8 over a bright picture: by the brightest of four frames spread from the clip's first to its
                  last, shared between preview and video in a bounded cache keyed by file revision, stretch and text bounds, enough that
                  the brightest tenth behind the words comes to 0.22 of white; the preview judges the same stretch,
                  so it matches), and the words with a tight dark shadow are
                  drawn on. The tent runs at half resolution. The exact 3:4 crop is composed directly into the encoder’s aligned,
                  IOSurface-backed buffer pool, preserving source color tags without scaling the already-drawn words.
                  The IDs end in a render-version token (changed whenever the drawing changes, so system-cached clips
                  from older renderers cannot return), the style, the layout and, over moving artwork, m and the first 16 characters of the
                  file's name (SGLyricsClipLook), so the clip arriving, a Canvas after an animated cover, or a change of
                  style or layout re-offers the line showing. Until it comes, and for a track with no moving artwork, the lines are drawn
                  as Lyrics draws them, in the chosen style; so are they over a video that will not draw (turned, its
                  frames another size than it states, as a video with non-square pixels has, cut short or gone from the
                  store), which is remembered for the launch and tried again only when handed over again. A track with
                  no synced lines, or whose lines are not in yet, shows its moving artwork plain, as Moving artwork does:
                  LyricsArtwork.x says so (SGLockMotionShowPlain) and LockScreenMotion.x shows it and takes it off for
                  the lyrics' clips. Translations (spotifyglass.lockscreen.translation, off) put the line's translation
                  under it, in the regular weight at 0.62 of its size, a word joiner between Hangul letters so Korean
                  breaks at its spaces; the ID carries t and an FNV-1a hash of it, so a translation coming in re-offers
                  the line. The artist row's Lyrics line (spotifyglass.lockScreenLyrics.line: Original, or Translation
                  where the line has one) splits a long translation into even pieces over the line's time. The row
                  wakes for a displayed piece, lead or rest, not each source word. Both row and artwork re-arm on
                  player reports and effective speed changes, without waiting for a Now Playing setter. A metadata
                  resend carries the current position and rate together, so a late cover cannot slow the clock. Missing lyrics normally wait for
                  delivery; a failed lookup still retries because renewed authorization is not announced. With artwork
                  Off, unrelated defaults changes neither queue artwork work on main nor read the artwork style. Main compares the current mode
                  with the mode it last applied, so a background defaults write cannot skip cleanup. Either one
                  asks SGRAutoTranslateWithoutView (declared in LockScreenLyrics.h, defined in Redesigned/Lyrics/
                  AutoTranslation.m) once a track and language: the saved translation is synced onto the lines, then
                  automatic translation runs on the lyrics view's terms and job ledger, without a view or the app in
                  front. Rendered on the Mac against harness/lyrics-clip/ (`motion`, over a
                  bright busy, a dark and any given videos). What reaches the
                  system's now playing through this hook and Player/NowPlayingExtras.x is checked by harness/now-playing/
    AnimatedArtwork/ moving artwork (AnimatedArtwork.h): the track's Canvas, else Apple Music's animated album cover
                  (SGMotionCatalog.m: the full release title including the edition and the album artist suffice, even
                  when a song's title differs; Apple Music's " - EP" and " - Single" suffixes are not part of the title. A single
                  named "X - Single" stands for Spotify's "X" only with video, as a last resort once neither the album nor the
                  song found a release in a final (not full first-page) result; Spotify's own "X - Single" is compared whole.
                  Otherwise a single release must contain the song with its artist credit;
                  trailing features and version tags are simplified on the song, never on the album. A soundtrack's songs
                  share the title search; only a full page with no identified release can be narrowed by artist.
                  A downloaded clip verified for the Spotify album URI wins even over a later answer for the same title.
                  Without one, a known title answer is reused without asking Spotify for identifiers. Otherwise, with an album URI,
                  Spotify's album metadata supplies its UPC. Apple Music gets the barcode as supplied; only albums whose own UPC matches (ignoring
                  leading zeros) qualify. If Apple returns no UPC match, the player's track (on the album page, the first
                  track on the album) supplies a recording code from Spotify. Of the Apple albums containing that ISRC,
                  exactly one distinct non-single must share the edition-stripped album name, whether it has video or not;
                  with none, exactly one "X - Single" whose whole name (less the suffix) is the album's.
                  A confirmed identifier miss permits the title lookup (and, on the album page, matching track rows).
                  A recording miss applies only to that track; the next track may identify the release.
                  An unanswered request remains retryable. If a complete UPC or ISRC reply has multiple qualifying
                  release IDs, the track gets a clip only if every candidate selects the same video URL. That agreement
                  does not verify the release or store the clip for other songs on the album.
                  For an identified still edition only a title match within one year of Spotify's release year can move;
                  without a year it stays still. Only an identifier-verified clip that downloaded successfully is kept
                  for all songs by Spotify album URI. Header and track share the
                  master and media playlist lookup for the same stream size. The catalog is
                  left alone for 10 minutes after a 403 or 429; an album's answer kept on disk for a week, so a relaunch skips the search), kept as local files (SGMotionStore.m, a download that
                  fails on a transient error (a timeout, a lost connection, DNS or no network, HTTP 408, 429 or 5xx) tried once more while
                  someone still waits for it, its body streamed to a temporary partial that is moved into the store only when the whole
                  30 MB (decimal) has arrived — an advertised length over it is refused at the headers and a body that passes it
                  is cut off, so neither a lying nor a chunked server can fill the disk, and a cancellation, a size refusal or a
                  failed write is not retried; every request hands back a ticket, SGMotionTicket.h, and the tickets asking
                  for one file share its transfer: cancelling the last stops it, unless the size is known and more than half
                  of it is in, when it finishes into the store anyway; a cancelled ticket's completion never runs, a dropped
                  one's still does). The store trims its own clips to 40 files and 300 MB (decimal), oldest modification
                  first, skipping clips still in use and trimming again on release. On iOS 26 the lock screen's full-screen
                  artwork (LockScreenMotion.x). With Every song, a song with neither gets the selected background
                  as a gentle 4 s 3:4 loop, using the shared lyric encoder without text (SGFluidClip.m).
                  Cache keys include cover content, background settings and output size. Pending presentations
                  retry on native now-playing updates without downloading again; ownership changes reject late
                  posters. Late covers replace coverless lyric caches, including while paused.
                  Rendered on the Mac against harness/fluid-clip/. A track whose
                  metadata names no Canvas has it asked of Spotify's Canvas service (MotionSources.m); each track is
                  looked up again when its Canvas comes in a later state, and the next track's clip is fetched ahead
                  (SGMotionFollower.m), unless optional advance work is standing down (Core's SGOptionalWork.h: Low
                  Power Mode, a serious or critical thermal state, no usable network, Low Data Mode, an expensive
                  cellular or hotspot network — lyrics are small, artwork is not — or the Player page's Load ahead,
                  spotifyglass.loadAhead, switched off: it stops this and the next track's lyrics walk, never the current
                  track's), in which case nothing is fetched ahead and a fetch under way is cancelled. Paused, no new
                  fetch ahead starts (one under way for the same track finishes), and playing again aims it once more. A change of the
                  up-next track (PlayerState.x's playerUpNextDidChange:), of the current walk or of a setting aims it again. The lock screen takes a clip under a key the
                  system lists, cut to that key's
                  shape when it is not, with its still filled to the size asked (SGMotionClip.m), and a change of the
                  choice applies at once, Lyrics too. Switch with the star (spotifyglass.lockscreen.star, off;
                  LockScreenStar.x) puts a star on the lock screen widget, MediaPlayer's like command, whose tap swaps
                  the choice for the one the star last left (kept under spotifyglass.lockscreen.star.back) when that one
                  is on the other side, with lyrics or without, else for Lyrics or Moving artwork: Lyrics swaps with the
                  moving artwork it left (Moving artwork or Every song), and Moving artwork with lyrics counts as lyrics,
                  so it swaps with Moving artwork. The star is filled while the lyrics show; the choice is the setting, so the
                  mode outlives a relaunch and the page's row follows it. The star takes the slot of Spotify's like
                  and dislike buttons, so their flag is forced off at launch while the switch is on, over the row's
                  own override, and the row shows it locked. The cut and the service's wire format are checked on
                  the Mac against harness/motion/
    LocalFiles/   local files (LocalFiles.h lists its files): Edit info in the player's ⋯ menu, the table's footer
                  under Speed and pitch, which closes the menu and opens a form sheet (the three names, the cover
                  with a menu to change it, Restore file's info; nothing is stored before Save, and a swipe away
                  with changes asks first), storing a title, artist, album and cover by the file's URI and laying them
                  over -[SPTPlayerTrack metadata] and the cover's image request (the redesign's artwork reads the
                  stored cover itself, Redesigned/Kit/SGRBridges.x); the file is never written. Find Info at the
                  sheet's foot (spotifyglass.localfiles.suggest, on: a button, nothing sent before a tap;
                  LocalInfoLookup.m, LocalInfoReview.m) asks iTunes Search (term from the shown title and artist, or
                  the file name cleaned of brackets, a leading track number and words like official or lyrics;
                  media=music, entity=song, limit=10, the device's country; ephemeral, 15 s, no Low Data Mode, 2 MiB,
                  redirects only to itunes.apple.com), keeps results within 3 s of the file's length, ranks them by
                  title, artist and length, and shows the best beside the current values with a checkbox per
                  differing field and Other Matches; Use only fills the sheet, the cover fetched then from an https
                  mzstatic.com URL (4 MiB, decoded, then the picked-cover path), and Save stores it as any edit.
                  Successful answers are kept in memory for the launch, 32 at most; harness/local-files/
                  suggest-build.py and suggest-sim.py. Their
                  lyrics are kept under the URI and asked of the sources by name, since Spotify never asks for them;
                  with no source switched on, of LRCLIB alone, which then gets the file's title, artist, album and
                  length. A rename gives a new key (a cover alone does not), asked for at once while the file plays.
                  A miss is asked again a few times, in case it was a lost request. The user's own lyrics files
                  (LocalLyrics.m, Imported lyrics files under Lyrics' sources) accept .lrc, .ttml, .xml and .txt
                  and stay as UTF-8 in Documents/Retrine/Lyrics. Import or paste links lyrics to the URI of the
                  song playing when the listener taps. For Automatic, that link precedes offline and online
                  lyrics without overwriting the ordinary offline copy. Replacing or deleting refreshes the
                  affected track. Only local files can also match by folded [ti:]/[ar:] or "Artist - Title".
                  Before that name match, the engine tries the playing file's `local_file_path`, off main:
                  ID3v2.2 ULT/SLT, v2.3/2.4 USLT/SYLT, FLAC LYRICS/UNSYNCEDLYRICS, or M4A ©lyr.
                  Timed lyrics take precedence over plain text; SYLT with MPEG-frame timestamps is skipped.
                  An unreachable file or absent tag continues the ordinary lookup. What a file holds is decided by its content, never by
                  its name — a TTML document with timed lines, else LRC's stamped lines, else one untimed line after
                  another — and it is kept under the extension of what it turned out to be. A file or a paste over
                  1,048,576 bytes of text, an empty one, bytes that are neither UTF-8 nor UTF-16 with a BOM, or a
                  document with no line at all is refused with its own reason; a document that looks like TTML or LRC
                  but yields no line is read as plain text, and refused only when that gives nothing. A replacement
                  writes the new file and links it, then puts the replaced file's name on a list of its own and
                  deletes nothing; that list is worked off at the next launch, and only a name no link holds, that is
                  a regular file directly in the lyrics folder, is removed, so a by-name import or a file copied in by
                  hand is never touched. Every change to the store runs on one serial queue — a name's allocation,
                  its file, the links, the retired list, a delete and the launch's retire step — so the step always
                  runs before anything the launch asks for, and every notification is posted on the main queue. A link
                  whose file is missing gives that track no lines rather than another song's, and a write that fails
                  leaves the old file, link and lines as they were. SGImportedLRCAsk is the same as a source for the
                  order, which moves it on top at the first import and at every link once LyricsSources lists it.
                  Where Spotify's player shows its placeholder for a local file, the file's own cover is found
                  (LocalCover.m) in the image fields of its metadata or, while the titles and artists agree, in the
                  system's now playing artwork, which the lock screen shows (read again, and announced, whenever the now
                  playing info changes, so artwork that arrives late replaces the provisional one); the native look puts it into the front
                  cover's empty image view (Native/LocalFiles/LocalCover.x), the redesign's artwork bridge takes it
                  as the picture of a local file whose metadata names none. A cover picked in Edit info wins.
                  Import audio files (LocalAudioImport.h, LocalAudioPage.m), on the Local files page under Player
                  settings in either look: a multiple-selection Files picker for audio (asCopy), whose picks are
                  copied, never moved, into the app's Documents folder at the top level, where Spotify scans its own
                  Local Files, so Retrine only copies and Spotify indexes and plays once its setting for showing audio
                  files from this device is on in Spotify's settings (the footer says so). A file is never overwritten:
                  the copy itself refuses a taken name and the next is tried, "song 2.mp3", "song 3.mp3"…, with the
                  number before the extension. The copies run off main with security-scoped access around each; one
                  alert says "Imported N files" and, below it, the names that failed. The names imported are kept in
                  Retrine's defaults (SGKeyLocalAudioImported) with each file's identity (device, inode and size, read
                  right after the copy); the Imported files page lists only those whose file in Documents still has
                  that identity, dropping a name whose file is gone or was replaced, and a swipe asks before it deletes
                  that one file with a single non-recursive unlink on the Documents-anchored name, after checking the
                  identity again; any mismatch deletes nothing, unlists the name and shows the delete-failed message.
                  A file the user put in Documents any other way, or that took an import's name, is never listed, renamed or deleted,
                  and there are no folders and no network. The numbering, never overwriting, the list and the delete
                  are checked on the Mac in harness/local-files/audio.m.
                  Local Library (LocalMusicIndex.m, LocalMusicStore.m, LocalMusicPages.m), next to Imported files:
                  those imported files by artist (album artist, else artist), album (with its artist; disc, track,
                  title order) and folder, with "Unknown" groups, the user's Edit info over the file's own tags and
                  never a write to the file; artist, album and folder pages with a cover header, an artist's first 5
                  songs and See All, and a reusable album shelf. The index is rebuilt off main when imports, deletes
                  or edits change, cached by name and file identity; covers are references decoded at display size
                  into a 16 MiB cache emptied on a memory warning. On Spotify 9.1.90 and 9.2.0 (LocalMusicPlayback.m) a page
                  plays or shuffles its songs as the spotify:local-files context, and a song can go next or to the
                  end of the queue, one at a time; a file is playable only once Spotify has been seen playing it,
                  which records the URI Spotify gave it with the file's identity (a replaced file needs playing
                  again), and a page with songs not yet seen says to play them once in Spotify's Local Files. A
                  refusal for Spotify Free (mft_disallow) says Spoof Premium lifts it; nothing is retried. Other
                  Spotify versions, or a player missing the calls it needs, get the pages to browse only.
                  The model, the cover fallback and every kind of lyrics file are checked on the Mac against
                  harness/local-files/, whose README lists the cases, the row and the editor in the simulator
                  against its sim/
    Navigation/   the page transition fix (PageTransition.x), opening a spotify: link (Links.x), and either look's
                  Add a Tab sheet (AddTabSheet.m) with the icons a tab can wear, Encore's glyphs or SF Symbols
                  (TabIcons.m). The sheet runs in the simulator in harness/addtab/
                  New links use retrine:; legacy vitrine: links are still accepted. Forms include retrine:track:<id>, retrine://track/<id>,
                  retrine://open.spotify.com/track/<id>, or retrine://https://<Spotify share URL>.
                  The public-page allowlist is track, album, artist, playlist, show, episode (22-character
                  base62 IDs) and user profiles (user/<id>, one URI-unreserved token, up to 255 characters).
                  HTTPS open.spotify.com paths may have an intl-xx locale prefix or embed prefix; page
                  queries, including ?si=, are discarded. Only public HTTPS socialsession/<22-character
                  base62 ID> invitations reach Spotify's own Jam join UI; raw Jam/session action URIs,
                  internal, debug, webview, settings, account/auth, download, add-to-playlist and unknown
                  destinations are rejected. Safari Eevee wrappers must contain a validated HTTPS share URL.
                  Short links resolve off main using HEAD, a five-second timeout, and exactly
                  open.spotify.com, spotify.link or spotify.app.link at every hop. Only one resolution
                  runs at a time: a newer inbound URL cancels and supersedes the older one. No link history
                  is kept. URLs are limited to 4 KiB UTF-8 and shared text to 64 KiB; the source-built
                  Open in Retrine share action scans off main and processes at most eight shared items
                  and eight providers. Its links use the same public allowlist as the app. Unsupported
                  dispatcher versions retain Spotify's original handlers and cold-start inputs.
                  A plain HTTPS link opened in Safari shows Spotify's web page, whose "Open app" button
                  cannot reach a re-signed app: use the share sheet or a Safari Open-in-Spotify extension.
                  The share-sheet handoff relies on iOS behavior that must be confirmed on a device.
                  A different app can register retrine: too; sideload signing does not reliably provide
                  app groups, so this scheme does not authenticate which app receives the handoff.
    Player/       the player's open and close announced (PlayerEvents.x), what the player is doing read through
                  one hook for every feature that wants it (PlayerState.x, which also names the up-next track, SGPlayerUpNextIn, and tells its
                  observers when it changes), the last track played for the settings
                  pages' previews to show when nothing plays (SGLastTrack.m), the lock screen widget's flags, the lock
                  screen card's parent app named to MediaRemote as the Info.plist's bundle id for an installed app signed
                  for another id, so a tap on the card opens it (NowPlayingParent.m, spotifyglass.nowplaying.parent, on;
                  a matching or wildcard signature and a LiveContainer guest are left alone), and in the
                  more button's menu Speed and pitch: both done to Spotify's audio by Apple's time and pitch unit, put
                  between its mixer and its RemoteIO unit by taking over the connection Spotify makes between them
                  (SpeedPitchMenu.x, SpeedPitch.x, SGTimePitch.m). Position reports still detect remote seeks,
                  but only an active or armed speed clock reads the state's track. Spotify runs a chain per sample rate, so a local
                  file at another rate can have two RemoteIO units running at once: SpeedPitch.x keeps a record
                  per unit (its own mixer, sample time, largest slice and formats; AudioOutputUnitStop and
                  AudioComponentInstanceDispose rebound too, a disposed unit forgotten after its render in progress)
                  on sideloaded installs. A jailbreak's ElleKit/Substrate, found in jailbreak paths before
                  process symbols and never counted from an app bundle, installs stop/dispose/start inline
                  instead, without writing Spotify's import page. All three must take before any replacement
                  acquires an output; the speed hook is optional and comes last. Only callers in Spotify's
                  own __TEXT (also under LiveContainer) enter the processors, all others pass through.
                  Hooker and bundle paths are canonicalized before containment checks, including /var
                  versus /private/var; roothide's .jbroot remains a jailbreak. ElleKit/Substrate may
                  patch before returning the trampoline: its out parameter is private until return,
                  then release-published. A replacement acquire-loads publication and, until ready,
                  returns kAudioUnitErr_CannotDoInCurrentContext without performing the operation.
                  Installation is synchronous at tweak load: SpeedPitch's unconditional constructor
                  calls rebind before %init; the AudioEffects, Haptics and Sing constructors can reach
                  the same dispatch_once earlier through SGPlayerWatchMusicOutput. Later registrations
                  cannot install again. In supported launch-time injection this precedes Spotify's
                  output creation/start, so no live Spotify output has a Stop/Dispose to lose in the
                  publication window. The error guard is a last resort, not an active-playback strategy.
                  Late injection into an already-playing process is not supported; constructor timing
                  does not prove that a LiveContainer host or unrelated framework has no audio of its own.
                  It never waits or calls the captured symbol address, which is now patched and would
                  recurse. After publication even a partially installed group passes through safely.
                  The address range is prepared during installation, never on render; refused-page diagnostics
                  are capped at three. SpeedPitch keeps the same output record
                  and names one the music's (SGPlayerMusicOutput), the one Spotify started or connected last, or
                  one with sound when that one has had none for a second; speed and pitch, Karaoke's stage, the audio
                  effects and Music Haptics follow it (SGPlayerWatchMusicOutput), and the other plays as Spotify
                  made it. A connection whose formats the callback cannot take (not float with a buffer per channel,
                  more than two channels, or a mixer at another rate than the unit) gets Spotify's own connection
                  back. Each start, stop and dispose is logged as `audio:` with its formats and where the processors
                  are. Pitch follows speed (on until switched off,
                  spotifyglass.speed.pitchFollows) plays the speed through Apple's Varispeed instead, faster and higher
                  together like a record; Varispeed also carries 1x while it is on, so a return to normal speed changes
                  nothing, and the stretch is left for pitch alone at 1x, the two swapped only through a reset. A new
                  format on either side of the output while it runs (a route to another rate, Spotify handing it
                  another one) makes the unit again for it, and until then the sound passes as it is. harness/speed's
                  `two` runs a 44.1 and a 48 kHz chain at once. Under the
                  sliders a Reverb slider sets the audio effects' reverb amount (spotifyglass.dsp.reverb.amount), turning
                  the effects and the reverb on with it; a reverb set from the Audio effects page posts
                  SGSpeedPitchReverbDidChange (SpeedPitchEvents.h) from the effects' own setters on main, so a song keeps
                  that reverb too. Every text of the block is read through SGL (player.speed_pitch.*), so the sheet is
                  localized like the mod's own pages. A second switch under Pitch follows speed, Keep for This Song,
                  gives this song its own speed, pitch, pitch-follow and reverb (SpeedPitchSongs.m; the records under
                  spotifyglass.speedPitch.songs, the newest 200 by timestamp). Keeping writes at once; a slider then
                  updates the record and writes it half a second after the last change, the newest change's generation
                  alone allowed to write, and a skip flushes a pending edit. A track is keyed by its URI, and a local
                  file by its four form-decoded fields (artist, album, title, duration, each decoded on its own so an
                  encoded colon cannot move a boundary) composed and cut to 128 bits of SHA-256, so it is the same key
                  at every launch and for every encoding of it. A stored record is checked before it is used (speed
                  0.5 to 2, pitch within 12 semitones, pitch-follow 0 or 1, reverb 0 to 100, a finite number each and
                  a timestamp), and one that is not is dropped. The values in effect before the first kept song are
                  kept as a baseline (spotifyglass.speedPitch.baseline) and put back as each unkept song comes, so
                  speed and pitch no longer only last until Spotify quits; a control the player has not admitted yet
                  stays pending and is retried on the next report, and the baseline keeps just those controls until they
                  are restored, so an edit made meanwhile is not lost. A song changing while a finger is still on a
                  slider shows the new song's values and rejects the old gesture's callbacks. Checked on the Mac by
                  harness/song-audio/, in two processes, so the relaunch path is real. The block goes into Spotify's own context menu sheet
                  and is drawn from its own measures, not the Kit's, so it sits there under either look. Tested on the
                  Mac against harness/pitch/ and in the simulator against harness/speed/ and harness/menu/. Under the
                  redesign, with the player's background Fluid or Animated, a row under the block switches Animated
                  artwork at once, through functions the redesign's PlayerMotion.x defines. The redesign shows that
                  sheet as the system menu (Redesigned/ContextMenu), whose own items stand in for the block, so the
                  block stays out of it unless the sheet itself is shown (SGPlayerMenuReplaced). Switch to video,
                  the chip over the title of a song with a music video, is hidden by default in Redesigned;
                  select Video in the Player page’s Buttons card to show it. Native leaves it alone by default.
                  VideoSwitch.x removes the identified button on layout when hidden. An explicit
                  spotifyglass.hide.videoSwitch value overrides either default (YES = hidden); stock leaves it alone if unset.
                  The switch is read on every pass, so it applies from the player's next layout without a relaunch.
                  Full screen cover on tap (spotifyglass.hide.fullScreenCover, shown unless switched off) is the
                  player's single tap on the cover, which opens Spotify's full screen cover, as a switch of its own:
                  off, each look's handleTap hook on CoverArtTiltView (PlayerGestures.x) returns before Spotify's, as
                  it does while Gestures is on (the tap is then half of a double tap), the native look's on the
                  player's cover only. Spotify's cover_art_tilt_enabled flag is left alone: with it off the cover has
                  no CoverArtTiltView, which the redesign's cover rounding and the native hold to play faster hang on.
                  Spotify's own lyric preview under the cover takes no touch, so a tap on it reached the covers' list,
                  which selected the cell and opened the same viewer whatever the switch said (issue #36). In the
                  redesign a tap on a showing preview opens the lyrics instead (PlayerLyricLine.x's SGRPreviewTap,
                  which waits for the Gestures double tap and leaves a preview the lyric line hid alone);
                  If lyrics are still coming, the tap waits for that track; another touch, a skip or leaving the player
                  cancels it. `harness/player/ui-check.py preview-tap preview-pending` sends the taps.
                  The sleep timer (SleepTimer.m, set from the Live Activity) pauses Spotify at a time, at the end of
                  the track or at the end of the album or playlist, the last track of it found by the tracks to come
                  that are neither queued by hand nor autoplay's (SPTPlayerTrack's provider), or by the next one
                  having played already when it repeats. Over the last seconds (the Player page's Fade-out duration: Off,
                  10 s, 30 s, 1 minute or 2 minutes, 30 s unless picked; at the end of a track, over the whole track
                  when it is shorter) it fades the sound 60 dB through a gain of the mod's own, applied by SpeedPitch.x's notify on the music's RemoteIO unit (never the system
                  volume), and puts the gain back a second after the pause. A wall-clock timer sleeps until the fade
                  starts, or until expiry with Fade out off; only the fade needs quarter-second samples. Player reports,
                  app activation and time changes reconcile the deadline against the date after sleep. Track and album
                  timers still follow the player clock four times a second. Spotify's own timer, from the player's
                  ⋯ menu, fades by the same choice and gain (SpotifySleepTimer.m): the core reports it in the player's
                  state (SPTPlayerState's sleepTimer: type 1 at a timestamp, 2 at the end of the track), checked four
                  times a second while Spotify plays; Spotify pauses, the gain is held down from its end until that
                  pause and back a second later, at once on a cancel or a later time. It stands aside while the mod's
                  own timer runs and while Spotify's own Fade out flag (its DuckHandlerImpl's duck) is forced on.
                  Tested on the Mac against harness/sleep-timer/, the gain in the simulator against harness/speed/.
                  Audio quality (the Player page, under either look, spotifyglass.player.audioQuality, off until
                  switched on, followed at once) shows the quality of the song playing the way the Music app shows
                  Lossless: a small capsule in semibold caption type and the secondary label color, centered under the
                  progress bar between the two times and on their middle (AudioQuality.x, AudioQualityRules.m). The
                  redesigned player draws it as the Music app does: a rounded rectangle 18.3 pt tall with circular
                  4.6 pt corners (a quarter of its height) in semibold caption type (the times'), lit by adding light to what is behind it
                  (17 of 255 for the fill, 0.40 white for the text and glyph; see Backdrop ink below), in the label colors
                  under Increase Contrast. The times sit 7.3 pt further from the bar; the times and artist add 0.265 and 0.48 white
                  respectively, plainly composited under Increase Contrast
                  (PlayerControls.x kTimesDrop), the badge's text on the times' baseline (placed again from the elapsed
                  time's own layout, since a change of text size resizes the times without a pass of the unit), a
                  template waveform glyph before every tier, and the Music app's words: Low, Normal, High and Highest
                  Quality (낮은, 보통, 높은, 최고 음질; Very high is lossy 320 kbps, so not Lossless), Lossless and
                  Lossless 24-bit as Spotify's. Its tap opens a summary in place of the rows below: the glyph, the tier,
                  "About N kbps" (Spotify's published 24/96/160/320) or the bit depth and sample rate, one sentence on
                  the tier, and a tertiary footnote "Playing now · Spotify High". It reads
                  Spotify's own report for the file it plays, SPTPlayerState's playbackQuality, on every player report
                  (playerStateDidReport:, since a quality that changes within a song does not change the track), and
                  only its bitrateLevel: 5 is Lossless and 6 Lossless 24-bit, with a waveform glyph before them, and
                  4 to 1 are Very high, High, Normal and Low in Spotify's own words, without one. Never the quality
                  asked for or the highest available. Nothing shows for level 0 or 7 (petrel, unknown), anything but a
                  spotify:track: (a podcast, an ad, a local file), while another device plays
                  (SGPlayerPlaybackIsLocal), while the window scene is landscape (an iPad's regular-height landscape
                  too, except under the redesign on an iPad, whose player keeps the time row as it turns), while the
                  times are hidden (the lyrics' Hide the controls fades it with them) or where it does
                  not fit between them. Off, the looks' layout passes return at once and remember nothing; switched on,
                  the units on screen holding the times are laid out once again so the badge comes without a restart. The tier is the one reported with the
                  track's own URI, and in 9.1.90 a skipped-to track first reports 0, so the badge goes until its own
                  level comes. Each look places it from its duration unit's
                  layout (Redesigned/Player/PlayerControls.x for NowPlaying_ModesImpl's and the AI DJ's,
                  Native/Player/Player.x for NowPlaying_ModesImpl's and a Free account's ReinventFree
                  DurationElementsUnit), as a drawn subview of the unit's view, so the unit's alpha and transforms
                  carry over and the times and slider never move; the redesign's lowered times while scrubbing leave
                  it where it is, and 9.1.90's time row has no scrub label in the middle. The controls' unit lies over
                  the bottom of the time row, so the badge takes no touches itself: a tap recognizer on the view holding
                  the units accepts only touches on a badge that draws (shown, and neither it nor a view above it hidden
                  or under UIKit's 0.01 alpha floor; 4 pt around it), cancels no touches of the views under it, and
                  the redesign's tap to seek leaves that spot alone only while the badge draws. The tap opens a
                  popover (SGPresentPopover), under the native look with the tier, the playing and output sample rates, whether it is
                  resampled (only once both rates are reported) and the source by strategy (best_matching and
                  backend_advised streamed, offlined_file downloaded, cached_file cached, local_file a local file).
                  The popover is held weakly with the track it was opened for: it follows that track's later reports
                  (a rate reported late fills in) and is dismissed on a skip, when nothing is shown any more (another
                  device, the switch off), when its badge stops being shown or leaves the window, and as the player
                  opens or closes (SGPlayerTransitionNotification). VoiceOver reads one element, "Audio quality, Lossless 24-bit",
                  with a hint. The mod's own Lossless files are not claimed: their replacement state is not
                  trustworthy enough for a badge, so with them on it still says what Spotify streams. Each change of
                  the report is logged as `audio quality:` with every field. The rules are checked on the Mac by
                  harness/player/audio-quality-check.m (run by upcoming-tracks-check.sh)
    AudioEffects/ the audio effects on Spotify's sound (AudioEffects.h has the keys and the page's calls): a render
                  notify on the music's RemoteIO unit (SGPlayerMusicOutput, Shared/Player) runs each finished buffer through the mod's own engine, re-blocked to 1024 frames one block late,
                  in place (AudioEffects.x, SGDSPEngine.m), then hands it, mixed to mono, to one reader that only
                  reads it, switch on or off (SGAudioSetOutputReader: the player's Visualizer). The buffers are in the unit's output format, the
                  hardware's, not the client format Spotify sets. The effects are the SGDSP*.m files, on Accelerate,
                  Apple's Reverb2 unit, libbs2b and EEL2 (vendor/audio). Settings apply as they change, on a queue of
                  its own; the file effects read their files from Documents/Retrine/Audio effects
                  (AudioEffectsFiles.m). Presets and Headphones (AudioEffectsPresets.h lists their files): seven
                  built-in presets over a reset that keep the Graphic EQ, the user's own as a copy of every dsp key, the
                  settings from before the page's first pick saved as one of them, Before presets, and AutoEq's
                  corrections, its INDEX.md fetched from GitHub and cached a month in Caches/Retrine/AutoEq, a
                  headphone's GraphicEQ file put into the Graphic EQ (AutoEq.m), None taking it off; a pick turns the
                  master switch on. A pick can be kept per output (spotifyglass.audioOutputs, by the port's UID): on
                  every AVAudioSessionRouteChangeNotification to another output (AudioEffects.x), a remembered output
                  gets its correction or None, and any other output takes off a correction that came on for one; a
                  pick made with nothing remembered and a curve of the user's own stay, and the master switch is
                  never touched. A remembered output can also name one of the user's presets (Preset under Use for
                  <output>, None unless picked): entering it first stores the user's values, a digest of what is
                  about to be applied and the output under spotifyglass.audioOutputs.baseline, marked pending, then
                  applies the preset in one burst (the correction over its Graphic EQ); leaving restores the baseline
                  only while the values still match the digest (else the user's changes stay and the baseline goes),
                  and a restore is marked pending too, so a kill in the middle of either is finished at the next route
                  call; a relaunch on the same output applies nothing, and deleting a preset takes it off every
                  output, settling the playing one. The digest is over every key's effective value
                  (SGDSPEffectiveValues). AutoEq's search filters by All, In-ear, Over-ear and Earbuds from the
                  entry's path. Checked on the Mac by `harness/audio-effects/build.sh route` (two-process kill cases)
                  and `harness/autoeq/`. A preset of the
                  user's is shared from a swipe or a long press as a file (`<name>.retrine-preset.json`:
                  {"format": "retrine.audio-preset", "version": 1, "name", "values"}) through the share sheet, and
                  Import preset file… reads one from Files on a queue of its own: another format, a later version,
                  over 256 KB or nothing usable is refused, values are kept to this build's dsp keys and types (never
                  the master switch, a file name with a path or a leading dot dropped), and it is saved under Yours,
                  not applied, a name taken asking Replace or Keep both. An impulse response, DDC or Liveprog file
                  is named, not carried; the alert lists the ones missing here. Checked on the Mac by
                  `harness/audio-effects/build.sh presets`. A Liveprog script is held to half of real time
                  (SGDSPEngine.m): each block is timed on the render thread with two clock reads, and over 50 % of the
                  block's duration on 8 blocks in a row, or over 100 % on one, trips an atomic flag; the next block
                  bypasses the slot through its crossfade, the script is unloaded and quarantined, and the page says
                  "This script took too long and was turned off." Compiling and @init run on a queue of their own
                  with a 2 s deadline ("This script took too long to start."); a late VM is abandoned, freed when its
                  worker returns, and no other load starts meanwhile. Automatic reapplication (NaN recovery, a rate,
                  route or output preset change, an engine rebuild) keeps the quarantine; turning Liveprog off and on
                  or picking a script clears it. EEL2's loop cap is unchanged. Checked on the Mac by
                  `harness/liveprog-guard/run.py`.
                  Tested on the Mac against harness/audio-effects/ and harness/autoeq/, the hook in the simulator
                  against its sim/, the page against harness/audio-effects-page/
    AutoMix/      Spotify's own Automix and Crossfade, which its player core does, set from one page (AutoMix.h lists
                  its files): Style picks Beat-matched (Automix and crossfade on) or Crossfade (Automix off), Blend
                  length is Spotify's crossfade time (1 to 12 s, kept in milliseconds as Spotify does). Every write goes
                  through Spotify's preferences object (SpotifyPrefs/), so Settings > Playback shows the same values,
                  and the player takes a change at the next track change, with no restart. Turning the switch on saves
                  Spotify's three settings; turning it off puts them back, and so does Reset all settings. A switch
                  flipped before Spotify has read its settings takes effect once it has. While the switch
                  is on, one log line per track change (the probe) gives the current and next track's automix.* and md_*
                  metadata and the settings. SGTransitionFacts.h says, read-only and on main, whether the playing song
                  blends into the next one and when: Crossfade from Spotify's crossfade length (nothing for an album
                  played in order, where Spotify does not blend), Spotify's Automix from the pair's automix.* metadata,
                  whose cue points (milliseconds, tempo in BPM) carry no window, so its times stay unknown; incomplete
                  metadata gives nothing, never Crossfade; another device playing gives nothing. The facts are cached and
                  remade on a track, queue, settings or metadata change, with SGAutoMixTransitionDidChangeNotification
                  (harness/automix/). The page opens on a preview of the transition drawn from the switch, style and
                  Blend length (AutoMixPreview.m); its notes say that Spotify's Automix covers only some playlists
                  Spotify made, so the user's own need Spotify's Mix button in the queue, and that the bar and cover
                  show crossfades only. It holds the redesigned player's three switches, all off:
                  spotifyglass.automix.show-progress (the blend's window on the progress bar; with Crossfade on, Spotify
                  shortens a song's clock by the crossfade so its bar ends where the blend begins, and the window shows
                  as the next song's first seconds; seen on a 9.1.90 phone),
                  .show-queue (a line above Playing Next naming the blend into the next song) and .artwork (the two
                  covers handed over during the window), all three in Redesigned/Player/PlayerMix.x, drawn only for
                  known times (harness/player/automix-check.sh). Spotify keeps no transition fields written into its
                  queue from outside (seen on a 9.1.90 phone), so Retrine plans no transitions of its own
    SpotifyMetadata/ Spotify's metadata service for features that ask it themselves (SGSpotifyMetadata.h): the signed-in app's own
                  spclient headers, kept only from its requests to https spclient.wg.spotify.com (KaraokeSource.x's
                  rememberHeaders; any other host or http is never kept), sent only back to that host by an ephemeral session
                  with no cache, cookie or credential storage. Two requests are accepted, the album JSON GET and the
                  extended-metadata protobuf POST (SGSpotifyExtensionRequest builds its body); redirects are refused, and a
                  reply from another origin or over 2 MiB is dropped. Music Haptics' ISRC lookup and the redesign's Spotify
                  plays for albums use it
    SpotifyPrefs/ Spotify's preferences object, the one Settings > Playback writes, captured as Spotify makes it at
                  launch, for Lossless's streaming quality and AutoMix. Its user's settings read 0 until they are read
                  in, about 3 s into a launch, so SGSpotifyPreferences is nil until the playback speed (a percent, never
                  0) is set; then what Lossless and AutoMix left to do is done
    Sing/         Karaoke (Sing in the code and its keys), a song's vocals turned down while it plays (Sing.h lists
                  its files): the voice model Voice model chooses (spotifyglass.sing.model, read live: Best quality,
                  the default, is Mel-Band RoFormer, MIT, exported by Vitrine for the Neural Engine and palettized to
                  6 bits: separator-ane.mlmodelc, 210 MB; Light is the vocals of HiDolen's Mini-BS-RoFormer-18M, MIT,
                  exported in float16 by harness/sing/export_light.py with the same input and output:
                  separator-light.mlmodelc, 31 MB, more of the voice left in and the music dipping under it; both
                  from the same Hugging Face repo, each with its own pins, staging folder, resume data and paused
                  bytes; on a FLEX build a copy of the chosen one in Sing/dev/<its folder> comes first; a switch
                  stops a running download, keeping what came in, and Sing.x loads the chosen model at once, no
                  restart, or lets the old one go if the chosen one is not downloaded) downloaded and checked file by
                  file over Wi-Fi unless cellular is allowed,
                  a stop keeping what came in for the next download to carry on from; the 489 MB model downloaded
                  before is kept and loaded on the CPU alone until this one is in (the Voice model row then reads
                  Update available), and deleted as its download ends or at a launch that finds both
                  (SGSingRemoveOldModel, which logs the space freed), Sing moving to the new one at its next load;
                  loaded only while Spotify
                  is active (SGSingLoader.m), on any iPhone with iOS 18, a CPU copy first and warmed, only with 1 GB left to the
                  process (0.4 GB for Light, and 1.6 or 0.65 GB beside a load still out; no floor on the iPhone's memory: both copies warm add 0.1 GB of footprint), then on Automatic, where the iPhone has a
                  Neural Engine, a Neural Engine copy of the same model beside it, which takes every window once it is
                  in, in the background too, each load with a deadline and kept a minute after the mic goes off; the
                  Neural Engine copy loads only with 0.5 GB left to the process (0.25 GB for Light), its first load after every install
                  compiling it for up to ten minutes while Karaoke runs on the CPU (while it loads, the CPU's falling
                  behind spends none of the 8 s after which Karaoke gives a song up, nor counts toward its three in a
                  row), unless Prepare after updates (on by default) compiled it already: with the model in and the mic off, 15 s after
                  Spotify comes to the front or the music pauses, with the music paused, below the thermal state Fair and out of Low
                  Power Mode (compiled while music played, it heated the iPhone for a minute with nobody asking; cooling down or Low
                  Power Mode going off looks again), the Neural Engine copy alone loads once for this
                  iOS and install and is let go (22 s on a fair iPhone 15 Pro, 48-65 s on a serious one; a want meanwhile takes that
                  load over), so the mic's copy loads in 0.3 s; Karaoke's status reads "On, Neural Engine" or "On, CPU", and "Off ·
                  preparing for the Neural Engine" while it compiles ahead, and it is dropped for the launch, the CPU copy carrying on, once it fails to load, warm up or
                  run a window (one that falls behind keeps its place); Runs on is Automatic or CPU only, the GPU and
                  Neural Engine choices stored before read as Automatic; the STFT around it on Accelerate,
                  and an engine that stands in Speed and pitch's chain between Spotify's mixer and its output
                  (SGPlayerSetStage), pulls the mixer a few seconds ahead of what plays, never past sound Spotify has not
                  decoded yet (a part of a pull ahead its mixer marks silent is left out of the lead and read again at the
                  next render, so a slow network fills the lead more slowly and a stall plays through on it; "sing: read
                  ahead:" in the log, the first three times and then a count a minute), separates two-second windows
                  there on a worker thread and mixes the vocals down on the render thread. Spotify's clock has the lead
                  taken off (SPTPlayerState's positionAsOfTimestamp): the lead held when that line of the clock began
                  (the same position run on at the same speed, however often a state is stamped again), less what was
                  dropped since, as the player reports on a change and not as it plays (SGSingLeadOf, read by every
                  correction); run on (-position), the lead comes off after running on and never below 0, so a track
                  reached as the last one ends, reported while the lead still holds that end, stays at 0 until its first
                  frame plays rather than running on from the title change (every 5 s a "sing: clock:" log line sets Spotify's clock against what the engine pulled
                  and played, and every lyrics seek logs where it was sent and where it landed), and a seek, a skip or a stop drops it.
                  Until the seek or skip lands (Spotify reports the target or the new track, or 5 s pass) nothing is
                  read ahead, as Spotify's mixer still hands over what came before it; the queue's next track arriving
                  up to 12 s early is crossfade and keeps the lead, another track arriving early drops it; on the
                  queue's last track (no next, no repeat) the lead drains at half speed so it has played out a second
                  before Spotify's decoder reaches the end (SGSingEngineSetLeadCap). Not separating (stopped, held, resting at As sung,
                  standing aside), the engine plays the lead it holds on as it is, dry, the clock still corrected, so no
                  part of the song is skipped; it lets it go at a pause, where Sing.x seeks Spotify back to what was
                  heard (and so when the headphones it played on go), or with a seek, a skip or the output stopping, and builds one only when it separates.
                  Karaoke stands aside, the model kept, over AirPlay, for what is not a song, and while Spotify plays
                  but its output has not rendered for 3 s (Connect to another device: "Not on this iPhone"); an
                  interruption (a call, Siri, another app's audio) holds the worker and keeps the lead until iOS says it
                  ended or the sound comes back, Spotify deciding whether to resume. At As
                  sung with Spatial voice off it rests (held as for the heat, the model kept a minute as for a mic
                  switched off, "sing: rests" in the log) unless the Karaoke page's card is on screen with Spotify in
                  front: its reads of its two lines (SGSingReadLevels; the card's traces, not the lyrics, which are no
                  viewer) keep Karaoke separating the playing song, so the lines move and the slider is heard at once
                  ("sing: separates again"), and a second after the graph scrolls out of sight, its page leaves the
                  window or Spotify resigns active, it rests again. The card's status and VoiceOver text follow player
                  reports (a late title or artist too), Sing and level changes rather than a poll. From the
                  thermal state Serious up Karaoke is held and lets the model go,
                  unless Ignore heat warnings is on, and runs again at Fair. Spatial
                  voice holds the separated vocals in front as the head turns: HeadGestures' motion gives the yaw off a
                  front that follows the head (Back in front, 5 s unless set), and the render thread pans the vocals' middle at equal power,
                  narrowed, with the far ear up to 0.65 ms late and low-passed; it stands down for iOS's own spatial
                  audio. Its Sound section sets Distance (the voice down by the square root of the distance), Room
                  (a wet-only AUReverb2 fed the voice's middle, emptied by a seek) and Instruments width (the rest's side
                  scaled); off, all three leave the song exactly as it was. The Spatial voice page's preview (SGSpatialPreview.m) turns a disc of dots under the listener by
                  the same front (SGSpatialVoiceAngle, SGSingEngine.h), on Core Animation alone and only while the page
                  shows. The mic is on the redesign's lyrics (Redesigned/Lyrics/SGRSingButton.m). Tested on the Mac
                  against harness/sing/ (the lead, its cap, a slow decoder, a track boundary, spatial voice and its front without the model: `build/sing spatial`; the
                  model as both copies with `ane`, as the CPU's alone with `cpu`), the download against its download/
                  (`update` for the old model kept until it, `dev` for the dev folder), the pages in the simulator against harness/spatial-page/
    Haptics/      Vibrations (Haptics.h lists its files): a tap of UIKit's feedback generators for the player's and the now
                  playing bar's controls, the scrubber's tenths and ends, cover swipes, gestures and the lyrics page's tap to
                  seek, at the strength set for them (ControlHaptics.x, SGFeedback.m). The redesigned player's volume
                  bar also taps at sixteen steps, more firmly at zero and full volume, and on grab and release.
                  SGInstallVolumeFeedback attaches to local and Connect sliders, including replacement system sliders;
                  it uses the existing Controls switch (on by default) and Strength, with no separate switch.
                  Music Haptics, Core Haptics
                  playing along with the song: the music's RemoteIO output unit (SGPlayerMusicOutput, Shared/Player)
                  gets a render notify, the samples, in the unit's output format (the hardware's), go through a drum
                  and bass analyzer on the render thread (SGMusicAnalyzer.m, plain C), and a thread of its own schedules
                  the taps and the rumble for when the sound is heard, at their strength and leaving out what Follows
                  leaves out (MusicHaptics.x). Everything applies at once; nothing plays while Spotify is not the active
                  app. When Core Haptics stops or resets the engine the thread stops sending to it at once, waits for
                  an asynchronous stop to finish, and starts a fresh engine and players only after a cooldown; a
                  failed call on a running engine cancels its playback without counting as a stop, and repeated
                  failures are logged once (harness/haptics/sim/). Beside it, In the Background (iOS 18 and up) asks Spotify's extended-metadata for the track's
                  ISRC through SpotifyMetadata/ with Spotify's own spclient headers, asks Apple Music's catalog for that ISRC (the phone's own country first, then the US), and names the
                  matched song's catalog id (same ISRC, length within 2 s, a haptic track) or else the ISRC in the now
                  playing info for iOS's own Music Haptics, which plays on the lock screen and in other apps too
                  (SystemMusicHaptics.x, its pure steps in SGHapticTrack.m). Both may be on: while iOS reports the named song
                  playing, the mod's own stays quiet, since iOS plays the track in front of Spotify too, and also while
                  it asks (10 s at most) and for 3 s after a song is named; with no report by then, once iOS has none,
                  while iOS's is paused in Control Center or in an install iOS does not list, the mod's own plays while
                  Spotify is in front. The analyzer is
                  scored on the Mac against harness/haptics/, as are the pure steps (build/track), the hook, the two
                  switches, the stand-down and the move from the old choice in the simulator against its sim/, the
                  settings against harness/haptics-page/
    HeadGestures/ AirPods gestures (HeadGestures.h lists its files): CMHeadphoneMotionManager's attitudes, while the
                  switch is on, Spotify plays and at least one action is assigned, read for a double nod and a shake,
                  each doing what its pull-down
                  says: Nothing, back or forward 15 s, play or pause (which listens with the song paused too), next or
                  previous track, shuffle, repeat, or Like, which adds the track to Liked Songs through Spotify's
                  collection platform (addURL:showUIConfirmation:completion:); Like and Next track until changed. A
                  tone played through Spotify's playback session confirms each, whatever the Ring/Silent switch says,
                  unless Chime on activation is off (spotifyglass.headgestures.chime; Try it and teaching always sound).
                  Try it listens a few seconds and names in its row what it picked up, doing nothing to the song. A
                  sheet teaches one's own nod and shake, five of each after a tone, a ring showing the head live (a dot
                  that moves with it, ticks lighting toward where it went; SGHeadMotionListen) and five dots counting
                  what landed, with Redo last. Then 20 seconds of ordinary movement, the ring counting them down while
                  the sheet asks the user to look around, nod along and walk, with no Redo. Nothing is stored before
                  that check: each gesture's learned threshold is replayed over all the recorded motion and kept only
                  if it fires none of the 20 seconds, never fires as the other gesture during the other one's five
                  demonstrations, and recognizes at least 3 of its own 5 and at least 60% of them, and the 20 seconds
                  must be whole (a full span, no gap the detector cannot read through). Nod and shake are judged
                  separately, each against the other's stored threshold; when both pass on their own but would break
                  each other as a pair, the pair is tried together first, then the shake beside the new nod threshold
                  with the nod dropped, and otherwise the shake is dropped and the nod kept. When either is
                  accepted, that gesture's threshold is stored and Sensitivity goes back to its default 100%; a
                  rejected one keeps the threshold it had, and the sheet says per gesture what it recognized
                  and how often it went off during the ordinary movement; with neither accepted it says so and asks for
                  quicker, bigger gestures. Cancel keeps everything as it was, and so does an interruption — headphones
                  taken off, or the app leaving the front — which ends with "Nothing changed". (SGHeadGesturesFinishTeaching)
                  Forget shows only while something is learned.
                  The one CMHeadphoneMotionManager is lent to other features
                  (SGHeadMotionListen: Karaoke's spatial voice), and runs for them with the switch off, the detector then
                  unfed. The detector is
                  tested on the Mac against harness/head-gestures/, the hook and the page in the simulator against its sim/
    Keyboard/     the hardware keyboard's commands, in either look and with no switch of its own: Space play or pause
                  (offered only where Space is free — not while text is edited, not to VoiceOver, not to a focused
                  control), ⌘→ and ⌘← next and previous, ⌘L like, ⌘↑ and ⌘↓ the system volume, ⌘1/⌘2/⌘3 Home, Search and
                  Library, ⌘F Search, and Esc or ⌘W the player closed. The commands are one table (KeyboardCommands.m,
                  Keyboard.h), which also holds what the ⌘-hold overlay shows for each; they are added to
                  -[UIApplication keyCommands], the end of the responder chain, so nothing has to be first responder.
                  Volume moves 6.25 points a press (16 steps across the range), snapped to that grid and kept within
                  0–100%, through the slider of one off-screen MPVolumeView, so it is the system volume and never a
                  Connect device's; without a slider a press does nothing.
                  A destination opens only when Spotify's link dispatcher has a handler for its URI, and Home, Search and
                  Library are named rather than taken by tab position. ⌘F opens Search, then 450 ms later presses its
                  bar and takes the field of the input page that push brings, in one ordered run that a second ⌘F
                  replaces and that stops itself if the user is elsewhere by then. Esc and ⌘W press the player's own close control, looked for at most
                  every 300 ms and only while no other window covers the app. All of them are skipped while text is
                  being edited. The screen the app shows and what is presented over it come from Core
                  (SGTopController.h), which the phone driver's `state` reads too, so a command and the driver never
                  disagree; whether a window of its own covers the app, which is what leaves Esc to a sheet or alert,
                  is read beside the commands (SGKeyboardWindowCovers). The volume grid, the table's inputs,
                  modifiers and titles and the screen and window readings are checked on the Mac against
                  harness/keyboard-commands/ and
                  harness/keyboard-top-controller/; the keys themselves are the phone's
    LiveActivity/ a Live Activity on the lock screen and in the Dynamic Island in one of three views, the line being
                  sung with the next one under it, the tracks up next (a tap on one skipping ahead to it), or a control
                  menu of tabs, Controls (previous, play and pause, next, shuffle, repeat), Queue and a sleep Timer of
                  the mod's own (Player/SleepTimer.m: 15 min, 30 min, 1 hour, End of track, End of album) that fades
                  the sound out and pauses Spotify, and stays set when the card is switched off (LiveActivity.h lists its files): a timer polls the player and
                  sends a new state only when what the view shows changes, local updates only, no push, and asks ActivityKit
                  only then. A strict main-queue dispatch timer, not a run-loop timer that iOS can defer with the screen
                  off, polls once a second, or sooner for a playing lyric boundary. Unchanged states are coalesced;
                  queue and panel rebuilds stop after three qualifying upcoming tracks. The lyrics
                  reader requests missing lines independently of artwork or an open player, and a lines-kept notification
                  sends the current line at once, including in the background. The lyrics keeper tells the card
                  whether a lookup ended; an evicted miss can be looked up again on revisit. The card
                  is tinted with the cover's color and shows the cover itself, a JPEG of a few dozen pixels inside
                  the state, which ActivityKit caps at 4 KB (the bridge sends it without the cover when it would
                  not fit); the color is darkened to a luminance of 0.04 at most, so the white text keeps 4.5:1 on any
                  cover, and the cover is read only once the now playing title is the new track's. The page's options
                  ride in the state too, read on every tick, so they apply within a tick: the lines' alignment, what the
                  lyrics view shows on a track with no timed lyrics (a note under the track, or the track large), the
                  colors (Spotify's green; Artwork, the cover's color lightened to about the green's luminance in its
                  place; Plain, white on the system's own background), and the progress bar. Artwork off sends no
                  cover at all. The page's preview (SGLiveActivityPreview.m) is a mock of the card in UIKit, not the
                  widget; its callbacks, conditional rows and restored choices are checked in the simulator against
                  harness/live-activity-page/. Taps are
                  LiveActivityIntents run inside Spotify and take a second or two to show on the card. The widget is extension/LiveActivity; ActivityKit pairs the two
                  by the attributes' type in LiveActivityShared.swift, compiled into both. It starts only with Spotify
                  in front; its settings apply at once. It ends when Spotify is swiped away while running; killed
                  while suspended, Spotify cannot end it, so each state goes stale a minute on (an unchanged card is
                  sent again every 20 s) and a launch ends any left over before it starts a new one. The same folder
                  gives Siri, the Shortcuts app and the Action button Like This Song, Play or Pause, Next and Previous
                  Track, Karaoke and Sleep Timer (AppShortcuts.swift lists them as Spotify's App Shortcuts), and iOS 18
                  controls for Control Center and the lock screen of Like, Karaoke and the sleep timer
                  (extension/LiveActivity/Controls.swift), buttons, as the extension cannot read Karaoke's state. Each is
                  a LiveActivityIntent or AudioPlaybackIntent, so it runs inside Spotify, launched in the background
                  when needed, and LiveActivity.x answers it with the activity on or off, Like through
                  HeadGestures.x's collection platform and Karaoke through SGSetSingOn; the sleep timer (15 min, 30 min,
                  1 hour, End of track, End of album or Off) is the card's own, Player/SleepTimer.m, which keeps its
                  own clock with the activity off. The intent asks again for 8 s while the player is not up,
                  then tells Siri to open Spotify. Checked in the simulator against harness/shortcuts/

                  Install limitation: LiveContainer runs Spotify as a guest, not a separately installed app, and
                  upstream LiveContainer does not register guest app extensions with SpringBoard. Retrine cannot
                  register its Live Activity widget or change the installed host's capabilities from inside that guest;
                  even its install check reads NSBundle.mainBundle, which LiveContainer replaces with the guest bundle.
                  Use Retrine's IPA installed directly, retaining its Live Activity extension, and enable Live Activities
                  for that installed app. Updating Retrine inside LiveContainer alone cannot supply the missing widget.
                  The lock screen's now-playing lyrics/artwork is a separate feature, not this ActivityKit card.
                  NSSupportsLiveActivitiesFrequentUpdates, written by Retrine's IPA overlay, raises the remote push
                  update budget; this card uses local updates with pushType nil, so that key is not a fix for delayed
                  local lyrics. Actual locked-screen delivery and any system throttling still require a device check.

    ListeningStats/ listening stats kept on the phone (ListeningStats.h lists its files): each music track timed while
                  it plays through PlayerState's observer and written to a text log in Application Support once it ran 30 s
                  or half the track (ListeningStats.x; a track repeated on repeat one or queued twice in a row keeps its
                  URI but gets a new playbackId, which starts a new play, so each lap counts and a seek does not split one;
                  a play in progress is also written down when Spotify terminates or a setting's Restart now quits it, via
                  SGWillRestartNotification, while one cut off by Spotify being killed is lost),
                  Spotify's data export read in, either shape, loose, zipped or from a
                  selected folder, and Retrine's own versioned JSON history imported or exported without an account. Plays
                  already there are skipped (SGPlayLog.m); input is bounded to 64 MiB per JSON, 256 MiB total and one million
                  plays. Its page leads with the current and best day streak and their dates, then a calendar week, month or
                  year stepped through one at a time (the calendar's first weekday), with a bar per day or month, the time
                  and plays, top tracks, artists and albums, and a locale-formatted hourly breakdown; all time stays a row
                  of its own. Each top list's heading opens a chart of that period (SGTopCharts.m, TopChartPage.m): up to
                  50 entries by plays, then time, each with its move against the period before, NEW when it was not in
                  that period's top 50, and its run of periods in the top 5; songs, artists or albums played and
                  discovered (never played before the period). Recap (SGRecap.m, RecapStory.m) plays a year with 30 or more
                  days with plays as seven cards (time, top artist, song and album, discoveries, active days and the
                  longest streak, peak hour and month), each shareable as a 9:16 picture; a year belongs by each play's
                  end. From 1 to 14 January the year just ended is announced once (`spotifyglass.stats.recap.announce`:
                  in Retrine Settings by default, when Spotify opens, or off; the year announced is kept as its number).
                  File parsing, traversal,
                  aggregation and serialization stay off the main thread. Tested on the Mac against harness/listening-stats/,
                  the page and the recorder in the simulator against its sim/
    Connect/      Connect speakers on the Wi-Fi for a build signed without the multicast entitlement (Connect.h lists
                  its files): Bonjour, which needs only NSBonjourServices (plist/, merged with Spotify's own list by
                  pipeline.sh) and the Local Network permission, finds and resolves _spotify-connect._tcp; Spotify's
                  imports of sendto, sendmsg and recvfrom are rebound, a Connect query the system refused is sent by
                  unicast to each receiver's port 5353 instead, and each answer is passed to Spotify's socket over
                  loopback with recvfrom reporting the receiver as its source. Spotify asks the same question from four
                  sockets, two for each address family, every two seconds or so; it is relayed once every 3 s for each
                  family (on a busy Wi-Fi with 21 receivers, 124 rounds a minute became 31), and a new question goes at once. No setting. Tested on the Mac against
                  harness/connect/

Native:

    Appearance/   AMOLED (Amoled.x), the accent color (Accent.x), the soft top edge (EdgeEffect.x), the explicit badge hidden by
                  a mask (ExplicitBadge.x), and Repaint.x, which
                  keeps what the native tweaks stripped transparent
    Navbar/       Spotify's tab bar composed (Navbar.x, NavbarLayout.m, hooked from TabBarHooks.x), the Navbar and Add a tab pages
    NowPlayingBar/ the device button hidden, the bar's flags
    Player/       the full screen player (Player.x), its cards and buttons hidden and a hidden lyric preview's room given
                  to the cover (PlayerDeclutter.x; with all nine cards hidden the list's section headers collapse
                  too, never one holding the slider or controls, and the trailing blank scroll space is removed),
                  the glass lyrics card (LyricsCard.x), the gestures' hookup and the hold
                  on either side of the cover that plays at the Gestures page's hold speed until the finger lifts
                  (PlayerGestures.x), the list's pull
                  held off while the progress bar is scrubbed (PlayerScrub.x), the Queue & devices flags. The scrub and
                  the cover's room are checked in the simulator against harness/native-player/
    Lyrics/       the full screen lyrics page on glass, and a tap on the lyrics' footer opening the pages a credit
                  links to (LyricsPage.x)
    LocalFiles/   a lyrics button on the player's footer for a song with a linked import, or a local file with
                  embedded or name-matched lyrics. The viewer honors provider picks. The button sits a fifth of the
                  way in from the leading edge, which opens a page of lines on black. Player reports update the page
                  on track changes, seeks and resume; only advancing timed lyrics arm a line deadline, capped at a
                  quarter second because speed can change between reports
                  (LocalLyrics.h lists its files); the file's metadata says has_lyrics. Checked in the simulator
                  against harness/local-files/lyrics/. And the file's own cover where the player shows
                  Spotify's placeholder (LocalCover.x)
    Home/         the Home gradient, Home's sections and pills hidden (HomeDeclutter.x), the native Library flag rows
    Playlist/     the playlist header and pills, hidden one switch each
    Album/, Artist/ their pages' parts hidden, and the cover or photo behind their headers

Redesigned:

    Kit/          what the redesign builds on (SGRKit.h lists it), the flags it forces (SGRedesign.h, SGRGlassDesign.x for
                  Spotify's own glass design), its repaint hook (SGRRepaint.x), soft top edge (hard where a page asks for
                  it, SGRHardTopEdge), AMOLED black (always on, SGRAmoled.x) and its own accent color (SGRAccent.x, stored
                  apart from the native look's, with Automatic following the page in front and then the cover, SGRAccentContext.m, and the
                  explicit badge's mask, SGRExplicitBadge.x). In both looks, enabling the badge switch scans scene
                  windows once. A badge detached during that scan is masked when it enters a window. Disabling restores
                  each masked view, including detached ones. The off path does not classify views.
                  The playlist, album and artist pages take their field's color from the
                  cover's main color (checked on the Mac by harness/palette/), and come in whole: a black veil over the
                  page until the cover has been read, at most SGRFieldHoldLimit (1 s), then faded away (SGRField.h). The album and playlist covers are laid out per page
                  (Cover layout on the Albums and Playlists pages, Card or Full screen; spotifyglass.redesign.album.fullCover
                  and spotifyglass.redesign.playlist.fullCover; unset, an album is Card, the Music app's centred cover, its
                  animated cover still filling the hero, and a playlist Full screen; a stored choice wins; SGRPageFullCover in
                  SGRHeaderInfo.m). Under the cover the title is Title 2 bold, the creator Title 3 regular and the kind and
                  date or length Caption 1 semibold in the secondary color (the Music app's sizes, capped at Extra Large;
                  SGRHeaderInfo.m infoFont); the artist page's name is Large Title bold, centred like the album's (largeTitle).
                  The first read of either carries the global switch of before (spotifyglass.redesign.fullBleedCovers) into both
                  where they have no value of their own and sets spotifyglass.redesign.fullBleedCovers.migrated; the old key is
                  left alone for a downgrade and never read again. In Card an album's animated cover still fills the hero.
                  Pulled down past the top, the album and artist heroes stretch their artwork from the top edge instead of
                  leaving a gap and return exactly to their rest size on release (Kit/SGRStretchHero.m): the pull is read
                  from the overlay that actually scrolls, its rest at -adjustedContentInset.top; the rest-sized rendering is
                  reused while pulling, so a pull asks for no new render; the bottom fades by a mask over the field, not a
                  flat colour, since the field darkens lower on the screen; the album cover stays tappable and accessible,
                  and Blur covers on scroll follows the same scroll owner (harness/album/, harness/artist/).
                  Picture-aware cover (spotifyglass.redesign.album.adaptiveCover, off, read at launch, shown with Full
                  screen) reads the cover once off main (Kit/SGRCoverRead.m: a 64 px OKLab sample, solid, dark-with-accent,
                  portrait, colourful or edge, Vision faces and saliency for the non-solid ones, 64 readings cached) and hands
                  the field its colour (SGRField's overrideColor); the hero keeps the cover sharp down to a boundary below the
                  title and faces, then blurs it into that colour in an image drawn off main at 2× at most
                  (harness/album/cover-check.sh). Picture-aware photo (spotifyglass.redesign.artist.adaptivePhoto, off) gives
                  an artist page the colour under the shown photo with its faces left out, the photo itself drawn as before
                  (harness/artist-artwork/photo-check.sh). Artist picture on the Albums page
                  (spotifyglass.redesign.album.artistPicture, on, live) shows up to three of the artists' faces from
                  Spotify's own artist line, overlapping with a cut ring, or the name alone (SGRHeaderInfo.m's
                  SGRCreatorFaces: only image views shown before a shown name); an album's track rows draw their ⋯ in a
                  soft tint of the page color, through a layer masked by the glyph's own picture when its color is baked
                  in (AlbumRows.x; harness/album/faces-more-check.sh).
                  Two of the player controls' own refinements live here too (SGRRefinements.h, whose decisions are
                  plain functions the views follow): a label SGRRollDigits marks is monospaced and has each change of
                  its text shown by SGRDigitsChangeFor's rules — the characters that differ roll up into place over
                  0.25 s, by cutting their columns out of the label and drawing them in an overlay of its own that no
                  accessibility sees, so Spotify's text, its accessibility and its drawing stay Spotify's; the first
                  value, a label just moved into its window, a change within 0.15 s of the last (a seek or a scrub) and
                  a text with a right-to-left run are shown at once, Reduce Motion crossfades in place, and nothing runs
                  between changes (SGRRollingDigits.m reuses digit images and equal-width time columns until their style changes;
                  SGRRestyle.m skips repeat writes from the same text setter
                  if the label still holds the mapped output; it reports other writes and each
                  move to or out of a window), checked on the Mac by harness/player-refinements/. And a live preview
                  card that leads the redesign's Playlists, Home, Search, Albums, Artists and Library pages (SGRPagePreview.h):
                  a plain-view mock of the page those settings change, drawn over local placeholder art, that follows
                  the page's switches as they are flipped, at the top of the page in the table's header with the page's
                  note under it (SGRPagePreviewPage). A hidden part fades where it is and the parts under it move up
                  into its room; the card reads the page's own preference readers in two steps (state, then apply), and
                  while it is in sight redraws only for a value unlike the last one drawn, in the redesign's layout
                  motion; out of sight a change is only noted and is drawn when the card is back, and coming into a
                  window it draws at once from the top of the page. A change to a part below the card's foot scrolls
                  the mock to it. Its text grows with the reader's to half again the size and the card with it; VoiceOver
                  reads the card as one image naming the parts shown. Checked in an iOS simulator of its own by
                  harness/page-previews/, which writes each card's states to PNGs
    Navbar/       the glass tab bar (TabBar.x) over its own composition (Navbar.x, NavbarLayout.m) and editor, the glass search field.
                  Spotify is made to leave the glass bar its height where its own bar is shorter (a phone with a home button,
                  Offline or Private Session under the bar), so the now playing bar and the pages move up with it. Under both
                  bars the pages fade to half black. SGRBarFade sits behind the glass inside the stock bar, so it hides
                  with the bar. Its sides are constrained to the tab bar container and stay aligned as the iPad player
                  panel opens or closes. Its top follows the glass 88 pt above it; its bottom reaches the lower of the
                  glass and container bottoms (16 pt below the stock bar on iPad). Fade under the bar on the Tab bar
                  page (spotifyglass.redesign.navbar.fade, on by default) removes the fade and its constraints when
                  switched off. The page's preview draws the same ramp over its own rows. Apple symbols on the Tab bar page (spotifyglass.redesign.navbar.symbols, on until
                  switched off, applies as the bar lays out again) draws each of Spotify's tabs with an SF Symbol for the
                  page it opens, filled on the selected tab where the symbol has a filled variant: Home house, Search
                  magnifyingglass, Your Library books.vertical, Create plus, Premium crown, any other square.grid.2x2. The
                  page comes from the list of tabs Spotify reads (Navbar.x keeps each label's URI, SGRNavbarStockURIs), so it
                  holds in any language; a tab whose page the list has not named keeps Spotify's glyph, and a tab of the
                  mod's own keeps the icon picked for it. The bar takes its items again when one that had no glyph gets
                  it: in a regular width UIKit sets each name beside its glyph and sizes the tab as the bar takes the item,
                  so an iPad cut the names of items handed over bare (harness/tabbar/ipad-check.sh). A page scrolled down
                  minimizes the bar to glyphs on circles: at the trailing end the last split tab or, with none, Spotify's
                  Search wherever the row holds it, as the Music app keeps Search there (known by the page it opens in
                  Spotify's list, 9.2.0's spotify:search or 9.1.90's spotify:find, never by its name or place; a tab
                  of the mod's own is never it), drawn selected when it is the tab you are on; at the leading end the
                  tab you are on, or when that is the trailing one the first other tab of the main bar. The now playing
                  card stands between the circles, or with no trailing circle runs to the bar's trailing inset. A tap on
                  the trailing circle opens its tab as a split tab's circle does, also after the tab was left from elsewhere, and a scroll back up, its top, another
                  tab, the player or a window widened to a regular width brings the bar back (TabBarMinimize.x, MinimizeStep.h; the Player page's Apple
                  Music style). Spotify's container is no UITabBarController, so UIKit's tabBarMinimizeBehavior and
                  bottomAccessory cannot do it. The bars, their circles and the card move as one, on one spring of their own (SGRMotionBar, 0.26 s, no
                  overshoot; at once under Reduce Motion), from what is on screen, so a change turned back half way
                  carries on from there. A tab keeps one glyph as it moves between the row and a circle: its new button
                  starts where its old one's glyph was, on either bar; Search's circle comes out of Search's place in
                  the row, over the shrinking main bar. Expanding, Search's glyph goes back to its place in the row as
                  a view of its own over both bars, on the bar's spring, drawn as the row draws it (lit when Search is
                  the tab selected), the row's Search glyph cleared and its name left to the row; the circle, its own
                  glyph hidden, travels horizontally under the main bar, level with the row even when the glyph rises
                  above its name, and its glass goes in the very frame
                  the growing platter reaches it (issue #35: drawn over the row it was a darker disc), timed off the
                  spring UIKit made, its layer's opacity held over a model of 0 so a busy main thread cannot make it
                  late. As the spring ends the row's own glyph, which the spring has brought to the same place, takes
                  over; a change that turns the expand back takes Search from the row and the circle as it is shown.
                  Search's glyph is never under another bar's glass, and no glass is drawn over or under the growing
                  row's. No glass fades. While the bar is minimized the card follows its slot when the trailing
                  circle comes or goes with Spotify's list of tabs. The selected tab shows Spotify's filled glyph and the others their outlines, also
                  after the bar minimizes and expands and when a tab's view is handed another icon: an older
                  SPTEncoreIcon gives its filled variant through -active, and 9.1.90's Swift Encore.Icon is drawn once with
                  isActive set and then put back; the images are kept by the glyph drawn, not the label's color
                  (harness/tabbar/bar-check.sh, `glyphs` and `glyphs swift`). Each glass tab carries its name for VoiceOver and the large content viewer, labels
                  hidden or not, and the leading circle says it shows all tabs. Laid out on
                  the Mac against harness/tabbar/ (`mini`; a tap on the leading circle `tap`, real flings that turn
                  the bar half way `turns`, a minimize from inside Spotify's own animations `nested`, every frame of
                  the move sampled `motion`, Search on the trailing circle and drawn once through every move `search`, what an earlier state leaves `states`,
                  one expand recorded off the screen frame by frame by harness/tabbar/capture.sh),
                  the scroll's steps checked by harness/tabbar/minimize-check.c
    NowPlayingBar/ the glass now playing bar (NowPlayingBar.x). Video artwork that is not square is masked to the
                  centred square in the chosen artwork shape until a square cover returns (harness/now-playing-bar).
                  A hidden or covered title or artist holds its marquee at its current offset and continues there on reveal.
                  A regular-width iPad automatically gets a capsule
                  with shuffle, repeat, lyrics and queue alongside artwork, title and play. Shuffle and repeat use
                  Spotify's player commands; lyrics opens the player on its embedded lyrics, and queue opens the
                  existing Playing Next sheet. The capsule grows toward, but never within 16 pt of, the nearest tab platter seen on its row, a split tab's circle included.
                  Device and add step aside; optional Next remains. Compact-width iPad and iPhone keep the card.
                  Capsule commands mirror with the window's direction. Play and inactive commands are white;
                  shuffle and repeat use the accent only while Spotify reports them active.
                  Following the adjacent tab platter reacts to changed geometry, not repeated assignments of the
                  same frame, bounds or center: those KVO setter notifications must not start another bar layout.
                  Spotify's device button on it is hidden unless switched back on, as the Music app's mini player has none
                  (BarConnect.x, its own key and its own row on the Player page, apart from the native look's); the bar at the top of Spotify's sheets (the DJ request one) keeps it. Unless
                  switched off a Next button of the mod's stands after Spotify's button stack, last in the row that holds
                  the track's information and that stack, as large as play's item (its touch target at least 44x44 pt,
                  the part outside Spotify's 40 pt row handed to it by the page's hit test), and asks the player for the next
                  track (among Spotify's buttons it made Spotify, which moves them by index, put add after play); it stands aside in the minimized row with
                  the device and add buttons. The cover is a circle, or a rounded square with 8 pt corners (Artwork
                  shape): standing 8 pt in from the card's 24 pt corner, a corner of any radius stays inside the card's
                  curve, so the cover keeps Spotify's 40 pt (the jadetheda fork shrank it for its fully round 56 pt
                  capsule). The views this file rounded are marked, so a change of shape rounds them again, and
                  SGRNowPlayingArtworkFrameIn hands the morph the radius shown (harness/now-playing-bar/). Above the
                  tab bar the card is exactly as wide as the glass tab row, split tabs included, like the Music app's mini
                  player (SGRTabBarGlassRow in Navbar.h, posted at most once a run loop turn when the row's edges change);
                  outside the iPad capsule, a regular width or right-to-left layout keeps Spotify's edges, and a Jam never puts it inline. The card's text is the Music
                  app's, the title over the artists with no device line, drawn inside Spotify's own text on each swipe page
                  so it slides and fades with it; Spotify lays a page out as "title • artists" over the device line or as
                  title over artists, and both are read. In the minimized row
                  the card drops its device and add buttons, faded out as it heads there and back in as it leaves. Only the title stays in the row. In a Jam the
                  glass stays on the track and Spotify's Jam strip gets a pane of its own above it (harness/tabbar/, jam)
    ContextMenu/  the ⋯ of the player and the ⋯ pinned over the playlist, album and artist pages open the system menu,
                  always (ContextMenu.h). The player's ⋯ is a pull-down button of the mod's beside the title, Spotify's
                  own hidden in the header: the menu opens on touch down with the quick row (Spotify's items 9, 19 and
                  11), the title row's add button, named for what its tap does (Save to Your Library, or Change Where
                  It's Saved for a saved song, which opens Spotify's sheet of where it is saved; never read as Liked
                  Songs, Spotify's own Like row staying in the menu), drawn as Spotify's plus or circled tick, and left
                  out with Star add button on, which keeps the add button on the row as a star, and Spotify's X where the
                  row has one, each left out while Spotify's rows in the menu offer its action, matched by the row's
                  identifier (Spotify's item number, the same on 9.1.90 and 9.2.0), never by its words: Add to Liked
                  Songs (18; Add to Your Episodes for an episode), which a song not saved yet has, for the add button, and Hide in this playlist or album
                  (7) for the X, which hides the song there. Out of a playlist or album (a song played from Search), in
                  Liked Songs, or for a saved song, the sheet has no such row and the item stays. Until Spotify's
                  rows are read this goes by the stored rows the menu shows (their identifiers stored with them), so
                  the menu opens as the last one did; the live rows put it right while the menu is up (the item back
                  if they lack the row or have it grayed out), and so does giving up on them, so an action is never
                  missing. A stored row picked that stands for an item is any stored row: Spotify's live row of its
                  title if enabled, else Spotify's own sheet; never the item, which could act on another song or do
                  another thing. Then the rest of
                  Spotify's rows laid out in the menu, then the player's own items, waiting on
                  nothing of Spotify's (the button holds a stand-in menu from the start, since UIKit opens
                  a button's menu on touch down only while it holds one, and the session's replaces it as the touch
                  asks); Spotify's ⋯ action is then run from code and its sheet presented
                  in a window of the mod's under the app's (the menu, a presentation of UIKit's from the player,
                  leaves no room for another there), read, and used to run a pick. On an iPad that sheet is a popover
                  from Spotify's ⋯ (a UIPopoverPresentationController of NavigationUI_SheetImpl's), which UIKit drops
                  without a word when it is presented from the mod's window with its source view in the app's, so
                  its source is moved first to the same place on screen in the mod's window. A sheet that does not
                  come, or comes and is never presented in the mod's window (no presenting controller), within the
                  three-second request window ends the wait: the loading row gives way to "Spotify's options did not
                  load" and the lead items come back. One still being presented then goes on to the rows' own
                  bounded wait, so a pick made before keeps waiting for its row.
                  Spotify's rows show the last
                  complete set stored for that kind of track (spotifyglass.redesign.player.menuRows.<kind>), or the
                  system's loading row the first time, and are put right in place as the live rows come. A page's ⋯
                  works the other way round: its tap (claimed as it fires, so a press let go off the ⋯ claims nothing, and claimed by one sheet only) opens Spotify's sheet, presented unanimated in a container hidden
                  from the presented controller's viewWillAppear: on, and the menu comes from an invisible button
                  inside the ⋯ that takes touches only while it is up, opened with -performPrimaryAction (else
                  UIContextMenuInteraction's private _presentMenuAtLocation:). Spotify's rows, read off the sheet's
                  cells (words, glyph, grayed out), and the mod's own rows in its header and footer (Sort, Mix, Edit
                  info) are fired on the hidden sheet once the menu is gone, through the row's own control (scrolled
                  to when it is below the fold); a row that pushes a page shows the sheet on that page, one that
                  presents a sheet of its own (Sleep timer) leaves that sheet as Spotify's and the card goes unseen,
                  and a close with no pick dismisses the hidden sheet. A pending player request accepts only
                  Spotify's context sheet or its known lazy wrapper, never a mod panel, with no presenter-ancestry
                  restriction. The pending request keeps the session alive after a pick or close: a Spotify pick
                  fires when the sheet arrives; a mod pick or cancellation discards the next Spotify sheet within
                  the three-second request window. This is not request correlation: newer requests replace the
                  single pending slot, so overlapping A/B deliveries and page ⋯ gestures within the recency window
                  remain documented ambiguities. A sheet arriving after the window is not adopted or suppressed
                  by that request. Checked in the simulator against
                  harness/system-menu/
    Player/       the redesigned full screen player (Player.h lists its files). In a regular-width iPad's expanded
                  player, artwork and Spotify's control units occupy the leading column; the existing embedded
                  lyrics view or PlayerQueue.m's list occupies the trailing column. Lyrics is the default when
                  available, queue otherwise; the footer buttons select the column's content. No new switch.
                  Both orientations use these columns, mirrored for RTL, with leading-column-first VoiceOver order.
                  The leading footer sits above the window's bottom safe area; the lyrics options button stays
                  inside the trailing column's safe area, rather than following the single-column footer.
                  On iPadOS 26 and later the visible safe rectangle uses UIKit's vertical corner-adapted safe-area
                  region, keeping the system's window-control corner clear; the redesign draws no window control.
                  Returning to one column restores the exact cover list the overlay faded, even while Spotify hides
                  its outgoing cover cell during a resize. The artwork band is identified inside that cell, not by
                  matching its temporarily stale width to the player's, and the lyric thumbnail stays below the header.
                  PlayerLandscape.x already limits its separate landscape window to iPhone; it is not used on iPad.
                  Compact windows and Spotify's narrow side panel retain the existing single-column layout.
                  `harness/player/ipad-check.py --screenshots <directory>` checks disposable iPad/iPhone clones,
                  including compact width, RTL, accessibility text size and hidden-cover restoration,
                  and captures the layouts. Its width overrides are harness tests, not system window-control transitions;
                  they do not establish behavior on iPadOS 27.
                  The header has only the Music app's grabber, a 60 × 4 pill 7 pt under the screen's safe area in a
                  44 pt touch area that lies wholly inside the header row: Spotify's ⋯ is put away (alpha, out of
                  VoiceOver's reach), and its down arrow too once the arrow has a tap's action to close by
                  (SGRControlActionEvents); the grabber then closes the player by that action on a tap, VoiceOver
                  activation or the escape gesture, answering whether it was sent, and reads the arrow's words. An
                  arrow with no such action stays as Spotify's, on glass as Header glass says, and the grabber is only
                  drawn. A swipe down still closes the player (PlayerHeader.x). The progress bar
                  and the volume row are drawn the one way, the Music app's, on every iOS: default-style sliders with an
                  empty thumb whose tracks are 7 pt capsule images (SGRPlayerBarImage, Spotify's track height), so the
                  fill ends square inside the round track. They are translucent: the fill a light white the background
                  shows through, the track dimmer. On podcast episodes with chapters, the loading band sits on the
                  chapter bar, running from the thumb no farther than the bar's rounded end. Spotify still controls
                  when it appears and how it animates. Both progress sliders skip playback updates within the same
                  device pixel, never rounding Spotify's value or filtering tap-to-seek, animated, tracking or off-window sets.
                  PlayerProgress.m stops the work upstream when a NowPlaying_ElementsImpl duration tracker
                  has written only invisible views. The mini bar rests under the settled player, detached
                  time labels rest until mounted, and the player's own slider rests after the lyrics controls
                  finish fading, not merely because lyrics opened. The landscape player's own window covers
                  the portrait rails. During an interactive compact morph the player rail is live; the mini bar is a snapshot.
                  A reveal refreshes from Spotify's clock
                  before the controls return. Spotify's own pause request is kept independently; the sticky
                  header, unrecognized links and links with no known output stay under Spotify's control.
                  Visibility and layout events drive this; there is no polling timer.
                  A visible tracker with a slider asks for 10 Hz only if its track advances at most
                  ten device pixels per second. A scrub, unknown geometry or duration, or a faster
                  bar uses Spotify's requested range; a label-only tracker keeps its range. Settled
                  callbacks forward without rediscovering the outputs or observing animated digit labels.
                  Both track colors are more opaque under Increase Contrast (SGRPlayerBarFill,
                  SGRPlayerBarTrack). Over a light backdrop they are drawn at the plain alpha that equals the Music app's white
                  ADDED to it (fill 0.44, volume fill 0.55, track 0.175; SGRPlayerBarFillOver, SGRPlayerBarTrackOver over
                  SGRInkPlainAlpha), so a white cover's bar is white and not gray; over a dark one that is the usual 0.6 and
                  0.2. The volume row's speaker glyphs and the footer's glyphs at rest follow the backdrop the same way
                  (0.46 added; PlayerVolume.m, PlayerFooter.x refreshFooterInk). A finger dragging either thickens its track 1.75 times, to 12 pt, about its middle
                  (SGRPlayerBarDragHeight) and lights the fill whole white: the progress bar's as a rail of the mod's own
                  drawn over the slider while it is held — one capsule clipping a rectangular fill to the value, Spotify's
                  track image views hidden under it and given back on release, so the held shape does not depend on how
                  UIKit stretches a track image (issue #30: a disc drawn across the whole bar as a lens); checked by
                  harness/player/scrub-capsule.inc — the volume's through taller images (PlayerVolume.m). The volume's slider tracks a drag from its fill's
                  end; a sideways drag starting anywhere else on its row moves the volume by the finger's distance, as
                  iOS 26's thumbless slider did, and a tap there moves nothing. Its ⋯, beside the title and artist where the add button was
                  (PlayerMenu.m), opens the system
                  menu (ContextMenu/), Spotify's rows with the add button and X first (each but where Spotify's rows have its action) and then Speed, Pitch & Reverb, which opens the sliders, Pitch
                  follows speed and Keep for This Song in a popover from the ⋯ (SpeedPitchMenu.x, Shared/Player), then Audio effects, which
                  opens the Audio effects page in a sheet with its summary under the name (SGDSPShowSettingsSheet, Shared/AudioEffects), and the backgrounds it can switch
                  to (PlayerMenu.m), and a hold on either side of the
                  cover plays at the Gestures page's hold speed (2× unless changed) until the finger lifts
                  (PlayerArtwork.x), higher in pitch while Pitch follows speed is on (an octave at 2×). Hide on the player's Shuffle and Repeat (spotifyglass.redesign.player.hideShuffle,
                  .hideRepeat, read at launch; the Player page's Buttons chips, selected = shown) take those buttons off the controls by alpha in their slots, as the
                  Music app keeps them off its own (PlayerControls.x). With neither shown in portrait (both hidden, or a row
                  Spotify builds without them, a Free account's), previous and next move outward so each is
                  min(a third of the room between the 32 pt margins, 140 pt) from play's center, less where that would take a
                  button past the row's edge and not at all where it is already farther out; play stays centered and
                  every button keeps its size, and the move is a translation set in the unit's own layout pass, so
                  Spotify's layout stays underneath and comes back exactly when a button is shown again. They stay out
                  while Spotify takes the repeat button out and puts a new one in (9.1.90), and the emptied ends take no
                  touches meanwhile, so a tap where next lies over repeat's end is next's; a shuffle or repeat Spotify
                  brings back ends the spread on its arrival. With either shown, on a podcast's row whose ends hold the
                  15 s skips, or in landscape, the slots stay Spotify's. In portrait on an iPhone-shaped one column player
                  the Music app's measures hold (Player.h, PlayerFooter.x keepRhythm): the title row, progress bar and
                  volume row stand 32 pt in from the sides (SGRPlayerSideMargin, set through the constants of Spotify's own
                  side constraints so the content lays out for the width; Spotify's own lyric preview under the cover,
                  shown while the lyric line is off, is inset in the cover's column to the same margin, PlayerLyricLine.x;
                  where the title starts in its row is read from the pass that insets the row and read again while the
                  row is not inset, and a unit that laid out before its row placed the title, a song started after the
                  app opened on a video podcast, is asked for another pass a second on), the cover keeps Spotify's tilt view's size (24 pt
                  in on a 402 pt iPhone, 354 pt, as the Music app's) and is drawn up to 33 pt under the window's safe area
                  where Spotify's tilt view stands lower (PlayerArtwork.x; only up, never in landscape or on an iPad,
                  never over a header row that takes touches: with Where it plays from on, Spotify's arrow live
                  or the AI DJ's buttons, it stops at the row's bottom where the row is now in its own player, followed
                  live as the switch changes and as Spotify moves the row with no layout of it, and the lyrics' and the
                  queue's thumbnail stands 8 pt under such a row, PlayerLyrics.x, and the scrolled queue fades it and the
                  title out before they reach the row; with Volume off, the rhythm holding
                  the stack and no lyric preview under the cover, the cover is drawn half the volume row's room (25 pt)
                  lower, so the room the title row's move leaves splits evenly over and under it; with the row put away, a
                  touch on the drawn cover landing in the row, off any control Spotify still shows there (an iPad's button
                  to widen the player), or on a view holding nothing but the row goes on to the cover, decided at the touch
                  from the views as they are, with nothing switched off on Spotify's (PlayerHeader.x passesTouches); the
                  row's controls and its parts off the cover stay Spotify's; it takes
                  touches, and VoiceOver's frame and activation point, where it is drawn; laid out again when the
                  window's safe area or the vertical geometry inside its cell changes, even if the tilt's size does not;
                  checked by harness/player/ `cover`), and the gaps from the artist to the bar, the bar
                  to play's middle and play's middle to the footer's middle are taken to 38, 91 and 91 pt (plus 48 pt for
                  the volume row, which stands that far over the footer's middle); where the room is shorter Spotify's
                  gaps stay and the earlier shared-move layout applies. A spacing change moves Spotify's views only on
                  the player's next layout, so the player is laid out once more on the next turn of the run loop and the
                  volume row placed against the controls there. When the bottom-pinned stack grows around a floating unit,
                  the non-arranged volume row keeps its distance from the bottom, not from the stack's old top.
                  To record an intermittent narrow cover, leave the player open and enter the app switcher while it
                  is wrong, then return and share diagnostics without restarting: `redesign player geometry:` and
                  `redesign player rows:` record frames in player coordinates, without track or lyric text.
                  In landscape and the two columns the volume row keeps
                  the halfway place between play and the footer. The title is 20 pt semibold over the artist 20 pt
                  regular in the secondary color (Title 3, capped at XXXL), 17 over 17 beside the lyrics' thumbnail
                  (PlayerTitle.x), in the app's chosen font (Spotify's own family when Spotify Mix is chosen), Spotify's
                  labels and marquees keeping their text, simplification and translation. The title and artist reach
                  the ⋯ (the star with Star add button on, below), the add button's and X's slots (put away by PlayerMenu.m) given to them by a custom spacing after
                  the track info's arranged view, so the marquee scrolls or ends there; slid beside the lyrics' thumbnail
                  (toward the ⋯, mirrored right to left, PlayerLyrics.x) the same spacing narrows it by the slide and
                  12 pt -- the row's trailing layout margin where nothing is arranged after the title (no add button,
                  the ⋯ then in the row's end) -- so the title, its mark and the artist end short of the ⋯, of
                  Spotify's next button or of the row's end rather than under them. Spotify's explicit marks
                  (Components.UI.ExplicitIcon, a square "19" in Korea, and Components.UI.19andOverIcon, a circled "19",
                  each in a holder of the badge stack leading the artist) are kept hidden, the artist then starting under
                  the title, and one mark trails the title as the Music app's: the symbol for Spotify's mark in the
                  secondary color, 1.1 times the title's cap height, centered on it, half its size after the last letter
                  and, for a title too long for the row, after the marquee, which then ends that much sooner. It carries
                  the shown mark's accessibility and id, so VoiceOver still reads the track as explicit and Hide explicit
                  badge clears it (harness/player/title-style-check.sh). A button of Spotify's arranged after the title
                  (an episode's skip ad pill, the AI DJ's) stays beside it, the title and its mark ending Spotify's
                  spacing short of it; where the add button's slot is gone (an episode's row while the pill is up) the ⋯
                  stands in the row's end and the row's arranged views end before it, by its trailing layout margin, so
                  the title, the pill and the ⋯ sit side by side and the row takes its shape back as the pill goes
                  (issue #28). A podcast's speed button (Spotify's value and "×", turned to two lines by Spotify for a
                  long value such as 1.25, and past the row's edge for a Korean "1배속×") is kept on one line, scaled
                  down about its middle only where it would not fit the 48 pt button, so every word is where the
                  button takes its tap and VoiceOver frames it, short of the 15 s skip (PlayerSpeedLabel.m,
                  harness/player/speed-label-check.sh). Whether the ⋯ stands in the add button's slot is read from
                  the slot (shown or hidden by Spotify) rather than from where the ⋯ was drawn, so the pass in which
                  Spotify takes the pill away and brings the slot back already ends the title before it. Where
                  the footer has no queue button of Spotify's (a Free account's row), the Music app's queue glyph stands
                  in the trailing slot and opens Playing Next; Spotify's own is kept where it has one. Queue (the
                  Player page's Controls, spotifyglass.redesign.player.queueStyle: 0 Spotify, the default, 1 Apple Music)
                  is read at launch. In two columns both choices select the existing side list; ⋯ → Playing Next always
                  opens the original sheet. In one column Apple Music replaces Spotify's queue button too: it opens the queue in the player
                  (PlayerLyrics.x's page with PlayerQueue.m's SGRPlayerQueuePage in its stage, the cover a thumbnail as for
                  the lyrics): shuffle, repeat, sleep timer (in the Music app's Autoplay slot: Spotify's player.autoplay has
                  no Objective-C setter) and AutoMix toggles 16 pt under the thumbnail, then History, Playing Next,
                  Continue Playing and Autoplay sections, 48 pt covers with 4 pt corners. A song's grip moves it within its
                  section the way Spotify's queue screen does (copy of the reported queue, setNextTracks:, setQueue:options:
                  with SPTCommandOptions.overrideRestrictions, read from 9.2.0's binary). A newer report during a drag
                  cancels the move; the list shows Spotify's order after the drop. As in the Music app, the thumbnail,
                  the title row and the toggles ride with the list (the page's stage starts at the thumbnail, its first
                  section the room they stand in, SGRPlayerQueuePageConfigure): pulled down, History shows above them, with
                  Clear (asks before hiding the displayed history on this page only); pushed up, they leave and the songs to come
                  take the room. A History row plays its song again (skipToPreviousTrackWithOptions:track: with
                  SPTSkipPrevOptions.overrideRestrictions), leaving Spotify in charge of what comes next. Skipped and cleared
                  rows are hidden by a bounded set of track keys owned by this Music page, never the side list or sheet. Shuffle and
                  repeat dim (UIKit's disabled 0.3) while SPTPlayerState.restrictions disallow toggling them. The footer's lyrics and queue
                  glyphs, while their page shows, sit on a 38 pt disc with the glyph cut out of it (markActive, as the Music
                  app's player does), white landing where 0.46 added would. The
                  timestamps under the slider are metered (SGRMonospacedDigits) and set in the Music app's type (SGRTimeLabelStyle:
                  the system font, semibold, 12 pt (Caption 1) at the default text size, 0.265 white added to the backdrop
                  (plain white at 0.7 alpha with Increase Contrast; see Backdrop ink), a minus sign before the time left) and, with Rolling time digits on (the
                  Player page, on until switched off), their changed characters roll into place (SGRRefinements.h,
                  described under Redesigned/Kit/), checked on the Mac by harness/player-refinements/. Star add button (off until switched on, also the
                  Player page) keeps the player's add button on the title row, which the ⋯ otherwise stands in for, and
                  draws it as a star — outlined in the primary color until the song is saved, filled in the accent once
                  it is — its tap, selected state and accessibility Spotify's; the ⋯ then stands in the row's end after
                  it, the row's arranged views held in before it as for a row without the add button, the title and
                  its mark ending at the star (12 pt short of it beside the lyrics' thumbnail), and the ⋯ menu leaves
                  out its add item (issue #44; harness/player/title-style-check.sh, harness/system-menu `star`). In
                  the player it wins over Saved mark, which
                  keeps every other add button; a disabled player button goes back to Spotify's own glyph, which shows
                  it disabled, and gets the star again once enabled (SGRPlainCheck.x, which owns the add button's glyph
                  and finds the player's by the InformationElementsUnit its button answers to). A Free account gets it too: Spotify's Reinvented Free player mode, whose units none of
                  the hooks reach, declines while the redesign runs, so the track falls to Spotify's other Free mode,
                  built from the units the redesign styles (PlayerFree.x, read from the binary, not yet seen on a Free
                  account). Header glass (spotifyglass.redesign.player.headerGlass, on until switched off) keeps the glass circles
                  behind the AI DJ's header down arrow and ⋯ (PlayerHeader.x; the ordinary player's has only the grabber); off, only
                  the circles go, and the buttons draw as Spotify's own with their actions, touches and accessibility, the
                  grabber staying. Where it plays from is off by default (the underlying hideContext preference defaults to on).
                  Turning it on restores the header's artist, album or playlist and its VoiceOver announcement live,
                  without moving the close or ⋯ buttons (PlayerHeader.x). Redesigned only:
                  Native keeps its own header hooks. Playing Next in the ⋯ menu (PlayerQueue.m) reads Spotify's whole queue:
                  up to ten recently played songs, oldest first, as read-only History above Now Playing,
                  then fifty Up Next songs with the existing skip-ahead action. Empty History is omitted. Each row
                  shows the cover its track's metadata names, 44 pt with the thumbnail corner, or a faint square
                  until it lands. Rows share a single pending fetch per track (SGRPlayerTrackCover) and keep a
                  successful image. Leaving the list or closing Playing Next cancels pending covers; a row shown
                  again retries a cancelled or failed fetch. The Up Next
                  heading and the blend under it are a header of the table's own kind, so they share the margins of
                  History and Now Playing.
                  The list follows Spotify's queue reports, falling back to the state's shorter lists when
                  the whole-queue API is unavailable. No swipe deletion, Edit/reorder or History replay ships:
                  the forks use the same setQueue:/nextTracks mutation and direct skip-back APIs that did
                  not take effect in the tested Spotify 9.1.90 Free context, including with Spoof Premium.
                  Their reinsert-and-skip and repeated-skip fallbacks are not used. Native keeps Spotify's own queue; there is no Native copy
                  of this sheet. Music app icons (spotifyglass.redesign.player.musicIcons, on until switched off) keeps
                  the Music app's lyrics, AirPlay and queue glyphs over Spotify's in the footer and the AI DJ's footer
                  (PlayerFooter.x, DJPlayer.x), and draws the DJ button as a waveform over its masked disc; off, Spotify's
                  glyphs come back in the colors and state Spotify gives them (Encore's microphone on Lyrics and queue on the
                  DJ's Queue, as 9.1.90 has no lyrics glyph) and the blue disc shows again. The hidden share button and its
                  holder take no touches in either state. The footer row sits lower than Spotify puts it, just over the
                  home indicator (issue #54), and where it hangs out of its bottom stack a band of the redesign's hands the
                  touches there to the row (PlayerFooter.x SGRPlayerLowerRow). Spotify 9.2.0 holds a podcast episode's player
                  and a track's in units of their own and, on each switch, puts its views back over the band, a plain view
                  under the stack among them; so on every pass of the row its band is lifted back over the stack, the band
                  of a row that has left the player goes, and a row that does not hang out has none: one band for a track,
                  none for an episode, after any order of switching (harness/player/ `look`). The open player follows both at once (SGRPlayerLookChanged lays the watched unit views out
                  again). Landscape player (Player › Controls, off, iPhone only) turns the open player sideways with its
                  lyrics closed, as the layout for a track without lines (cover, title and controls), in the scene of the
                  player on screen, never while the player is closed, opening or closing; a player opened sideways turns
                  once it has opened, and Landscape lyrics still decides for open lyrics (PlayerLandscape.x). Share Song Card
                  in the ⋯ menu shares a 1080×1350 image of the cover, large and rounded over itself blurred, with the title
                  and artist, drawn on the phone off the main thread (ShareCards.m). Animated artwork (PlayerMotion.x)
                  plays a square clip (Apple Music's square animated cover, no taller than 1.05:1) inside the cover
                  itself, a subview of the cover on screen that takes its corners, paused shrink and swipe, over the
                  field as it is; any taller clip
                  runs edge to edge from the top over the colors of its last rows drawn on down (four means across the
                  width, blended from side to side by a gradient, so the foot keeps the clip's left and right without
                  the columns a row's own pixels made, issues #39 and #40), with a blur coming in
                  from the seam under the controls and over the whole clip behind the lyrics. The clip and the cover
                  cross over as one comes and the other goes, the clip from its poster frame before the video has
                  decoded one, and the Fluid field under a clip holds still and, once the clip has faded in, is hidden
                  (SGRArtworkField's covered); the menu switches between Animated, Fluid and the Visualizer without
                  a restart. The clip holds its frame while the song is paused, goes while
                  Spotify's music video shows, is given up when it has drawn nothing in 5 s on screen, is played again from its local file when its item or
                  its looper fails after it has drawn a frame (3 rebuilds at most, only while it may play, then it is given
                  up like one that never drew and the cover or the Fluid field comes back; a clip standing in for the last
                  track is never rebuilt, and no timer polls its clock), and on a skip
                  stays a moment for the next track's to cross over it. With Reduce Motion, Low Power Mode or a Serious
                  or Critical thermal state, the player clears the clip and shows the cover over the still field.
                  Once those holds clear, the moving field continues from where it stopped; the player looks up the clip
                  again and plays it from the beginning. The Colors field (Kit/SGRFlow.m) is moved 15 times a second
                  by a timer that stops under the landscape window or a hidden player and resumes at the same phase.
                  It is drawn at half a pixel to a point, then stretched to the screen: played by the render
                  server at full resolution it was drawn again on every frame, 21% of an iPhone 13 Pro's GPU under the
                  player against 9% so (1.4% held still, 6.5% for Spotify's own player). A black gradient dims the clip by its brightness (the 75th
                  percentile of the linear luminance of three frames), so white text keeps 4.5:1 (7:1 with Increase
                  Contrast), from 0.10 to 0.80, only where text is: a band at the top and from above the title
                  down; behind the lyrics it covers the whole clip, 0.15 darker (issue #101). The band is darkest at the very
                  top and has no edge: the dim is 0.9 of itself at the very top and 0.49 where the band ends (over the status bar, and over the
                  header, to 14% of the screen, only while the header shows where it plays from, Spotify's arrow or the
                  AI DJ's buttons) and fades out from there over 108 points (issue #39). The lower half is untouched down
                  to 23% of the screen, then both the dim and a second black over it (0.40 at the foot) grow along x^1.75
                  to the bottom of the screen, measured on the Music app's player (0.63 in all over a white cover), so the
                  lower part darkens as the Music app's does, with no knee at the title. A clip that is black or nearly so
                  (the 75th percentile of its linear luminance up to 0.04, fading out by 0.12; a dark blue or pink cover, 0.15 to 0.25, ends in its own color) ends in the Music app's gray
                  rather than in black: a white layer over the clip (kLiftFoot 0.066 at the foot, 17 of 255 over black)
                  rises from 27% of the screen along x^1.5, as measured on the Music app's player over a black cover, and
                  is gone behind the lyrics. Under a cover shorter than the screen (the tall 3:4 one) the area below it is
                  not the poster's last rows stretched down, which stood as a vertical streak, but a small picture the layer
                  stretches smoothly (PlayerMotion.x veilImage): the foot's colors smoothed along the width, more the further
                  down (0 to 120 pt below the cover's bottom edge, the edge's own columns first, then the brightness-weighted
                  mean), and darkened by up to 0.49 of black under a dark cover and by none under a light one (the dim and the
                  deepening already darken a light cover to the Music app's 0.63; the veil's black on top of them took a white
                  cover to 0.75), as fitted to the Music app's player; the clip dissolves into it over its last 3.5%, so a
                  cover's own dark middle stays dark to its edge as the Music app's does. A Canvas, which fills the screen, has none.
                  The foot is not the poster's: while the clip plays, its current frame is read 15 times a second
                  (AVPlayerItemVideoOutput, on the item the player has) for the colors of its last rows, and the foot and
                  the veil close 0.35 of the way to them each time, so the lower part's color and brightness move with the
                  clip as the Music app's do; a paused or stood-down clip leaves them where they were.
                  A track that changes
                  while the player cannot be seen (no window, or the app not in front) takes the last clip away at
                  once. Checked in the simulator against harness/player/ (`motion`). The Visualizer
                  (PlayerVisualiser.m) draws two soft hills of the song's spectrum across the foot of the player, the kick
                  a mound in the middle (the two bands under 80 Hz are left out, and the kick's bands stand at least as
                  tall as the bands beside them, so the middle is never a notch), as light in the cover's flow colors
                  added to the Fluid field held still (plusL, every color at one luminance with its saturation lifted, so
                  a red cover glows warm and a black one is a gray mist, never a silhouette), clear toward the tallest crest so a peak
                  thins out instead of ending in an edge, the front hill brightening on the kick, blurred behind the
                  lyrics: the audio effects'
                  render notify on the music's output hands what it plays, mixed to mono, to one reader (SGAudioSetOutputReader), and
                  SGRSpectrum.m cuts it into 24 bands with Accelerate's FFT on the render thread, without allocating or
                  locking, and publishes them atomically; a display link asking for the rate it draws at, 60 Hz (Bars
                  and Halo 120 on a ProMotion screen), 30 behind the lyrics and 15 with Reduce Motion (where the bands
                  ease over seconds), its range reaching up to the screen's rate and the ticks between draws skipped
                  when something else runs the screen faster, draws them while the player is on screen,
                  Spotify is in front, the player is not opening or closing and Low Power Mode is off, and stops once
                  a paused song's hills have settled. The spectrum is checked on the Mac against harness/visualiser/,
                  the view in the simulator against harness/player/ (`visualiser`). The line under the cover (Lyrics Line on the Player
                  page, off until switched on, as the Music app keeps nothing between its cover and title; PlayerLyricLine.x,
                  PlayerLyricFit.h). When switched on, synced lyrics replace the native preview. The player reserves
                  two sung rows and, while translations are enabled, one translation row, one grid gap above the title.
                  Both start at the title label's live leading edge and wrap within equal side margins; only a
                  missing title uses the 24 pt text inset. Moving the title does not resize the artwork.
                  The ordinary cover gets the room above the slot up to its measured phone artwork-column width.
                  Unknown or narrower layouts keep their ordinary cover geometry. The preview is masked only after
                  the replacement fits; chip measurement starts at the normal cover top, independent of the resize.
                  To keep a recognizable cover
                  at least two thirds of that width, release the translation row first, then the second sung row,
                  then the slot. Missing words or translations within a track do not resize the cover. It uses the measured
                  19.098 pt system bold preview font, fixed across phone text sizes,
                  and white text at the player's position less the Lyrics page's Delay; a tap opens the lyrics.
                  Size under Lyrics Line selects 19 pt (the preview size) or 17 pt; the translation uses 15 or 14 pt respectively.
                  A field clip or full-screen still keeps the same text rectangle, with the clip's dim behind it.
                  A visible chip lifts the rows only enough to leave one grid gap above it. If that would
                  crowd the cover, it tries the sung line alone before hiding it. The same lift over a clip
                  or full-screen still carries the dim with it. The line observes changes to the floating unit
                  as well as player layout, so a late switch, move or fade is followed even while paused. The video
                  switch is measured from the outer pill, not its inset text. The search reaches the title:
                  on Spotify 9.2.0 the floating unit is inside the bottom stack. If Spotify retains a nonempty
                  strip above the title after the button is removed, it still explains a smaller centered
                  native square. The natural side is the column width; the top stays at the native lifted,
                  header-safe edge. When Lyrics Line reserves no artwork space and the video switch is hidden, an allocated but empty unit
                  costs the artwork no width: the picture fills the normal column without moving the stack,
                  unless Spotify's own lyric preview is showing beside that tilt. Showing the switch or
                  another visible element keeps Spotify's square; changes in the floating unit, including
                  fades and reinsertions, update the cover without a player layout or lyric clock. With the line on,
                  only visible chip content requires clearance. An empty strip leaves
                  the line directly above the title, with the same row budget and cover floor.
                  The identified switch need not expose painted pixels; anonymous views still do. In driver builds a changed
                  floating-unit snapshot logs `lyrics unit:` even when nothing wins. The numbered parts
                  show the title top, stack frame, reserved natural side (zero if none), search area,
                  chosen top and view (`*`), and a bounded view/layer tree with default attributes omitted, never
                  identifiers other than the switch classification, label text or image data. Changes to the
                  observed floating-unit layers trigger a check between layouts. A shape mask reports its path bounds in player
                  coordinates; a path outside the pill cannot lift the rows. Translation alone is recorded
                  once it settles. During playback snapshots are at least one second apart and use at most four
                  unified-log entries each (at most 240 per minute; oversized trees are marked `[capped]`).
                  Leaving the player or app flushes a pending snapshot immediately, outside that rate limit. For a report,
                  show the problem, then use Mod Settings → Mod → Share diagnostics without restarting.
                  The file includes the newest 1,500 matching system-log entries available from this launch,
                  not a guaranteed number of minutes.
                  A track without synced lyrics keeps Spotify's own lyric preview under the cover,
                  which in 9.1.90 is Lyrics_NPVElementsKitImpl.LyricsElementWrapperView beside the tilt view, hooked apart
                  from the other placements because that preview gets its height when its lyrics arrive, after the cover's
                  last pass. Long lines use successive two-row portions at the chosen size (only a word too wide
                  for one row shrinks, no further than 0.85) — cut at word boundaries where the
                  text spaces them, and character by character through an unspaced Chinese or Japanese run — the portion
                  holding the word being sung while the line is word timed, else the even share of the line's time; no
                  portion is ever cut mid-word. Portions are kept per line, width and font (the font whole, so Bold Text
                  or a text-size change measures again), the newest 32. It reads the line on a one-shot timer armed
                  again from every update at the next thing that can change what it draws — the next portion, the next
                  line's start, or any later line's sung end — never nearer than 20 ms and never aimed further than
                  0.5 s (with 0.1 s tolerance for a distant boundary because speed can change between reports; no timer
                  while paused, hidden (including under the expanded Queue sheet), without synced lines, or after the final portion is drawn),
                  with song time turned to wall time by the playback rate; no display link, which at 60 Hz would drag the
                  player's 120 Hz transitions down. A player report re-aims it when the rate changed (a pause or a
                  resume), and, paused, on any move of the place, else only when the position is more than 500 ms off
                  where the armed timer was heading; kept lines, the Delay and coming back to the foreground re-aim it
                  too. While the lyrics' menu shows translations (SGRKeyLyricsTranslation; no switch of its own), the line's
                  translation (SGLyricsShownTranslation: none, or one that reads the same as the line, adds nothing) sits
                  under it at 80% of the line's chosen size, rounded, in the player's artist color
                  with the lyrics page's translation weight and brightness (Text
                  sizes), on one row that shrinks to 0.85 and then truncates. It goes under the line only where the room
                  holds the pair at the native text position with half a grid gap clear of the art and title.
                  If the pair does not fit, the translation is left
                  out and the line keeps exactly its place without one, the line never shrinking for it. The
                  translations are the lyrics page's, on the same kept lines it translates in place, plus the saved
                  ones read onto them from disk (SGLyricsLoadTranslation, as the Live Activity restores them); the line
                  never asks a translator. A save (SGLyricsTranslationSavedNotification), a removal or job change
                  (SGRTranslationNotification, SGLyricsTranslationsDidChangeNotification) or the menu's switch
                  (SGRLyricsTextDidChangeNotification) shows at once: the translation fades in or out and the pair
                  settles with a layout spring, at once under Reduce Motion. While translations are shown, in a
                  player taller than wide, for a track the line has synced lines of its own for, the line takes the
                  place of Spotify's preview rather than standing down (SGRPlayerLineTakesPreview, PlayerLyricLine.h):
                  every preview in the covers is hidden by an empty CALayer as its layer.mask (Spotify's own mask, if
                  any, kept to put back) and kept from VoiceOver, again on each pass of the preview's, the cover's and
                  the player's and on every update of the line's; Spotify's alpha and touches are never touched. The
                  room is measured as if no preview were there. Each hidden preview is held in a weak table, so
                  translations switched off, the player turned wide or a track without synced lines give back every
                  one (SGRPlayerPreviewsToGiveBack), a cell the covers keep for reuse included: only the line's mask
                  comes off, if it is still the preview's. The line then stands down for it as before; the switch
                  and lines arriving hand over at once. Only the touch target over the words opens the lyrics.
                  Checked on the Mac against harness/player-lyric-line/
    Lyrics/       the full screen lyrics page on glass with Apple Music style lyrics over it, always on (SGRKaraokeView,
                  which the player shows in itself too, Player/PlayerLyrics.x, where with Hide the controls set to
                  Everything, everything else -- the header row, the thumbnail, the title row and the controls --
                  fades 4 s after the last touch while the song plays (5 s when it starts again with Sing on) and the lines take
                  the whole safe area, as the Music app does it:
                  a tap under the lines' place, where the controls were, brings it all back; a scroll decides as the
                  finger lifts, a flick on toward the lines to come sending the controls away at once (playing or not) and a
                  flick back bringing them back, a scroll that stops dead changing nothing, and after a flick on a tap brings
                  nothing back until timed lines follow the song again. On untimed text a tap brings the controls back
                  without moving the text. A tap on a timed line seeks there, flashing the Music app's
                  plate behind it, white at 8 % with 16 pt corners, the line's own box grown 16 pt, and changes nothing
                  else (in a song for two voices every line is set in 85 % of the width against its voice's side,
                  so the plate stops short of the far edge as the Music app's does; the Lyrics settings preview alternates voices
                  and uses the same blur on lines adjacent to the sung line); set
                  to Keep the title, as the Music app's: only the controls under the title row, the lyrics' own button
                  and the mic fade (the mic, under either choice, stays with Keep the mic,
                  spotifyglass.redesign.lyrics.keepMic, on by default, or while Sing is on), the thumbnail, the title row and its ⋯ rise 22 pt with
                  the title 12 pt from the cover, and the lines start 16 pt under them and grow down the safe area, the sung line resting 238 pt down the player
                  as the Music app's): line views only for the lines in and near sight, built nearest
                  the middle first, at most four a pass and none after the first once the pass has spent 1 ms, the
                  next pass picking up the rest (a work budget; the display link is never slowed); lines sung over each other lit together, the stack moving on
                  once the first is sung out. Both pages render through a landscape fade. Portrait rests once the
                  landscape window is opaque; landscape retires its link, fallback poll and boundary wake after fading out.
                  A held interactive dismissal keeps
                  the hidden page and its browse position, not its clocks; cancel paints from song time before reveal.
                  An instrumental break of 7 s or more is held by three dots
                  that breathe and fill over its length on a Core Animation timeline laid against the song's clock; and
                  a line's pronunciation (under the words it spells) and translation, switched on from a glass button in
                  the lyrics' corner (its translate glyph an ellipsis for a song with neither), whose menu also has Sync
                  and Search LRCLIB (LyricsTools.m: the song's and the output's offsets in steps of 10 and 100 ms, and
                  LRCLIB searched by title and artist, the pick pinned to the song; the player's ⋯ menu has Search Lyrics
                  too, for a song with no lines to open the lyrics on; Reload Lyrics; the song's language, picked by hand
                  or left automatic, with Keep for its songs, which keeps the translation and pronunciation switches as
                  they are for every song in it, SongLanguage.m; and Write Pronunciation and Explain References, which ask
                  the AI service picked from a submenu and keep its answer for the song), in the order of sizes the Lyrics page sets
                  (LyricsText.h). With the Lyrics page's Pronunciation on, a line in another alphabet has its reading in
                  the pronunciation's own place in that order, at its size and look, so the corner menu omits its
                  Show/Hide Pronunciation action while that setting is on: the source's own pronunciation where
                  the line has one, else one generated in the alphabet chosen (Latin letters, or Hangul with that picked) as
                  timed words (SGLyricsPrepareExtras, Shared/Lyrics), each anchored by its source range to the lyric word it
                  spells, so it sits under that word, takes its clock and is swept with the line, even where every clock
                  is zero; a provider's pronunciation, which has no source ranges, keeps its alignment by timestamps.
                  Furigana sit in room the row makes above its words, centered on the kanji they read, and light with the
                  line; a cultural note goes last under its line, smaller and dimmer than a translation. Name the
                  breaks (SGRKeyLyricsBreakLabels, off) sets Intro, Interlude or Outro beside the dots, in their group
                  so it breathes and fades with them. Simplify song titles and Translate song titles change what the
                  player's own title and artist labels draw (Player/PlayerTitle.x, which gives those two labels a
                  subclass of their own class), the landscape lyrics' title, and the title and matching artist on each
                  now playing bar page, never Spotify's text underneath. The player and bar refresh when either
                  switch changes, even if both were off at launch, and when a translation arrives. A landscape
                  refresh leaves controls and idle timers alone.
                  Keep screen on (SGRKeyLyricsKeepAwake, off) holds the idle timer off while lines show and the song moves,
                  and lets it go 5 s into a pause, when the view leaves its window or the app leaves the front.
                  A word held 0.9 s or more glows and its letters rise in a wave as the sweep reaches
                  them. Pressing and holding a line opens the system edit menu on it (UIEditMenuInteraction, anchored
                  on the line, its Copy and Share and, first, Meaning where Genius has already explained that line):
                  Copy puts the line's own words on the pasteboard alone, Share offers the line, then "— title · artist"
                  and, for a streamed track whose lyrics are the one playing, its open.spotify.com link, never a
                  timestamp; Meaning opens the same sheet a tap on a meaning-marked line does. That sheet (MeaningSheet.m)
                  offers Translate only while a translator the user set up takes the Lyrics page's translation language
                  (SGLyricsTranslateTextsAvailable); a tap sends the annotation and the line it quotes, as two strings, to
                  the first service available in Translate song titles' order (the iPhone, Bing, Google, DeepL, Gemini,
                  Claude, then the OpenAI-compatible one; TextTranslation.m over the services' *TranslateTexts entries),
                  once for each annotation and language, a second tap while it runs doing nothing. The answer is refused
                  unless both strings come back (2,000 strings of 64,000 characters at most, 128,000 together, 256,000
                  back), is saved nowhere and is never a lyric translation: the sheet says Translated under it, offers Show
                  Original, and keeps the newest 24 until it is dismissed; a refusal says Couldn't translate and leaves
                  the action for another try. A line with no letter
                  or digit in it (an empty one, an instrumental break), a touch on the page's own controls (the
                  extras, the auto-translation note, the Sing button) and any preview get no menu, and the menu
                  follows its line: it is let go with its own
                  dismissal or when that line's view goes, and a press that offers nothing takes the last one away.
                  Nothing there asks a source for anything, a light tap confirms the press where Vibrations' Controls
                  are on, and VoiceOver
                  gets the same as custom actions (Meaning, Copy line, Share line, Share as card). Share as Card opens a sheet
                  of the song's lines with the held one picked; up to six can be picked, and Show Pronunciation (where a
                  line has one: the source's, else the Lyrics page's romanization) puts each line's reading under it; the
                  card draws them over the blurred cover with the small cover, title and artist on top, off the main thread
                  (LyricCardPicker.m, ShareCards.m), and nothing is fetched. The items, what Copy and
                  Share say (SGRLyricsShareText), the anchor and the dismissals are checked in the simulator against
                  harness/lyrics-hold/, the press itself on the phone. Every line but the sung one is blurred as the Music app's are (one more than its distance ahead, two more behind,
                  up to 4, times the look's Blur). The size, the room between lines, the blur, the glow and the wave are the Lyrics page's look
                  (LyricsLook.h): five presets (Apple Music, the default, at the Music app's 34 pt bold; a stored look keeps
                  its values) and a sheet of sliders, applied at once to every view, the lines 32 pt in from the sides as
                  the player's title and bar are (SGRKaraokeView.m), under a live
                  preview of the view playing a song of its own (LyricsLookSettings.m); its Size in each place sets the
                  player's lyrics and landscape/full-screen lyrics to 75–130% of their own size,
                  Default changing nothing. Laid out on the Mac against
                  harness/lyrics/; the page against harness/lyrics-page/
    Navigation/   Open pages from their artwork, an opt-in on Appearance beside the page-title options
                  (`spotifyglass.redesign.pageZoom`, off, restart to apply, iOS 26 only; PageZoom.x/m).
                  A passive touch observer and control actions remember the artwork of the selected card or cell;
                  SPNavigationController's push flags only album and playlist URIs. The hosting page's URI is available
                  before the push, when spt_pageURI is still nil. The source holds views weakly and rejects artwork that
                  leaves its window, is clipped offscreen, changes image or belongs to a reused cell.
                  UIKit's preferred zoom was tested first: its morph/portal hierarchy targets Spotify's LayoutOnlyView,
                  whose LayoutOnlyLayer inherits CATransformLayer and ignores masks. The portal hides its source but
                  the full-size page's descendants remain visible behind the shrinking portal. A diagnostic CALayer
                  substitution removed that duplicate, but changing Spotify's view's backing layer is not shipped.
                  The black push is separately Spotify's empty LoadableTemplateViewController before its album loads;
                  changing the layer does not make the content ready.
                  The scoped replacement forwards Spotify's navigation delegate through a weak-target proxy. Only a
                  flagged push/pop receives a 0.4-second spring animator; every other delegate selector and unrelated
                  transition goes to Spotify. Delegate reassignment updates that forwarding target. The animator moves
                  the actual page into a temporary CALayer-backed carrier, not a replacement controller or root view,
                  and grows/shrinks it at the artwork frame while dimming the source page slightly. Tab bar and mini
                  player remain outside the carrier. A push retains the source image view's full-resolution UIImage,
                  not a bounds-sized rendered snapshot. It stays square and top-aligned, tracking the carrier's width,
                  with black below it; its corner radius animates from the source's to zero. The destination stays transparent
                  underneath, laid out at its final size rather than repeatedly resized with the image. An uncapped
                  display link inspects readiness at most every 50 ms, only on that destination, for laid-out collection cells or the album's
                  LegacyUI_ECMCoreKit HeaderView with non-empty bounds. On that signal, or after a 0.6-second cap,
                  the page fades in and the image fades out over 0.2 seconds. The spring still takes 0.4 seconds;
                  transition completion waits for both it and the reveal. The display link is invalidated when the
                  reveal begins and in completion, and the original page alpha and autoresizing mask are restored.
                  Incoming navigation platters are matched by their bar items (including the previous item's Back),
                  never by hiding the shared navigation bar. Their glass and controls reveal with the page; original
                  alpha is restored on completion or cancellation. Source and unrelated chrome are left alone.
                  Missing/reused artwork and Reduce Motion use a cross-fade.
                  Interactive pops return nil for UIKit's slide; no interaction controller, recognizer or page cache is
                  added. `python3 harness/page-zoom/check.py` checks on/off, delegate forwarding/reassignment,
                  interactive-pop selection, an uncapped readiness link, destination-chrome alpha and cancellation
                  restoration, a CATransformLayer page, the source-image push, content/deadline reveal,
                  source geometry, removal and cell reuse.
                  Real Spotify 9.1.90 confirms the pop duplicate is gone, the source remains behind the growing page,
                  Reduce Motion cross-fades, and the Home tab returns to root. Cold and warm Home-to-album captures
                  confirm the cover grows through loading and fades into the destination without the empty growing page.
                  Edge-swipe acceptance remains open: the simulator input attempts did not start a pop with either
                  setting, despite the recognizer being enabled; the harness's interactive branch is not a real gesture
                  pass; real-device edge-swipe verification is pending. Search, Library, artist rows, VoiceOver and older
                  Spotify versions await visual acceptance.
    Home/         Home decluttered to music on black (an allow list of its sections: shortcuts, the DJ without its heading and its
                  Beta badge, what it says kept, the shelves of cards, each with a switch on the Home page of Mod Settings; the previews and the
                  song suggestions only when switched on), a large title where the filter pills were, the title rising and
                  fading with the feed as it scrolls, as the Music app's does (or, with Title stays on scroll, staying put
                  over the feed's hard top edge, shaped to the row, and no scroll observer), the shelves' headings at the
                  Music app's size (Title 3 bold, capped at Large) with a chevron after the title where Spotify offers
                  "Show all", which goes: a tap anywhere on the heading fires Spotify's concealed "Show all", so it
                  opens the same page, and VoiceOver keeps it as the heading's action (HomeHeadings.x),
                  continuous corners on the covers, and, under the Home look switch (the Home page's first row; off, none of
                  its hooks install and Home is as before it): at the trailing edge a glass pill of the filter (a menu that
                  drives Spotify's own chips, with the device picker and the top shelf's Show all; with Podcasts and audiobooks
                  hidden on the Home page, `spotifyglass.redesign.home.hidePodcasts`, shown unless set, it leaves out the
                  Podcasts and Audiobooks chips and takes Home back to the default chip once when one was chosen, at once
                  when flipped; harness/home-podcasts/) and the avatar, 6 pt apart and kept so through an iPad's turns and
                  window resizes (the page's pass lays the header out before reading it; harness/home-header/), on a Friday (the device's calendar, read as the
                  header lays out) a thin ring of pinks and purples turning round that pill (a turn in 6 s at no more than
                  30 frames a second, still under Reduce Motion, going and coming back with the pill as the title row
                  scrolls and still while gone), and Top picks
                  (the first shelf, or the one Cards from names, found in Spotify's feed model before its cells are
                  built, moved above the shortcuts and drawn as large cards in their covers' colors with no heading
                  unless Show Top picks heading is on, the page tinted by the first card, laid out in the page view's own
                  pass (the feed's controller's), so from launch even when the feed comes after the header's last pass,
                  and across the page's whole width through an iPad's turns and window resizes; harness/home-header/);
                  under Glass shortcuts (the
                  row after Home look, `spotifyglass.redesign.home.shortcutGlass`, read at launch; unset, it is what the
                  Home look is, so turning the look off before it existed still means plain shortcuts) each shortcut tile as
                  a glass pill in its cover's color, 72% opaque so the page shows through, with its name in bold on up to two lines; in FLEX builds a meter
                  of each scroll's frames and the hooks' time (Home.h lists its files)
    Search/       the Browse page decluttered to its category cards (an allow list of the list's cells: the watch feed
                  carousels and promos collapse (each on a switch of the Search page, on until switched off, and back when it is off), and the cards move up by the spacing they leave, the list's end with them), the header the way Home
                  has it without the camera, and each card as Liquid Glass tinted by its own color, read off the Box's
                  shape layer, its name the redesign's own label over Spotify's transparent one, Headline semibold (17 pt,
                  capped at Large) 12 pt in from the top leading corner on up to two lines on every card, where Spotify
                  draws 16 or 14 by the name's length (SearchCards.x placeTitle; Search.h lists its files)
    Library/      Your Library the way Home and Search have their headers: a large title at the leading edge, the avatar
                  at the trailing edge with the search and create buttons before it, the header's scrim gone, each row's
                  artwork at the Kit's radius with a circular one left round, a hairline between the rows, and the search
                  inside the library on glass capsules (Library.h lists its files). The filter chips under the row stay
                  Spotify's: they were taken out when this was first built and put back in 0.21 (issue #20), since
                  sorting a library is not something the page can do without, and Spotify already draws them on the
                  system's own glass. Compact library (Mod Settings > Search & Library, redesign only,
                  spotifyglass.redesign.library.hideChips, off, read at launch; LibrarySettings.m, over a preview of Your
                  Library) takes the root page's chips away, closes the header up by what they leave, and puts a menu button
                  (LibraryMenu.m) before the trailing controls. The title and menu follow the row even when only the
                  header lays out. In Spotify 9.2.0's stack, the folded header ends at the control row. The folded
                  list inset and the full inset restored with the chips both shift by the page's safe-area change,
                  whether Spotify writes the folded height, the full height, or no inset. The menu is built as it opens, from Spotify's own controls found live on
                  the page: Sort, with the order the sort row shows, the list and grid views with the current one checked
                  (Spotify's toggle under its own name when the current one cannot be told) and Clear filter while a filter
                  is on. Each fires Spotify's control, in place while it is on screen, else once the list has been taken to
                  its top and brought it back. Where the menu cannot stand in (the chips not found, the sort or view control
                  not yet seen, a filter on with no clear chip, or a fired control that failed) the chips come back, and a
                  folder keeps its chips
    Playlist/     the playlist page (Liked Songs and one's own too, all three being the same page) the way the Music
                  app lays one out. Cover beside the title (`spotifyglass.redesign.pages.coverBeside`, on by default,
                  live; the shared row in Albums and Playlists) places a square cover on the leading side in a
                  regular-width iPad window, with the title, creator, metadata and existing action capsules
                  leading-aligned 28pt after the cover and vertically centred on it. The description wraps below the
                  action row; buttons keep their stacked-header sizes, and a row that cannot fit falls back rather
                  than shrinking them. The cover is 40% of the available width, up to 320pt. Both columns mirror
                  in RTL, and VoiceOver visits cover, title, details, then actions. Text grows with Dynamic Type;
                  insufficient room falls back to the stacked header, as do iPhone and compact-width iPad.
                  Resizing and switching the setting relayout the existing header without reopening it. A playlist
                  without artwork keeps its existing header. Leaving beside mode in Card layout restores Spotify's
                  cover's original mask, visibility, interaction and accessibility, including on cover reuse.
                  `harness/album/beside-check.py` covers both page types.
                  Otherwise the cover is across the top, in the Full screen cover layout full bleed and dissolving into the page's
                  field with no seam (Card leaves Spotify's square above the title, shrinking as the header collapses; a mix's
                  picture stays full bleed, as Spotify lays it out),
                  the title, the creator and the length centered under it, one row of glass controls (shuffle, a
                  prominent Play capsule taking its glyph and its word from Spotify's own button, add; Play on the
                  middle of the page, and download, where a playlist has both, pinned beside ⋯), the find bar
                  and the curation pills gone, and the track rows on the field with a hairline between them
                  (Playlist.h lists its files). Playlists › Playlist details has three launch-read switches,
                  all on unless set: Creator and length, Creator picture (beside the tappable name), and Description.
                  Sort and Mix, the two of those pills the ⋯ menu does not already offer,
                  are put on that menu's own sheet instead, above Spotify's rows, and fire Spotify's own buttons.
                  The chip row 9.2.0 gives the playlists Spotify makes itself (Video, Duplicate, Sort, Select; a view
                  beside the list, not a cell) stays, since Duplicate and Select are nowhere else, but goes with the list:
                  where Spotify holds it under the navigation bar it fades over the first 24 pt of scroll past that
                  point and takes no touch, and comes back as the list brings its place back (PlaylistRows.x), so it
                  no longer stands across the rows going by under it.
                  Hide on a playlist's page → Recommended songs (`spotifyglass.redesign.playlist.hide.recommendations`,
                  off; PlaylistRows.x) collapses the recommendation heading, its tracks and Refresh below the list to
                  zero height, clipped, hidden from VoiceOver and not interactive; rows found by their recommendation
                  component, restored on reuse and when switched off. It applies when the playlist is opened again.
                  The page of the songs the user liked by one artist (CollectionArtist) is Liked Songs' header kit
                  with no cover and goes through the same files: the neutral field, the wash and the bar's scrim
                  gone, the one row of shuffle, Play and download, and its rows as the playlist's are. Its pinned ⋯
                  opens the system menu, as every other redesigned page's does. Its download button is the plain one, not the Granular one, so its state is read from its
                  owner's `currentStatus`, whose cases are its own (none, waiting, downloading, downloaded); it keeps no
                  progress while it downloads, so the ring turns (Kit/SGRDownload.m).
                  Laid out on the Mac against harness/playlist/
    Album/        the album page laid out the same way, on the page the Creative Work Platform builds rather than the
                  playlist's. The shared Cover beside the title setting uses the same regular-width iPad fit as
                  Playlists, without replacing the page controller or its source views. The existing hero carries
                  both still and animated covers in the leading square; motion eligibility and the page's colour
                  source stay unchanged. If Spotify replaces the header's artwork view, only the new view can
                  update the hero and page colour. Compact widths and an unfitting side column retain the stacked header.
                  It shares nothing with Playlist/ but the Kit: the cover, in the Full screen layout full bleed, dissolving into the
                  field (Apple Music's animated cover over it where the album has one: the header asks with the album artist
                  first. Only a fresh page with an unidentified release uses one title search, indexed off main,
                  for at most eight distinct song/credit pairs; a page, hero or track list reused for another
                  release is header-only. The pairs come from
                  this page's own settled track list, never the playing song or cells in a list update. When the two services
                  name the release differently, the page uses its own album for barcode and recording-code evidence. The cover fades in once its first frame
                  is decoded and moving only in front of the app, below Serious heat, with Reduce Motion and Low Power Mode off and Auto-Play
                  Video Previews on; a suspended cover keeps its frame, bleed, veil and colour), the title, the artist and the kind and date centered under it, and the same row of glass
                  controls, shuffle, Play and add -- play and shuffle float over the album page outside its header, so they are concealed
                  there and the row carries the Kit's stand-ins, which draw their glyph and fire them; download is
                  pinned beside ⋯ in the top corner, the two one 88x44 glass capsule that download carries, laid right
                  under ⋯ and, while the page fades in, over the field's veil, so ⋯ is never its glyph alone; right to
                  left the pair mirrors into the left corner, ⋯ outermost (Kit/SGRActionRow.m). When the shown buttons
                  do not fit beside Play's capsule, measured once with the longer of Spotify's localized Play and Pause,
                  Play becomes a 48 pt glyph-only circle; add's saved state is a 22 pt accent disc with a dark check
                  (harness/action-row/). Where the download capsule covers
                  the Card cover (a 402pt phone: the cover {77, 76, 248, 248}, the capsule {298, 62, 88, 44}), the cover is
                  drawn smaller: square, on the same vertical axis, its bottom edge kept and its top 8pt under the capsule
                  ({96, 114, 210, 210}), its shadow and the veil on its picture with it, measured with the page at rest so a
                  scroll moves it with the page (SGRAlbumHero -sgr_card in AlbumHeader.x). ⋯ alone, the Full screen cover,
                  Cover beside and the playlist are left as they were (harness/album/layout-check.py chrome-*). A track's artist line
                  goes where it only repeats the album's artist (with the guests the title names after "feat." and the
                  like), its explicit badge drawn after the title instead (AlbumCredits.m decides, checked on the Mac
                  by harness/album-credits/; a switch on the Albums page). Under the tracks
                  everything the server sends is dropped -- more by the artist, videos, concerts, merch, you might also
                  like, and whatever it adds next -- but the album's own line and its copyright, each section back
                  once its switch on the Albums page is off. Both looks recognize the English headings and four
                  Korean ones: “<artist>의 곡 더 보기”, “콘서트”, “굿즈” and “이건 어떠세요”. Unrecognized headings follow
                  Everything else in the redesign and are left alone in the native look. Album notes, from Apple Music's catalog, have a
                  place of their own on the Albums page (Under Play, Under tracks — the default — or Off; AlbumNotes.m):
                  Under Play an arranged sibling after the header in the page's own scrolling stack, Under tracks the
                  footer under the copyright cell, whose lead grows by the note's height, and Off asks for nothing. The
                  note is Apple's editorial text read as plain text, never a web view or an attributed-string importer:
                  script, style and comments go, block boundaries become paragraph breaks, the markup goes, then the
                  common entities and numeric references are decoded, so an escaped "<…" stays literal text; a document
                  over 64 KB gives nothing. Only an exact, unambiguous match is used, and only for an album whose own
                  edition is known on the page: the artist and the album's name as Spotify spells it (no edition
                  qualifier borrowed), with the track count from the page's consumption cell (read as
                  the leading number of the localized "count · duration"), the release year from the header's metadata
                  row (and only when no two labels disagree) and the explicit rating the page proves (an explicit track
                  seen, or every track loaded with none). A second record that fits equally well gives nothing, as does a
                  missing count, year or rating; the count and year change, or the page identity changing, recomputes
                  once, and the tracks are remembered by index path plus title within one collection snapshot, so a
                  reload or a batch rebuilds that evidence rather than mixing two snapshots. The short note sits under
                  the header or the tracks and a tap opens the full one in a page sheet on black (SGRPresentDark).
                  Checked on the Mac by harness/album-notes/, against replayed catalog-shaped fixtures. Play counts have a place
                  and a source of their own on the Albums page (Off, In the row — the default and what the
                  switch it replaced meant when on — or In menu), read at launch: In the row draws "Your plays: 12" or
                  "Spotify plays: 12" after the title in the locale's grouping, never 1.2K, and nothing for a track with
                  none or an unknown count; In menu leaves
                  the row alone and puts the count, as a line of information with no glyph, in the header (or, where
                  Spotify uses the header, the footer) of the sheet that track's ⋯ opens, matched to the track by the
                  row's ⋯ as it sends its action, so a finger, VoiceOver, Full Keyboard Access and Switch Control are
                  all read; a slot Spotify fills with a view of its own takes the line off that sheet for good
                  (AlbumPlaysPlace.m, AlbumPlaysMenu.x; the place and the old switch's migration, and the sheet's
                  line against Spotify's mocked sheet, are checked on the Mac by harness/ui-refinements/). A stored switch migrates: on or unset is In the row, off is
                  Off, and the key stays readable. Count source (spotifyglass.redesign.album.playCounts.source, 0 Your plays
                  unless set, 1 Spotify plays; the page's preview follows it) picks the numbers, apart from the place. Your
                  plays are Listening stats', matched by the album's and the track's names. Track numbers
                  (`spotifyglass.redesign.album.trackNumbers`, off unless set, read at launch) uses the
                  position in each disc's metadata track array. A loaded row's menu supplies the track URI;
                  only a row without one can match an exact, unique title. Missing metadata leaves no number.
                  Spotify plays
                  (AlbumSpotifyCounts.m, AlbumRows.x, over Shared/SpotifyMetadata/) are what Spotify's own metadata gives for
                  the album: one JSON GET for its track URIs (the metadata/4/album path, market from_token) and one batched
                  extended-metadata POST for all their play counts (extension 185), per miss, never one request per track and
                  never retried on its own. The page's identity, the album URI and not its title, owns the answer, so a new
                  page drops an old reply, and requests for one album are coalesced. At most 500 tracks an album, 16 albums
                  and 16 waiters for one pending, 64 albums and 2 MiB kept on disk; a count is kept 24 hours and a failure
                  five minutes, and the reply is read on a private serial queue within a budget of 16 fields a message and a
                  depth of 5. It needs Spotify's own spclient headers, so nothing is asked before Spotify has made a request
                  of its own, and an unknown count shows nothing, never 0. In menu serves either source, the track found by the
                  URI in the ⋯'s identifier for Spotify plays. A loaded 9.1.90 row has no Granular.Title or Granular.Subtitle:
                  the count and the ⋯'s mark read its RetrievalRowKit TitleView and SubtitleView, and the artist line's change,
                  which needs the Granular wrapper the explicit badge sits beside, leaves such a row alone. A podcast's episode page is the same template, so it is given the same field, and what it
                  paints over it is taken off. Laid out on the Mac against harness/album/
    Artist/       Hold Play on the redesigned artist header, or use its Shuffle accessibility action, to play
                  the displayed artist shuffled. A hold released outside the button does not act. The header's
                  own Shuffle and Play controls supply the state and actions; an artist already playing is not
                  paused. A normal tap stays Spotify's. See harness/artist/README.md for simulator coverage.
                  The artist page on the same field and header (Artist.h lists its files), its Music / Video / Merch
                  strip gone so the Music list is the page, and off that list its videos (on until switched off) and,
                  off until switched on, the Artist pick, the Release Countdown and About
                  (spotifyglass.redesign.artist.hide.pick, .countdown, .about). Each is told apart by the identifier
                  its content carries in any language (Components.UI.PinnedItemUI, Components.UI.UpcomingReleaseRow,
                  Components.UI.CreatorBiographyCard; strings of the 9.1.78 and 9.1.90 binaries) and dropped with its
                  heading and spacer (ArtistSections.x). Laid out on the simulator against harness/artist/, whose
                  recorded artist has no countdown. Apple Music's artist photo (off until switched on) and animated
                  artist artwork (on until switched off) are found by name and by the artist's own releases: the rows
                  of the Music list whose subtitle carries a year and which are not an add button or an undo button
                  give the release titles (never a localized section heading), at least two distinct titles must
                  agree, and only one namesake in Apple Music's results may agree — two artists of the same name leave
                  the page as Spotify drew it (SGMotionArtistMatch). The catalog's artists search asks for its
                  editorial artwork and its editorial video, and an artist record without its albums is asked for them
                  by id, so one search and one request per artist cover it. The photo is the studio logo read at the
                  header's width and the motion is motionArtistSquare1x1's video, else motionSquareVideo1x1's, cut to
                  the header's shape and looped in an AVQueuePlayer that plays only while the header is on screen, the
                  app is in front, thermal state is Nominal or Fair, Reduce Motion and Low Power are off and Auto-Play Video Previews is on
                  (SGMotionHeaderMayPlay, shared with the album's cover), fading in once its first frame is ready. In
                  both headers a fully clipped, detached, player-covered or disappeared page, or a backgrounded app,
                  releases the entire looping queue. A side panel that leaves any of the header visible does not.
                  SGRHeaderClip keeps a copy of the last frame and its item time, or leaves the poster if capture
                  fails. On return that still covers the paused seek and first-frame wait, without another fade;
                  an autoplay or accessibility hold leaves it static (harness/album/motion-visibility.sh). One
                  attempt is made per page: evidence arriving later, from release rows laid out after the header's last
                  pass, never retries it, and the delivered answer is dropped unless the page's identity — the ⋯
                  button's own identifier, never a generic one — is still the one it was asked for
                  (ArtistArtwork.m; ArtistHeader.x drives it from the header's passes and from the release rows'
                  layout). Checked on the Mac by harness/artist-artwork/, both the catalog match and the request's
                  identity and one-attempt rules

App:

    ModSettings.x  the root page and the rows that open it from Spotify's settings and the side drawer
    Pages.m        Redesigned UI's switch, the Appearance, Vibrations, Player and Lyrics pages, which Tab bar page opens
    About/         the update check against the repo's GitHub Releases, the Updates page it fills (the state, and
                   the changelog of every release newer than the build, a line per commit), betas counted only
                   while Mod > Updates > Include betas is on (unset, on for a beta build), and the sheet a newer
                   release brings up on its own a few seconds after Spotify opens, once per release; backup, the
                   signing warning, the date the provisioning profile runs out (on the Mod page, and at the top of
                   Mod Settings for a free Apple ID's week) and the Mod page with the reset
    Onboarding/    the welcome page over Home on the first launch, opening on the logo in glass, with Redesigned UI and
                   a No ads switch that sets Hide ads, Hide upsells and Spoof Premium together (off leaves each as it is;
                   on, like a changed look, ends the tour in a restart, as all are read at launch), and under "Easy to miss"
                   a card of pointers, each what it is and where in Mod Settings: Split Tabs (with the redesign picked),
                   Lyrics (sources, lyrics for every track, the redesign's live preview with it picked) and AirPods
                   gestures with the Live Activity (iOS 17 on);
                   on the first launch of a new version instead, What's new (WhatsNew.m), this version's section of
                   CHANGELOG.md, which scripts/whats-new.sh writes into a gitignored header at each make (a section
                   that came over from upstream is left out, so a build without its own has no sheet). The Mod
                   page offers both again. Environment.m says once per install state, a few seconds in, when
                   EeveeSpotify is injected too (a dyld image named so, or its settings page's Swift class), or Spotify
                   is on neither version list in Onboarding.h (supported: 9.1.90 and release base 9.2.0; likely works:
                   none). The version warning does not block launch. Other warnings cover a redesign below iOS 26 that
                   did not start and missing IPA changes, as with a .deb injected by hand: a glass opt-out
                   (UIDesignRequiresCompatibility, under the redesign), or NSSupportsLiveActivities or MusicHapticsSupported
                   missing, each named in the warning and the last two under Live Activity and Vibrations too.
                   A missing Live Activity extension alone does not trigger this warning: signing can strip extensions,
                   and LiveContainer cannot register them. The Live Activity page's missing-install row explains
                   keeping extensions when signing and installing the IPA directly, without implying that the rest
                   of Retrine is broken; all but
                   the third stay as red rows at the top of Mod Settings. What Chroma left in Spotify's storage when Retrine
                   replaced it (its Karaoke model and saved lock screen videos, never its listening history or audio
                   effects) is offered for deleting once, and stays a row there until it goes. Laid out on the simulator by harness/onboarding/

Every key a feature stores starts with `spotifyglass.`, whatever it holds: Reset all settings on
the Mod page removes by that prefix and has no list to keep up to date. It leaves `SGKeyStock` behind,
which makes every unset switch read off, so a reset is stock Spotify whatever switches exist. The API keys
(each AI translator's, the OpenAI-compatible server, DeepL's, Spicy Lyrics' key and the Deezer ARL) live in the
Keychain, which a reset leaves alone; Clear Keychain above it asks first, names what goes, deletes each
service's items by its own name (no wildcard, every account in it). This includes the WireGuard
profile and proxy password: their connection settings are cleared and an active tunnel or proxy
requires a restart. Other settings stay as they were.

A hook reads its switch when it runs (`SGEnabled`, `SGHidden`, `SGFlag` from Core/SGPrefs.h), so a
change shows after Spotify restarts; the tab editor on the Navbar page is the exception and applies as soon as the bar lays
out again, as are the Home gradient's color, strength and height, but not the switch that turns it on, and Vibrations
and Live Activity. The root page in `App/ModSettings.x` links the Appearance page and the page of each part of Spotify, and only the stored look's.
A search field heads it (`Settings/SGSettingsSearch.m`, `SGModPage.searchable`): the first letter typed (or the field
opening with stored places to show) starts reading the pages its rows open, three levels down, one page to a pass of the
main run loop (`Settings/SGSettingsIndex.m`), so the pages read so far answer at once and the rest join them as each
pass ends; leaving the field or its page stops the reading, and a setting changed meanwhile reads the pages again. Every
word of the query is matched against each showing row's title, subtitle, keywords (`SGModRow.searchKeywords`, set with
`SGSearchKeywords`: the names a setting is looked for by that its title does not hold) and the pages above it, case,
diacritics and width folded and Hangul initials taken for a word of initials. The best 60 show, a title starting with
the query first, then one holding it. Picking a row opens its page scrolled to it and lit for
a moment (`-revealRowTitled:`); custom tables are found by their own row unless they expose destinations
through `SGSettingsSearchPages` (Audio effects' Presets and Headphones, and Font's Free fonts).
An empty field shows the places opened from the results before, newest first and at most six, under
`spotifyglass.search.recents`, with a way to forget them. A place is the names of the rows the results led through, never
their titles (translated) or the text typed: a row's `SGModRow.searchIdentifier` (`SGSearchIdentified`), else its key.
A look's own setting names its look in it (`spotifyglass.redesign.accent`) and one both looks share does not
(`page.vibrations`), and a place with an unnamed page row is not stored.

## Lossless

Off unless `spotifyglass.lossless` is set; there is no settings row yet. A FLAC or ALAC file in Spotify's
Documents/Lossless folder (Files app › Spotify › Lossless) plays in place of Spotify's sound for the same recording.

- **Which file:** the folder's index (`.index.plist`, track URI to file name), else a file whose title tag (or
  name) is the track's title and whose length is within 2 s. Artists are not compared. A file goes in the index
  once its sound matched (`SGLosslessStore.m`).
- **Where in the file:** at each track start, seek and resume, 4 s of Spotify's output are matched against the
  file near Spotify's position: first on a mono copy at 1/16 of the rate, then exactly on a full-rate window. A
  normalized correlation under 0.8 is another recording or master, and Spotify's sound stays. The file plays
  from that frame at the gain that matches Spotify's loudness (`SGLosslessEngine.m`).
- **Playback:** a static 2^19-frame ring that a worker thread fills ahead of where Spotify plays. A block the
  ring does not hold yet keeps Spotify's sound. The swap is in Shared/Player's source selector, before Sing.
- **Data:** Spotify still downloads and decodes its own copy, and it downloads a song as it starts. So while
  the next song in its queue has a file, Spotify's quality is set to low, and the user's value comes back
  afterwards, also at the next launch (`LosslessQuality.x`).
- **Not yet:** Karaoke and speeds other than 1 keep Spotify's sound; the first 4 s after each start, seek or
  resume are Spotify's; a silent block drops the anchor until the next try. Sources that download files are a
  design only: [Lossless sources](lossless-sources.md), [addons](lossless-addons.md),
  [playback investigation](lossless-playback.md), [prototype history](lossless-prototype.md).

## Make targets

    make build      # out/retrine-<version>-pixie.ipa on 9.2.0, with FLEX
    make release    # the same without FLEX
    make release PIXIE=0  # omit Pixie (pipeline: --no-pixie)
    make install    # build without FLEX, sign with your certificate, install over USB or Wi-Fi
    make install FLEX=1   # the same with FLEX, which is what make trees reads through
    make quick      # rebuild only the tweak into the app the last make install made, sign, install (seconds)
    make trees      # record view trees screen by screen (FLEX build open on the phone, USB)
    make session    # clean trees, as many snapshots per screen as you like: Enter saves, n goes to the next screen
                    # (SCREENS="playlist artist" for some); every snapshot says whether the mod was at stock
    make log        # stream [spotifyglass] log lines from the phone
    make flags      # regenerate the flag table from the IPA

## Diagnostics

A build with FLEX in it (`make build`, `make install FLEX=1`) runs `Diagnostics/`: the tree server, the hang
sampler, and the phone driver, which lets an agent on the Mac work the app without anyone touching the phone.
The USB listener binds 127.0.0.1:8085, which the Mac reaches through iproxy. The separate tunnel listener
requires a token even for the tree; a utun address in the Tailscale range need not belong to Tailscale.
`GET /tree` answers with the visible screen's view tree, as `make trees`
records it. The driver adds `GET /<command>?<params>`, each answering JSON with `ok` and either what happened
or an `error`. A command needs an `X-Phone-Driver` header, which a web page on the phone cannot send to the
loopback without a CORS preflight the server never grants (`curl -H 'X-Phone-Driver: 1'`). It is compiled only with `SG_DRIVER=1`, which `scripts/pipeline.sh` sets for the builds that
carry FLEX; `make release` and the release workflow's build omit the server and screen dumps entirely.
Private preferences cannot be driven, except for the read-only token bootstrap over loopback.

`scripts/phone.py` is the client. It uses whatever already answers on 127.0.0.1:8085 or starts iproxy and
leaves it running. `state`'s screen and the controllers its path holds come from Core's resolver
(`Core/SGTopController.h`), which the keyboard's Esc and ⌘F read too, so the driver and the keyboard never
disagree about what is in front.

    scripts/phone.py tree | state | log [--since N]
    scripts/phone.py find --class UILabel
    scripts/phone.py tap --id X | --label X | --text X | --class C [--index N] | --at X,Y
    scripts/phone.py longpress --id X [--duration 1]
    scripts/phone.py swipe --from X,Y --to X,Y [--duration 0.2] [--drag 1]
    scripts/phone.py scroll [--id X] --by 0,400
    scripts/phone.py type "text"
    scripts/phone.py player.open | player.close | player.more | play | pause | next | seek 42
    scripts/phone.py menu.pick "Sleep timer"
    scripts/phone.py tab 0 | tab Search
    scripts/phone.py settings.open | settings.page "Appearance"
    scripts/phone.py wait --id X [--gone 1] | --menu 1 | --log "system menu: the player's menu is up" [--timeout 3]
    scripts/phone.py screenshot out.png
    scripts/phone.py pip.frame out.png [--current X] [--next Y] [--credit Z]

Views are addressed as the tree prints them: `id=` is the accessibility identifier, `a11y=` the accessibility
label, the quoted text a label's, and a class with an index counts that class's views in the tree's order.
Points are screen points, the frames `find` prints. Touches are made as a finger's (`harness/tabbar/touch.m`'s
way: a UITouch and the IOHIDEvent gesture recognizers read, through `-[UIApplication sendEvent:]`), so
controls get their control events, recognizers recognize, and a button whose menu is its primary action opens
it on the touch down. `menu.pick` taps a row of the system's menu, not of Spotify's own sheet (tap that by
`--text`). `log` reads the app's last 2000 `SGLog` lines from memory, so no device log capture is needed;
a log wait looks from the start of the last command that did something. Everything runs on the main thread
through `dispatch_async` and a semaphore with a timeout, waited on from the server's thread only. Checked in
the simulator by harness/driver/.

## Mod Settings

Mod Settings, opened by holding Home on the tab bar or from the first row of the side drawer and the
last row of Spotify's Settings, looks like the system Settings app in its dark appearance under either look:
cards of #1C1C1E on black, 17pt rows that follow Dynamic Type up to xxxLarge and the app font, each part of
Spotify behind a symbol on a tile of its own color, gray chevrons and footnote headers. It has no account
page. It sorts every
setting by the part of Spotify it changes, so a part's glass, its hide switches and its flags sit on
one page, the mod's own rows first and Spotify's flags below them or on a sub page named after what
they change. Under any signing and environment warnings, both looks have six sections:
Look & navigation (Redesigned UI first, Appearance and Tab bar); Screens (Home, Search & Library, Player, Lyrics,
Albums, Artists and Playlists); Audio & playback (Audio effects, Karaoke including Spatial voice, AutoMix, Playback &
local files and Listening stats); Outside Spotify & devices (Lock screen, Live Activity on iOS 17+, Picture in Picture,
AirPods gestures and Vibrations); Privacy, network & downloads (Premium, ads & privacy, plus WireGuard and Pixie
in builds that include them); Advanced & about (Labs, All flags and Mod). It is checked in the simulator
against harness/mod-settings/. The Appearance page has, in the native look, AMOLED (the redesign is always black), then the stored look's Accent color
preset, a pull-down of Spotify, Apple Music and Custom read off the color stored (a color set before the presets
existed reads as Custom, Apple Music's red as Apple Music), and Accent color, the hex and a swatch of the color in
effect, which opens a sheet of the colors chosen before over the system picker, storing only from a swatch or from
the picker's checkmark (never while it is dragged), as Custom. The recent colors are up to 8 discs, newest first,
under a "Recent colors" caption; choosing a color already listed moves it to the front instead of repeating it, the
9th drops the oldest, and Spotify's green is never kept, nor the redesign's own green, nor an entry that is not a
whole number in #000000–#FFFFFF. Each look keeps its own list under its own key (SGKeyAccentRecent for the native
look, SGRKeyAccentRecent for the redesign), its swatches labelled with the color's name or hex and marked selected
when it is the one in effect. The two lists' rules are checked against
harness/appearance-page/ (rows). The custom color is
kept aside while a preset is in place, so Custom brings it back. The redesign's page leads with Accent source
(spotifyglass.redesign.accent.auto, Picked unless switched): Picked is the color above; Automatic takes the color of the
page in front (SGRAccentPublishPageColor), else the playing cover's, else the pick, and moves only when a navigation
transition ends, a cancelled interactive pop included. The preset and color rows keep showing the pick, never the
temporary color. What is drawn in the accent is a token (SGRAccentToken, Kit/SGRAccent.x) that keeps its alpha, its shade
and Spotify's own green, so an image, a background or a shape layer is recolored by what it was made from and never by a
similar hue, a running animation is never replaced (only a newer submission takes the color), and Picked or Spotify's
green puts the originals back; Follow the cover paints on the same tokens (PlayerCoverAccent.x). The token hooks are
installed only when a launch starts with an accent other than Spotify's green or with Follow the cover on (read at
launch like the accent, so turning it on needs a relaunch too); while installed they keep recording
tokens even when the user switches back to Spotify's green, so the accent can return live. A launch with Spotify's
green and Follow the cover off installs nothing, and choosing an accent then takes effect after a relaunch (the page's
restart note). With Spotify's green and Follow the cover on, the tokens resolve to Spotify's own colors everywhere
but the player's controls, which follow the cover (harness/appearance-accent/). After the accent the redesign's
list has its glass, every glass the redesign makes: the glass behind its buttons that Redesigned/Kit/SGRGlass.m makes
(SGRGlassInside, SGRGlassCapsuleInside, SGRShowGlass), the glass tab bar's platters, main and split, expanded and
minimized (Redesigned/Navbar/TabBar.x hands each platter UIKit draws to SGRGlassRestyle, which gives it the
listener's glass through `-[UIView _setGlassEffect:]` only when they chose other than Regular, None and on, since any
glass handed over comes out with UIKit's smoothness 6 lost), the now playing card's glass and its Jam strip's
(Redesigned/NowPlayingBar/NowPlayingBar.x) and the glass behind both bars' stand-ins while the player opens and closes
(BarTransition.x) and the search field's (Redesigned/Navbar/SearchField.x, once per pane), all through SGRGlassEffect().
Search's category cards keep their Clear glass in the category's color, and the full screen lyrics page's
(Redesigned/Lyrics/LyricsPage.x) stays Core's regular glass, for the words' legibility. The choices are each read once as the redesign starts (a constructor, not the first glass made,
so a launch under Reduce Transparency that changes them and then switches it off still waits for a restart): Glass material (`spotifyglass.redesign.glass.material`,
Regular or Clear, UIGlassEffect's two styles), Glass tint (`spotifyglass.redesign.glass.tint`, None, Light or Dark,
white at 30% or black at 45% as the glass's tint color) and Glass touch response
(`spotifyglass.redesign.glass.interactive`, on until switched off: interactive glass). Nothing stored is Regular, None
and on, and a stored material or tint that is none of the choices reads as Regular or None. Under Reduce Transparency a
shape is the solid fill whatever is chosen, and the bars keep UIKit's own opaque treatment of their glass (iOS 26.5
simulator: Clear and Dark show no page through either bar), and below iOS 26 the dark blur stays as it was: the three
apply to the iOS 26 glass only. The tab bar's platters answer touches as UIKit's do, and switched off their glass stays
still while the tabs still take their taps; the card's glass takes no touch, its own press stays its answer
(harness/tabbar glass-check.py). A shape takes no touch, the control it sits in does; interactive glass gives under the touches of the view
UIKit asks `-_flexInteractionGestureView` for, so the shape (SGRGlassShape) names its control, as UIKit's own glass
background behind a button names the button: the control SGRGlassBacks gave it, else the control it sits in (Home's
pill keeps its glass in a holder beside the buttons, and Redesigned/Home/HomeHeader.x gives it the Filter button), and the glass answers the control's touches while the control keeps them,
with its action, highlight and VoiceOver; a disabled control names nothing and its glass stays still. A shape that took
touches itself left its button without a tap (iOS 26.5 simulator). Switched off, the glass is not interactive and the
control works as ever. Saved mark (`spotifyglass.redesign.savedMark`; Spotify's, Plain checkmark or Dot) replaced the
Plain checkmark switch: a saved song's circled tick stays Spotify's, becomes a plain checkmark in the accent, or a filled
dot in the accent in the same place, only while the button is selected (saved), the unsaved plus always Spotify's
(SGRPlainCheck.x, SGRAddGlyphFor). With nothing stored, or a value that is none of the three, it follows the old switch
(`spotifyglass.redesign.plainCheck`: Plain checkmark when on, Spotify's when not; SGRSavedMarkFrom), which is read and
never written or removed. The Player page's Star add button still wins in the player. The button's action, its selected
state, size and accessibility label stay Spotify's, and the mark follows the selected state on every set and layout, so
a reused row or a song unsaved gets the right glyph back. Checked against harness/appearance-page/ (rows-check: the
defaults, out of range values, the old switch carried over and left alone), harness/player-refinements/ (`dot`) and
harness/glass-choices/ (an iOS 26 simulator: each material and tint, touch response on and off judged from screenshots
held against at rest, Reduce Transparency, and Dot over a list scrolled for reuse, unsaved and saved again). Hide explicit badge
(off) ends either look's list (spotifyglass.hideExplicit native, spotifyglass.redesign.hideExplicit redesigned;
Native/Appearance/ExplicitBadge.x, Redesigned/Kit/SGRExplicitBadge.x): a transparent mask over Spotify's own badge views,
Components.UI.ExplicitIcon and the retrieval row's ExplicitBadge class, never an E label found by its text, so the layout,
VoiceOver and content restrictions are as Spotify has them; a flip applies to the badges on screen. In the redesign the
list also has Blur covers on scroll (`spotifyglass.redesign.hero.scrollVeil`, off; Redesigned/Kit/SGRHeroVeil.m): the
album, playlist and artist pictures blur (radius 0 to 24 between 60 and 320 pt of scroll) and dim into the page's color
(alpha up to 0.45 between 80 and 400 pt) as the page scrolls, with the full-screen art drifting at a quarter of the
scroll and zooming on a pull, the Card-mode square blurred and dimmed in place, and the header text faded out over
14 pt under the top bar (SGRHeaderInfo.m's -clipUnderTopBar, a mask sized once per header size and only moved on
scroll); Page title when scrolled (`spotifyglass.redesign.pageTitleWhenScrolled`, on; Redesigned/Kit/SGRScrolledTitle.x): off, the small title Spotify puts between
Back and ⋯ once a playlist, album, artist or profile page is scrolled stays hidden, Back and ⋯ untouched, applied live
and restored only once a push or pop has settled; and Play in the page's color (`spotifyglass.redesign.playInPageColour`, on:
off, the Play glyph and word take the accent). Checked in the simulator against harness/album/veil-check.sh. The redesign has no
global Full bleed covers row: the Albums and Playlists pages each have a Cover layout. Last come the Font, under either look and on any
iOS, below 26 too, a page of its own with each choice drawn in itself: Default (Spotify's; named Spotify Mix in the
redesign), San Francisco, SF Rounded, New York and SF Mono. Nothing stored is Spotify's font in the native look and San
Francisco in the redesign, whose own text is San Francisco (Fonts.x, SGAppFontChosen); a stored choice, Spotify's
included, wins, and a font whose files go away removes the stored choice so that default applies again; More fonts, the families iOS carries of a fixed few (Avenir Next to American
Typewriter), each weight taken as the family's nearest face; and Your fonts, the files of one family (.ttf, .otf, .ttc or .otc, picked
together) added from Files, refused when their faces name more than one family, copied to Application Support/Retrine/Font
and registered again at each launch, each weight taken as the family's nearest face, Spotify's font coming back when
the files are gone. Swiping the row deletes the family. An import from before families (one file under
spotifyglass.font.file) moves to spotifyglass.font.files and the family name on first use. Free fonts, between More fonts and Your fonts, lists
the free families on this iPhone, each drawn in itself once FontLibrary.m has registered it off main and announced it, as is the imported family once its
files are registered (opening the page or finishing a download never waits for Core Text; SGRegisteredCustomFont and
SGFontLibraryRegisteredFamily give the names the Lyrics PiP font choices use; the launch registers them synchronously
in Fonts.x, as the global font hook needs them first), and opens the free fonts page (Shared/Fonts/FontLibraryPage.m): sixteen SIL Open
Font License families from github.com/google/fonts pinned to one commit, Korean first, each file and its OFL.txt checked against its
size and SHA-256 (FontLibrary.m) before the family moves from a hidden folder into Application Support/Retrine/Font Library, one
download at a time with its progress on the row and a tap stopping it. A family downloaded becomes the app's font
(spotifyglass.font 7, spotifyglass.font.library) and is registered again at each launch; a swipe deletes it or opens its license, and
Spotify's font comes back when its files are gone. Then the App icon. Everything on the page applies after a restart. Redesigned UI, the main page's
first row, is the one switch between the two looks (see Layers): it glows (Settings/SGGlowSwitch), its ⓘ says what
it changes, and flipping it offers to restart Spotify. The pages show only what the stored look has: a page opened
after flipping the switch already shows what the restart will bring. Albums and Artists open each look's own pages.
In the redesign, Playlists, Home, Search & Library, Albums and Artists lead with a live preview of the page
their settings change (switchable between Search and Library on their combined page; Kit/SGRPagePreview.h, drawn
over local placeholder art and following the switches as they are flipped, in the table's header with the page's
intro note under it, as the Lyrics page keeps its preview), described under Redesigned/Kit/. The Albums page's
Album notes row picks Under Play, Under tracks or Off for Apple's editorial notes; a Cover layout row (Card or Full
screen, here and on the Playlists page) leads it, and Play counts take a place and a Count source. Its Artists counterpart adds
Animated artist artwork and Apple Music artist photo under Artist logos, then Play: Round artist Play
(`spotifyglass.redesign.artist.roundPlay`, off: a 64 pt white circle with the glyph alone, Shuffle and Follow at 44 pt
beside it), Cut-out Play (`spotifyglass.redesign.artist.cutOutPlay`, off, only with round Play: the circle filled white,
or in the accent with Accent Play button, `spotifyglass.redesign.accentPlay`, off, its glyph cut out by an alpha mask
redrawn only when the glyph, bounds or font change; Kit/SGRActionRow.m, harness/artist/cutout-check.sh), and Header:
Picture-aware photo and Monthly listeners in About (`spotifyglass.redesign.artist.listenersInAbout`, off: the line
under the name is omitted from the first layout when enabled, since Spotify's About already shows the count.
Turning on Hide About keeps the line under the name; ArtistSections.x,
harness/artist/listeners-check.py). The Player page leads with a pinned miniature of the whole player showing the
current or last song (480 pt, shrinking to 236 pt as the page scrolls, opaque above the rows; with Star add button on,
the star before the ⋯ as the player draws it), whose Without a clip
pill previews the selected Animated fallback without sending a playback command
(PlayerSettings.m; preview lookups are tied to the shown track and torn down with the page, SGRPlayerMotionPreviewStop,
SGRPlayerVisualiserPreviewStop; harness/player/settings-check.sh). Its Buttons card has Shuffle, Repeat and Video chips.
The Controls section has Lyrics Line, Rolling time digits, Star add button and Music app icons beside Header glass, Volume and Follow the cover.
Volume keeps MPVolumeView for local playback. On a volume-capable remote device, Spotify's own Connect aggregator
selects a matching slider backed by its Connect volume service (Redesigned/Player/PlayerConnectVolume.x).
Hardware buttons remain entirely Spotify's: local outputVolume deltas cannot represent presses at the phone's
limits and forwarding them changes local volume too. No KVO forwarding or native-handler suppression is installed.
Every hooked method, observer callback and invoked Spotify API must match its return and argument types;
a missing or mismatched API disables Connect volume for that process. Missing state or an unusable volume keeps
the local path. Native is unchanged. Lyrics-only mode keeps even a newly created volume row hidden and restores it only
when it still has room (PlayerLyrics.x, PlayerVolume.m). Connect delivery and physical taps require a real device;
the player and haptics harnesses cover slider routing, signature rejection, current-device reads, fade restoration and step/end feedback.
With Volume shown, the controls keep Spotify's vertical position rather than lifting 10 pt into the time row;
`harness/player/volume-layout-check.sh` runs real placement at 402×874 and 375×667 (SE), checking unobstructed
time/playback controls and clean omission when there is no room.
Audio effects has the shareable presets and AutoEq headphone corrections; Appearance's Font page has free
and on-device custom fonts. In the redesign, Player's Visualizer background links to its styles and Lyrics
links to Lyrics styles. Tab bar: the tab editor of the stored look, each with
its own list of tabs. Lyrics, on the main page of its own: in the redesign a live preview of the lyrics first, with the presets of their look
under it and their sliders in Tune look (Text size, Line spacing, Blur, Glow, Wave), applying at once.
Display contains the redesigned lyrics controls or Native's Glass lyrics. Pronunciation enables the inline alphabet
menu; Japanese reading (Romaji or Hiragana) appears for Latin, not Hangul. Both looks offer Timing, Translation & AI,
Sources, Source accounts, and Offline & imported lyrics. Translation language and the shared prompt are available
in either look, as are the automatic translation switch and provider order used for lock screen lyrics.
Karaoke, under either look, is on the main page, its row reading out On,
Off or how far the voice model's download has come, kept up to date while the page shows: Karaoke's switch, which turns
the mic on and off at once, a card at its top (SGSingCard.m: the song, what Karaoke is doing, a tap saying more, the vocals
and the rest traced live from the engine's loudness, Karaoke running on the playing song while they show even at As sung, still under Reduce Motion, play and pause, and a tall Vocals slider
from gone through as sung to the vocals alone, with Sing along, Original and Vocals only under it), Spatial voice
(where the iPhone reads headphone motion; a page of its own, reading out On or Off, with a live preview at its top that
follows the head through AirPods, or sways gently without them and holds still under Reduce Motion, a line under it
saying which, then the switch), a Voice model section (Best quality
and Light, a checkmark against the chosen one, each with its size; then the chosen model's download, Paused and Checking
among its states, and its removal; and Remove the other model, with its size, while the one not chosen, or the old
model with the full one, is on the iPhone), Toggle from lyrics (the redesign's mic, issue #12; until switched, on where Karaoke can run and off below iOS 18,
SGSingButtonShown),
and under Advanced Runs on (Automatic: the Neural Engine
beside the CPU; CPU only), Prepare after updates, Ignore heat warnings and Ignore memory warnings, all applying straight away. Lock screen, on the main
page under either look, opens the lock screen widget's page, titled Lock screen: Widget (the line in place of the artist,
its Lyrics line, Original or Translation, and Spotify's like and dislike buttons' flag, locked off while the star is on) then
Artwork (Off, Moving artwork, Lyrics, Every song or Moving artwork with lyrics, the lyrics' style, Still or Animated,
fallback Background with darkening, blur strength or solid color, Translations, Switch with the star;
below iOS 26 one row saying why not). Playback & local files → Data & prefetch holds Artwork sources and Download in Low Data Mode.
Mod → Storage contains Clear Downloaded Covers and Artist Photos (AnimatedArtworkSettings.m's
SGArtworkCacheRow): their size measured off the main queue, and after an alert with Cancel only the store's own clip
files (SGMotionStoreClear, a clip in use left in place) and the album answers file (SGMotionCacheClear) removed; a
transfer or lookup begun before it delivers to its own caller but keeps and starts nothing; songs, a chosen cover,
edits and lyrics are untouched; harness/artwork-clear/. Spotify's podcast, audiobook and artwork flags stay in All flags.
Playback & local files holds the sleep timer fade, blocked artists and songs, Lossless files, Local files and Load ahead
(`spotifyglass.loadAhead`, on until switched off: only the advance work on the next track's artwork and lyrics stops).
Player has Gestures, Full screen cover on tap (`spotifyglass.hide.fullScreenCover`, shown until switched off, live) and Audio quality (the badge under the progress bar,
`spotifyglass.player.audioQuality`, off until switched on, live; Shared/Player/AudioQuality.h), which work with either look, including below iOS 17;
in the native look also Mini player (its device button and its flags), Queue & devices, and
Spotify's own player screen (artwork background, glass header buttons, Disable Canvas and the sheet,
header, slider and sticky header flags, the cards under the player and the lyrics preview and player
buttons to hide); in the redesign the page instead leads with a card of the player (Redesigned/Player/
PlayerSettings.m): the background chosen edge to edge, and over its foot the cover, title, artist and progress;
for Animated while the player has no clip, the card looks the playing track's up itself while it is on screen
(SGMotionClipFor, the player's sources, size and Low Data Mode, into the store the player reads), Fluid until it
is in, then the clip over it, poster first (harness/player/ `preview`);
under it a segmented control of the five backgrounds (Still, Colors, Fluid, Animated, Visualizer, changing the card at once)
with a note on what the one picked does, and a Behind the Player menu (Artwork, Black, Your Photo) that lays pure
black or a photo of the user's own over the field instead (PlayerBackdrop.m, kinds 5 and 6 of
`spotifyglass.redesign.player.background`; Artwork goes back to the last segment, `...background.artwork`). The photo
comes from PHPicker, is kept as a JPEG of 2048 px at most in Library/Application Support/Retrine, fills the screen
from its middle and is dimmed by its brightness as the Animated clip is, more with a blur behind the lyrics; it
applies at the player's next layout, no restart; while Visualizer is chosen, its local style menu offers Hills (the default),
mirrored Bars with a waveform, a bass-driven Nebula and an artwork Halo, then the lyric styles: Lyrics, Poster and Cut. The selection is stored under the existing
`spotifyglass.visualizer.shader` key, with invalid or absent values falling back to Hills, and the preview and player update at
once. Poster (`builtin:poster`) sets the sung line word by word as a heavy, left-aligned type poster over a halftone print of the
cover on black, the words still ahead faint; Cut (`builtin:cut`) shows one word at a time as large as fits, over the darkened cover
and a few flat blocks of its colors placed from the word, jumping a little at each word and settling (still with Reduce Motion),
the whole line small under it (PlayerLyricStages.m). Both read the line as Lyrics does, so without synced lyrics, in a break or
while the player's lyrics are open they show its quieter hills alone. The halftone is made once per artwork off the main queue;
text is built only when the line or word changes. Their rows on the Visualizers page show only for the style chosen (Poster:
Halftone, Type color, Print strength, Words ahead; Cut: Type color, Background, Motion, Whole line), stored in one dictionary,
`spotifyglass.visualizer.params` (style id to parameter id to value, colors as `#RRGGBB`; a malformed value reads as its default,
a number out of range is clamped, and a default is stored by removing it), and apply at once (harness/player-visualiser/). Shuffle styles (`spotifyglass.visualizer.shuffle`, off) picks another style at random, never the current one, once
for each new track while the Visualizer is on screen with the app in front and not stood down; the user's own pick is
kept under `spotifyglass.visualizer.shuffle.home` and comes back when shuffle is switched off. Visualizer motion pauses
while hidden, backgrounded, in Low Power Mode, under serious heat (unless Ignore heat warnings,
`spotifyglass.visualizer.ignoreHeat`, off) or during player transitions,
and is restrained by Reduce Motion (harness/player/ `shuffle`, `heat`).
Animated offers five choices for **Song without a clip**: Still, Colors, Fluid, Full-screen cover and Visualizer.
Still, Colors and Fluid use `SGRKeyPlayerNoClipBackground` (`spotifyglass.redesign.player.noClipBackground`).
Fluid is the default, including for older settings and out-of-range values. **Keep background still** is off by
default and appears only for Colors and Fluid. The selected fallback applies when the lookup confirms there is
no clip. A pending lookup or a square clip playing in the cover keeps Fluid behind the player.
Visualizer (`spotifyglass.redesign.player.animatedVisualizer`, off by default) appears after a confirmed miss.
A later clip or a new track takes it down. Low Power Mode, Reduce Motion or the heat limit keeps the ordinary cover.
Full-screen cover (`spotifyglass.redesign.player.animatedStill`, off by default) uses the cover Spotify already
drew when it is at least 300 px wide. It crops to 4:3 at most and dims and blurs behind lyrics as a clip does.
A 45% black scrim fades out 76 pt below the safe area. A later clip replaces the cover. Black and Your Photo take
precedence, and Low Power Mode, Reduce Motion or serious heat keeps the ordinary cover. The two switches turn
each other off. When an older installation has both enabled, Full-screen cover wins (PlayerMotion.x,
harness/player/ `autoviz` and `still`).
Choosing Fluid as the main background shows its sliders and a red Reset. Where Metal is available, the Style
menu offers Light or Smooth (`spotifyglass.redesign.fluid.renderer`). Redesigned/Kit/SGRFluid.h defines the
`spotifyglass.redesign.fluid.*` settings.
Light turns preblurred Core Animation copies, with no Metal renderer or music analysis; it is what shows where Metal is
missing. Smooth, the default, draws on the GPU (Redesigned/Kit/SGRFluidGPU.m):
three copies of the cover, 1.4, 0.7 and 0.7 units across (a unit half the visible rect's height on a phone) at (0, 0),
(-0.25, 0.15) and (0.7, 0.7), each turning clockwise about its own center once in 120, 70 and 90 s, the third carried
about the middle by the first's turn, drawn opaque into a quarter-size half-float picture (as the Music app's, so what the saturation pushes past 0 or 1 is
kept through the blur) after a mix toward black, a contrast
about middle gray and a saturation about Rec. 709 luma; the picture blurred by a two-pass Gaussian; then shown through a
24 x 24 mesh, flat and a quarter larger while held still; flowing (0.8 s between, eased), bent by one of two 6 x 6 grids
of Retrine's own, made at random per layer (the inner points well off the even grid,
the second the first with a few points moved, never folding over itself), and breathing from one to the other once in 2 pi * 3.5 s; mixed toward white, read through a 32^3 color table made from
Retrine's own grade (SGRFluidGradeTable), and its lowest channel taken down by a share of the spread. With these numbers (0.5
toward black, 2.4 saturation, 0.1 toward white, a 160 pt blur) it matched screenshots of the Music app's player
closely. Like it, it hears the music (Shared/Player/SGMusicSpectrum.x: each band's
share of the spectral power of Spotify's output, bass 20-300 Hz, middle 300-3500 Hz, treble 3500-24000 Hz, from an
unwindowed 2048-point FFT at 48 kHz, resampled to it if need be, 23.4 a second, scaled by the
frame's loudness, 20 log10 of its power over 120, then by an intensity of 0.2): each reading taken once into
the last four and averaged, held at its peak and let fall, followed and eased, bass raising the contrast (0.076), treble
the saturation (0.166) and bass and middle growing the picture (0.33 m^2). Paused, one empty reading goes in and no
more. The first visible, moving Smooth consumer attaches the spectrum to the current output;
the last one stopping detaches it. Native installs no spectrum watcher, FFT setup or render notify.
Format changes discard partial frames; non-48 kHz analysis waits for a kernel prepared off the render thread, never the other way around.
For Smooth, the Light copies also stand in until the first drawable and when Metal cannot draw.
A covered replacement uncovers its new copies first, not the old drawable. Checked by simulation only, not on a device
(both styles, switched both ways while moving, a cover change mid-flow). The sliders:
Speed (25-300 %, how fast the three blurred copies turn, picked up from the angle each is at), Warp (0-100 %, how
far from the middle the two smaller copies sit and how much they show, opaque at 100; at none the large copy turns alone), Blur (2-32, 160 pt at the standard 24 and in proportion), Saturation (0-250 %), Brightness (40-150 %, a gain on linear
light that the luminance ceiling, 0.17 or 0.04 with Increase Contrast, still caps; the shade over the lower part, not the ceiling, keeps the text's 4.5:1: see Backdrop ink) and Grain (0-200 %, 100 standard, shown only while Smooth
is the style, spotifyglass.redesign.fluid.grain: noise over the picture, none at 100 or below, as the Music app's backdrop has
none, at 200 a visible grain of 24 steps, spread only darker above 100 so no pixel rises over the ceiling and the
text keeps its contrast; the Light copies have no grain to scale); the
card and the player follow each step at once through SGRFluidSettingsDidChangeNotification, the last three by
blurring the cover again off the main thread, and Animated and Visualizer's Fluid with them,
and Mini player: Apple Music style (the tab bar's minimize on scroll), Device button (the now playing bar keeps
Spotify's device button in that minimized row, off by default, and wins there over the full bar's hiding of it), Artist under the title when minimized
(`spotifyglass.redesign.inlinePlayer.artist`, off: in that row the artist as a second line, only when both lines fit
the bar with 6 pt to spare, the full bar unchanged; harness/now-playing-bar/), Next button
(`spotifyglass.redesign.nowPlayingBar.nextButton`, on until switched off: a forward button after play on the full bar that skips to the next
track, hidden in the minimized row; live), Artwork shape (`spotifyglass.redesign.nowPlayingBar.artworkShape`, Circle unless
set, or Rounded square with 8 pt corners; live, and the player's open and close morph from the shape shown;
harness/now-playing-bar/), the device button hidden on the full bar (on until switched off), and the
like button hidden (Spotify's own flag ios-feature-nowplayingbar.add_button answered off at launch unless the row or All
flags stores an override, which wins, or settings are reset to stock; NowPlayingBarSettings.m), so the bar ends in play
and Next as the Music app's mini player does,
checked in the simulator against harness/player/ (`settings`). Vibrations, a page of its own under either
look opened from the main page (the row reads out which of the two are on), leads with a preview (Shared/Haptics/SGVibrationsPreview.m): rings of dots that a tap sends a crest across, out
from the middle in the accent color, higher and further the stronger the Strength, while the first of Controls and
Music Haptics that is on plays its own tap through its own path (Controls' add tap, or one kick of Music Haptics'
with its rumble unless it follows Beat), the line under it naming which, or saying why there is none. While the page
shows, each tap Music Haptics plays sends a low crest too. Nothing runs between crests, and with Reduce Motion the
rings light up together and fade instead of moving. Under it a card for
Controls (on until switched off) and one for Music Haptics, which holds two switches, both off until switched on,
each with an ⓘ: Music Haptics, the mod's own from the sound while Spotify is in front, and In the Background
(left out below iOS 18), the song named to iOS's own Music Haptics. The one choice of before moves to them once
(Generated to Music Haptics, Native iOS to In the Background, None to neither). Controls
has its Strength under it, grayed out while the switch is off (10 to 100%, a tap at the new strength with each step);
Music Haptics its Strength (20 to 200%, 100% being how it first shipped, a kick at the new strength with each step) and
Follows, grayed out the same way, Everything (a tap on each kick and snare and a rumble under the bass), Beat (the
taps without the rumble) or Bass (the kicks' taps and the rumble); In the Background a Status row (Paused, Waiting,
Checking, "Sent, iOS not playing yet", Playing or Unavailable) while it is on, or, while Music Haptics is off in Settings > Accessibility, a
row saying so whose tap opens its ⓘ, all applying straight away. Live Activity, on iOS 17 and up under either look: its switch and which view it
shows, Lyrics, Queue or Control menu, and for Lyrics its Without lyrics (Note or Track), Alignment (Center, or Left),
Translations (off until switched on) and Text size (Small, Medium or Large); then for every view a Card section of
Artwork and Progress bar (both on until switched off) and Colors (Spotify, Artwork or Plain), with a note that the
card shows on a paired Apple Watch and in CarPlay too, all applying straight away, the row reading out the view or
Off. At its top a preview, a slice of the lock screen with a mock of the card with a made-up song, follows the
options as they change and steps every 3 s through the picked view, the lines being sung or the menu's tabs, with
a crossfade; under Reduce Motion it rests and a tap moves it on, and it stops while the page is off screen. Audio effects, in either look (Shared/AudioEffects/AudioEffectsPage.m):
the effects' switch with what the engine is doing under it, Presets (built-in ones and your own, saved, loaded
and deleted there) and Headphones (AutoEq's corrections, searched and applied to the Graphic EQ, with Use for <the
output playing now> keeping the pick for that output and the remembered outputs listed, a swipe removing one), either of which
turns the effects on, then a card per effect, each opening out into its sliders, choices, curve or file library
while its switch is on (Reverb has its Room and its Amount, the amount the player's ⋯ menu also sets), everything
applying as it changes; the row reads out Off, On or how many effects are on. Home & Library, in the native look only:
the Gradient page (the wash behind the top of Home in one of eight colors, at three strengths and
four heights) and the Home flags, the parts of Home to hide including the DJ button and badge, and the
Library flags. Playlists, Albums and Artists are separate root pages. Then Premium, ads & privacy
(EeveeSpotify's Hide ads and Hide upsells, in the native look hiding the video carousel in Search, and
an Ad and upsell flags page under them, every switch there forcing a flag Spotify ships on to off;
Spoof Premium; Block telemetry; Clean shared links; then what the ad
blocking and the telemetry blocking have stopped) and Labs (features Spotify built and did not ship,
AI Chat (Martini) first). Last, All flags, Spotify's remote-config flags with a search field and an
Auto / Off / On control per flag (a text field for the number and text ones), and Mod: Updates
(the row reads out where the build stands and opens the changelog of everything newer than it, or
the build's own notes if it matches the latest eligible release. A build change bypasses the
six-hour cache once; an older cached release contributes neither its date nor its notes. Releases are read
from the releases Release Please cuts, with Check now, the release to get, all the releases and Tell
me when one is out, the sheet a newer release brings up a few seconds after Spotify opens), the
build and Spotify's version, the site and the repo, What's New and the welcome tour again, Clear Keychain and Reset all
settings. Mod › Storage links to Spotify's own storage settings (`spotify:config:storage`). Choose a cache
size there: Spotify saves the limit and trims its cache itself, not downloads. With a small cache Pixie
may need to download a streamed track before export. A flag switch on a page forces that one flag and off leaves Spotify's own value, so the All
flags page is where a flag goes back to Auto. Spotify ships its newer design behind several flags at
once, and the redesign is built on it (the glass navigation bar, the new player slider, the sheet style
player, the queue and Connect sheets, the redesigned player header, the sleep timer's options sheet):
while Redesigned UI is on each is forced, over an override too, and their rows elsewhere show what is
forced and take no touch. `Redesigned/Kit/SGRGlassDesign.x` holds the list; what else forces a flag
registers in `Core/SGFlagForce.h`. A change shows after Spotify restarts. Spotify reads most flags
only when their feature first needs them, so 15 s after launch the log says how many stored overrides
it has asked for and which not yet (`flags: N overrides stored, …`), and an override asked for later
gets its own line as it is asked (`flags: Spotify asked for <flag> only now, …`).

The tab editor on the Tab bar page is the exception and applies as soon as the bar lays out again. It lists the tabs in the order
the bar shows them: drag to reorder, tap to hide or show, and Add a tab puts a page of Spotify's or
any `spotify:` link on the bar. It is a sheet: a name, a link picked from Spotify's pages or pasted (one
Spotify's router cannot open is refused there), and an icon picked from Encore's glyphs or the SF Symbols,
searchable. Split tabs sets chosen tabs apart at the right end of the bar: after a gap in the native look,
on a glass bar of their own in the redesign, like Search in the Music app. Spotify's own tabs are kept by the
name under their icon, so they can be hidden but never removed, and switching the app's language
starts the order over. A tab of the mod's own opens its link through Spotify's link dispatcher. In the native
look it never lights up as the tab you are on; on the redesign's glass bar it does while the page it opened is
up, and a second tap goes back to that page. In the redesign (Redesigned/Navbar/NavbarSettings.m) the page leads
with a preview of the glass bar, drawn by the same system UITabBar as the bar itself from the list as it
stands, the split tabs on a bar of their own, and changing with every change on the page; then Custom tab
bar (off, the bar is Spotify's own tabs in Spotify's order, the list kept); two picture cards for the labels,
Icons and names or Icons only (Icons and names the default, as the Music app's bar has; applying straight away); Apple symbols (on
until switched off, applying straight away to the bar, the preview, the cards and the list: Spotify's tabs take SF
Symbols, Home a house Retrine draws to the Music app's measure (no chimney, rounded apex and foot, the door open at the foot), the tabs you added keep their
icons); Search's tab always titled Search (검색), as the Music app's is; Fade under the bar (on until switched off, applying straight away, the preview showing the
fade over a page's rows); the tabs, each with a
check circle that shows or hides it, its glyph (TabBar.x draws Spotify's own off their items on the bar, or with Apple symbols' symbol) and
the drag handle, a tap on a tab of the mod's own opening the Add a Tab sheet as Edit Tab, with Save and Remove
Tab; Add a tab and Use Spotify's tabs; and Split tabs. The redesign's split-list migration
(`SGRMigrateNavbarSplit` in `Redesigned/Navbar/NavbarLayout.m`) is one-way: downgrading to a build before
it loses split placement and custom split tabs. Spotify's own tabs keep their names and icons. Checked
in the simulator against harness/addtab/ (`navbar`, `edit`, `remove`, `links`) and the bar's icon, off and
hide switches against harness/tabbar/ (`navsettings`), Apple symbols against harness/tabbar/ (`symbols`).

## Localization

For `make build`, `make release` or `make install`, `NO_PLUGINS=1` (pipeline `--no-plugins`, CI `remove_plugins`, default off) skips building the Live Activity and Open in Retrine extensions and removes all PlugIns and .appex bundles before signing, including Spotify's widgets, Siri intents and notification service; leave it off to retain those features.

After injection and extension handling, `scripts/pipeline.sh` runs `scripts/patch-infoplist-ko.py` before signing to set the overlay's Korean motion prompt inside existing `ko*.lproj` directories only, preserving other entries and binary/text format; an app with no Korean localization is left unchanged with a warning, and the Connect/Cast prompt is added only when Spotify has no base or localized local-network wording. Live Activity requires both the Info.plist declaration and Retrine's bundled extension; without the extension, its switch is hidden and its runtime polling stays off even with a saved enabled preference.

Mod Settings and every page, sheet and alert it opens read their words from `Retrine.bundle`
(`tweak/layout/Library/Application Support/Retrine.bundle`): `en.lproj` and `ko.lproj`, each a `Localizable.strings`.
Theos puts the bundle in the .deb, so a jailbreak installs it under `/Library/Application Support` (or `/var/jb`), and
cyan copies every `.bundle` of a .deb into the app, so the IPA has it beside Spotify's own.
`Core/SGLocalize.h` has the one way in: `SGL(@"settings.player.title", @"Player")`, a key named for what the text means
and the English it stands for. Mod › Language chooses System (default), English or 한국어, independently of Spotify's
own text, and applies after Spotify restarts. `spotifyglass.language` stores an integer: absent or 0 means System,
1 means English, 2 means Korean; other values behave as System. The choice is read once per launch.
System keeps Spotify's language (the iPhone's, or the one set for Spotify in Settings);
one without a table, a missing bundle or key, and a translation whose format specifiers read differently from the
English all give the English, so System on an English iPhone sees exactly the text in the sources. `NSBundle` is left alone.
Pixie's companion uses `SAPL(@"settings.pixie.<what>", @"English")` in `NativeDownloads/src/`.
It resolves Retrine's `SGL` export at runtime and uses these same resources, falling back to
English when Retrine is not loaded. `scripts/check-strings.py` includes both source trees.

What is not translated: preference keys and `spotifyglass.*` values, logs, URLs, file names, Spotify's own words,
track and artist names, and the names Retrine, Spotify, AutoMix, AutoEq, Gemini and the like. A text that is also
stored or compared (a preset saved under "Before presets", the ad counters' labels, the equalizer preset a built-in
preset reads) stays English in code and is translated only where a row shows it. A text `SGL` reads must be made at
run time: a file-scope `static NSString *const` cannot call it, so such texts are functions or macros
(`SGRestartNote`, `SGRedesignedUIInfo`, `SGFakePremiumWarning`).

To add a text: write it as `SGL(@"settings.<page>.<what>", @"English")` (lowercase, dot-separated, `common.*` for
Cancel, OK, On, Off and the like), run `scripts/check-strings.py --sync` to write `en.lproj`, and add the key to
`ko.lproj` with the same `%@`/`%ld`/`%lu` specifiers (`%2$@` may reorder them). `scripts/check-strings.py` without
`--sync` fails on a key used for two texts, a table out of step with the sources, a missing or extra key, a specifier
mismatch, a table or Info.plist `plutil` refuses, and an untranslated text passed to a row, section, alert or label
on a settings page; a name that reads the same everywhere goes in `scripts/strings-allow.txt`. A harness that builds
a page using `SGL` compiles `Core/SGLocalize.m` too; harness/mod-settings/ copies the bundle into its app, so
`-AppleLanguages '(ko)'` on its launch line shows the Korean.

## Adding a feature

1. `make trees`, record the screen, read `trees/<screen>.txt` for the classes and frames.
2. Decide the layer (see Layers), then make `tweak/Sources/<Layer>/<Feature>/` with `<Feature>.h` declaring the switch key
   (`#define SGKey<Feature> @"spotifyglass.<feature>"`) and `UIViewController *SG<Feature>SettingsPage(void)`.
3. Add the hooks in `<Screen>.x`: `#import "Core/SGCore.h"` and the feature header, guard on the
   switch, use `SGGlassFor`/`SGGlassAt` + `SGShapeGlass` for glass and `SGStripBackgrounds` to clear
   Spotify's paint, and end with `%ctor { %init; SGRequireClasses(@[...]); }`, gated first on the layer's look
   (`SGNativeUI()` or `SGRedesignedUI()`) in Native/ and Redesigned/.
4. Add `<Feature>Settings.m` returning an `SGModPage` of `SGSection`s of `SGSwitchRow`/`SGHideRow`/
   `SGFlagRow`/`SGChoiceRow`/`SGSliderRow` (Settings/SGModPage.h), and put it on the page of the part of
   Spotify it changes in `App/Pages.m` or `App/ModSettings.x`. Every text it shows goes through `SGL` (see Localization).
5. `make install`. Log lines are prefixed `[spotifyglass]`. A FLEX build serves the visible screen's
   tree on the phone's port 8085, which `make trees` reaches over USB through iproxy.

A class Spotify has renamed shows up in the log as `class X not found, its hooks are inactive`;
declare the classes a feature needs in `Headers/` only when a hook calls into them by type.

Fluid's cost (Redesigned/Kit/SGRFluidGPU.m): the blur runs on a picture small enough that its Gaussian spans about
10 texels (a sixteenth of the drawable at the standard 160 pt, read through the cover's mipmaps), the display link
allows 120 Hz UI motion but submits at most 30 frames a second. Pausing, Reduce Motion, Low Power Mode
and serious heat stop the link after the mesh settles or a required still is drawn. Covered or backgrounded
fields submit nothing. The backing height grows in 256 pt steps; the visible rect places the copies within it.
There are two drawables and at most one pending off-main acquisition per layer. Outside a cover fade the
copy pass samples only the current cover.

Layout against the Music app's player (3x measurements, 402 x 874 pt): the footer row's middle 32 pt over the safe
area's bottom (kRowAboveSafeArea), the gaps from the artist to the bar, the bar to play and play to the volume row 35,
90 and 92 pt with the volume row 50 pt over the footer row (SGRPlayerVolumeToRow), previous and next 107 pt from play
(kSpreadShare 0.31) at 29.5 pt glyph size and play at 50 pt, the footer's lyrics and queue glyphs at 0.216 and 0.784 of
the width, and the volume row 5 pt past the side margins with a 4 pt glyph gap.

### Backdrop ink (Redesigned/Kit/SGRBackdropInk.h, in SGRRestyle.m)

The artist, the times and the audio quality badge are white ADDED to the backdrop (plusL), which goes nowhere over a
light one (a white cover's gray lower half). SGRBackdropInkSetSource (PlayerField.x) hands the player's field to a
reader that draws it 16 by 48 pixels four times a second (eight during a cover crossfade, once a second in Low Power Mode).
It runs only while the player is visible and active and weighs the cells behind each label's text; the field is read through the render server
(drawViewHierarchyInRect:), so Metal (Smooth fluid), the Animated clip and the lower shade count. The Music app adds a
fixed alpha of white to the backdrop (artist 0.48, times 0.265, badge 0.40 ink and 17/255 fill, footer glyphs 0.46),
so over a light backdrop its ink goes to white. In Spotify's player plusL does not reach the backdrop, although the
"ink tree" log lines (SGRRestyle.m) show no mask, rasterized layer or filter between the ink and the field on 9.2.0:
added that way, the times all but vanished over a light gray cover. So SGRInkFor and SGRInkPlainAlpha draw the ink
plain at the alpha that lands on the same value over the measured backdrop, alpha / (1 - luma), up to white over a light
backdrop as the Music app's goes (measured side by side over a light gray and a blue cover), and the alpha as it is with
no reading yet. The badge's fill (17/255) is drawn the same way, so its box stays as visible over a light backdrop as the Music app's (+19 of 255 over a 184 gray). Under Increase Contrast the times, the artist and the footer are drawn in the label colors. The
times (SGRTimeLabelStyle), the artist (PlayerTitle.x), the badge (PlayerControls.x, SGAudioQualitySetRedesignedInk)
and the footer (refreshFooterInk) take the ink again at each new reading; the badge uses the times' semibold.

The Fluid field's lower part follows the Music app's player (Mr. Blue Sky cover, measured: ochre at the title, olive at
the controls, near black at the foot): each blurred pixel is capped at 0.17 linear luminance (0.07 before), and the
shade over the bottom starts at 40% of the visible rect and grows along x^1.75 to a peak of 0.30 over a dark cover up to
0.62 over one at the ceiling (SGRFluid.m, kShade*), the peak read from the lower half of each blurred cover and
crossfaded with it, so white text keeps 4.5:1 whatever the cover. Not run on a device or simulator: checked by reading
the code paths only.
