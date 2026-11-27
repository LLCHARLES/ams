# Parity with spoti.pw 0.50.0

Every line of upstream's 0.22.0, 0.23.0-beta and 0.50.0 release notes, and where Retrine stands on it.
Each feature is written from its release note and public APIs, never from upstream's code after
`c790445`, which is PolyForm Strict.

Numbers are the line's position in the three release notes, in order. Status:

- **done**: built and on main. "Device" means it still needs a check on a phone inside Spotify.
- **in progress**: being built on its own branch
- **todo**: to build
- **n/a**: depends on upstream's account site, Plus or the upstream server, so Retrine leaves it out

A completeness audit on 2026-10-05 checked every done item below against its release note. Its gaps were
fixed in the commits that follow `956e65c`.

## EeveeSpotifyReincarnated (GPL-3)

| Source commits | Scoped port |
|---|---|
| `5f7b82e` | NativeDownloads offline-device manager: opaque device/cache selection tokens, current/other/unregistered-copy visibility and credential-free failure snapshots, adapted from `OfflineDeviceManager.m:147–251,275–306`. Confirmation, fresh-state checks and 9.1.90 routes/profile retained; companion-owned Korean/English strings. Fixture tests only; real-account registration/disable behavior remains unverified. Eevee's quality UI, 9.2.0 profile and other download features excluded. |
| `5f5c7ea`, `7a8c573` | Spotify 9.2 Spoof Premium: nebula account attributes and the signed-in remote config rewritten with Retrine's existing attribute and flag rules (crossfade included), their validators stripped, composed after Pixie's offline values. Version split by `CFBundleShortVersionString` ≥ 9.2 so 9.1.x keeps customize. Eevee's token bridge rename has no Retrine counterpart, and `AdsBaseImpl` was already covered. Harness only; on-device 9.2 queue, on-demand and crossfade unverified. |
| `43b9ca3`, `350aa15`, `d4daa49`; audit ideas `1010573`, `7a617a7`, `e2abe5a` | Terminal `/ads` and pre-send ad cancellation under Hide ads; six 9.1.90-verified service selectors with individual runtime guards; binary coverage audit with explicit DI/regulatory and missing-selector exemptions. `2a9d4ae` shuffle/full-song hooks and d4daa49 realtime/instrumentation/element/native-element hooks were not ported: no Objective-C `load` in 9.1.90. CTA cards keep `registerScrollProviderIn:`. Static proof and Foundation harnesses, not device verification. |
| `313ac37` | Native player: `ArtistAbout` hides with About the artist, and with all nine card switches hidden the player list's section headers (`Element_List.SupplementaryItemView`) collapse, never one holding the slider or controls. Eevee's `NowPlaying_ModesImpl` precedence fix has no Retrine counterpart (Retrine never excluded that wrapper). Simulator harness only. |
| `bde671b` | Clean links also in a Messages compose body (`MFMessageComposeViewController setBody:`, runtime lookup). Redesigned now playing bar masks non-square video artwork to its square artwork shape; the video view picker is unproven against Spotify's real bar video tree. |
| `cbc8a58` (UI) | Redesigned action row: Play turns into a 48 pt round button when the shown buttons don't fit, measured with the longer localized Play/Pause word; first placement outside animation; saved state as a 22 pt accent disc. The artist hold reads `PlayButtonView.isPlaying` (ivar resolved at runtime) instead of matching labels. Row-follows-anchor was already covered (the row lives inside Spotify's header). |
| `8c08046`, `cbc8a58` (Pixie) | Unused companion code removed (AlbumMetadata, EncodedAudio, cache research readers, runtime-testing helpers, the orphan `patch_offline.py`), exports kept as no-ops; AVAudioHooks and SourceGraph stay because Retrine uses them, and 9.1.x support stays. The removal-incomplete dialog shows library and offline totals and one reason per kind. Retrine has no server-sided download popup, so its runtime check was not needed. |
| `eddb1c2` | Opt-in “Save lyrics for Pixie downloads”: Pixie reports verified download completions, IDs and removals; Retrine fetches with its own providers into `LyricsStore` (`Shared/Lyrics/PixieLyricsQueue.m`, ledger `Library/Application Support/Retrine/PixieLyrics/queue.plist`). Eevee's native SQLite projection, viewer patch and stock offline card are not ported. Host fixtures only. |
| `b246006` | Nothing to port: Retrine never hooks `SPTAdsProductState`. Spotify 9.2.2 itself is a third supported version. |
| `8c08046` (9.2.2 target) | Pixie on Spotify 9.2.2: Eevee's native, trace and export sites and tail-padding caves in `NativeDownloads/targets/spotify-9.2.2.json` (Retrine schema, `provider_context_register` 28), manager field shift 136, and tail-padding acceptance in the setter and trace patchers. Every original-byte guard passes on the clean 9.2.2 IPA, and the setter's loads independently show the +0x80 shift. On an iPhone 13 Pro (iOS 27.2.1): track and album downloads, persistence across a restart, offline-mode playback, M4A and Ogg export, and deletion. Queue flags keep the unshifted base as upstream; they read `online=0` or invalid on 9.1.90, 9.2.0 and 9.2.2 alike. Downloads do not depend on them; the compatibility check for restoring key request mode 0 still does, so that restore stays refused. |
| `cb21e44` | Nothing to port: Turkish strings for Eevee's own screens. |
| `ddcdada` | Nothing to port: on 9.2.2 with the redesign, Spotify's offline mode banner sits under the glass tab bar and the now playing bar and tab bar do not overlap. |
| — | Sing-along on 9.2.2: Spotify removed the sing-along page and footer classes (`Lyrics_TextElementSingalongImpl`, `Lyrics_FullscreenSingalongPageImpl`) from the main binary and frameworks; only string keys remain, so the credit-tap hook has nothing to attach to. |

Not yet ported, checked against upstream `cb21e44` (2026-11-26):

| Source commits | To build | Before building |
|---|---|---|
| `f6a3403` | Pixie's local track quota from 1,000,000 to Spotify's 10,000: `SAPMinimumTrackLimit` in `NativeDownloads/src/Generated/OfflineLimits.h`, the 9.2.0 `SAPRestrictionTrampoline` bytes in `NativeRestrictionsPatch.h`, and `SAPPrepareNativeOffline` (`NativeOfflineAdapter.m`) setting the quota to exactly 10,000, lowering a higher value an older build left. Also drop `SAPInstallAVHooks()` from `PixieBootstrap.m` and add `SAPStartupReport` for a one-line startup state in the log. | Upstream gives no reason for the lower quota. Commit the uncommitted Pixie work first: `PixieManagerActions.m` and `PixieManagerSettings.m` are changed by both. Needs a download check on a phone, 9.1.90 and 9.2.0. |
| `838c5d5` | A new feature, not a version fix: download a local playlist over Wi-Fi, with a setting, the `offline` attribute forced while it is on and the playlist page's Download button kept. | Decide whether Retrine wants it; Spotify's `ActionView` class and the offlining helper's selector need checking in 9.1.90 and 9.2.0. |
| `5f5c7ea`, `7a8c573` (ported above) | On-device check of the 9.2.0 port: queue, add to queue, picking any track, seeking and crossfade on a free account with Spoof Premium. | A phone with Spotify 9.2.0. |

## Done

### Apple Music artwork

| # | Item |
|---|---|
| 1, 6 | Lock screen moving artwork: the Canvas, else Apple Music's animated cover |
| 15 | Album page plays the animated cover |
| 114 | Artist page shows Apple Music's artist logo |
| 77 | Low Data Mode switch on the Lock screen widget, Now playing and Albums & artists pages |
| 75 | Albums & artists page: animated covers, logos, a switch for each section the redesign hides |
| 107 | Switch with the star on the lock screen widget: the star takes the like slot and swaps Lyrics and Moving artwork, kept across launches (LockScreenStar.x) |

### Redesigned player artwork

| # | Item |
|---|---|
| 16, 18, 78 | Fluid and Animated artwork behind the player, edge to edge |
| 76, 121, 122 | Blur under the controls and behind the lyrics, the seam and the foot, on and off from the ⋯ menu |
| 106, 120 | Lock screen animates every song: its cover over a moving Fluid field |

### Lyrics

| # | Item |
|---|---|
| 36, 69, 109 | Lyrics take the whole player while untouched, a scroll hides the controls, the translate button goes with them |
| 32, 13 | Tap the cover to bring the player back, tap the progress bar to seek |
| 115 | Sung word glows the longer it is held |
| 111, 88, 124 | Landscape lyrics, with the meanings sheet |
| 94 | Translation: Musixmatch's community translations, or Gemini with your own key |
| 31, 138 | Spicy Lyrics with your own Developer Platform key |
| — | PetitLyrics: request and response knowledge from EeveeSpotifyReincarnated (GPL-3, `0d9feaa`); asynchronous matching and retained word timing in Retrine |
| 82, 93, 125, 60 | Lock screen lyrics as full-screen artwork, a clip per line, Still by default, no progress jump |

### Player and audio

| # | Item |
|---|---|
| 30, 23 | Pitch follows speed, on until turned off |
| 67 | Reverb slider in the player's ⋯ menu |
| 84 | Hold either side of the cover to play faster, under either look |
| 80, 83 | Presets, and AutoEq headphone corrections from AutoEq's public data |
| 27, 28, 29, 20, 103, 87, 55, 130, 53, 56 | Sing: model download, vocals slider, mic button, heat switch, iOS 18 floor |
| 81, 92 | Local files: Edit Info and lyrics |
| — | SponsorBlock for podcasts in both looks: opt-in tour switch, per-category Auto-skip / Ask / Show only / Off, native Skip and Undo snackbar, manual-seek and duration rules, local statistics, optional haptics, HTTPS server choice and progress-bar segment data. Report-driven; no polling, mute, submission or voting. Adapted from EeveeSpotifyReincarnated (GPL-3, `0d9feaa` / `51cb2dc`) and upstream Vitrine `d48c5f3b`. Real-Spotify playback validation outstanding. |

### System

| # | Item |
|---|---|
| 73, 74 | AirPods gestures: double nod likes, shake skips, learns your motion |
| 97 | Music Haptics through iOS in the background and on the lock screen |
| 90, 105 | Live Activity: the cover, its color, progress, centered and translated lyrics, and a small layout on Apple Watch and CarPlay from iOS 18 |
| 89 | Listening stats, with Spotify's export imported |
| 79, 98 | Apple Music red accent, one font for the whole app |
| 17 | Beta builds update to the next beta, then the release. Mod > Include betas lets a release build opt in |

### Round 2: player, pages, lyrics, settings

| # | Item |
|---|---|
| 85 | Sing's spatial voice with AirPods |
| 22, 123 | App icons: the picker, `icons/`, and Retrine's own icon |
| 42, 137 | Cover size fixes (the cover fills the lyric preview's room, under either look) |
| 112, 38 | Player page led by a showcase of the player, its background as a menu |
| 39, 40, 49, 61, 64, 136 | Player ⋯ opens the system menu, with speed, pitch, reverb and Animated artwork |
| 110 | Pinned ⋯ on playlist, album and artist pages opens the system menu |
| 104 | Hide Switch to video |
| 63 | Redesigned player for Spotify Free |
| 47 | Local files at another sample rate (device check outstanding) |
| 21, 33, 68, 132, 133 | Tab bar minimizes on scroll, the now playing bar in its row |
| 14, 113, 128, 44 | Add a tab sheet, own names and SF Symbol or Encore icons, Split tabs |
| 45, 59 | Fades under the tab bar |
| 41, 43, 34, 134 | Pages come in whole, cover color, owner pictures, section cards |
| 71, 119 | Album track rows drop the artist line that repeats the album's |
| 101 | Save turns into download on someone else's playlist, for accounts that can download |
| 62 | Playlist Mix can be turned off again |
| 24, 46, 50 | Connect discovery without the multicast entitlement |
| 108 | Lyrics page live preview and presets, a held word's letters rising in a wave |
| 48, 58, 118, 126 | Lyrics fixes |
| 57 | No freeze with EeveeSpotify's lyrics on |
| 95 | Mod Settings in the system Settings' style, Appearance on its own page |
| 70 | A dependent setting grays out instead of vanishing |
| 72 | What's new sheet (empty until the fork's first release) |
| 116, 117, 37 | Tour: glass logo, redesign below iOS 26 after a warning |
| 25, 26 | Say when EeveeSpotify is injected, or Spotify's version differs |
| 127, 135, 52 | Settings fixes |
| 66 | Less main-thread work for the flags Spotify reads at launch |

### Beta gaps (0.23.0-beta, described by behavior)

A separate describer compared upstream's beta branch with Retrine by behavior only (local notes, not in the
repo). Rounds 3 and 4 closed most of it: Spicy Lyrics' key, credit, pronunciations and back-off; the paused cover;
the clip's pause, Spotify's video, late Canvas, next-track fetch and give-up; the lyrics left alone; tap to seek;
the lock screen's Canvas shape, late Canvas and Canvas service; the lit custom tab; the update check; EeveeSpotify
by class; the app icon error; Signed until; two output chains; and Karaoke's memory, heat, hardware, hysteresis
and download. The rest, on `fix/beta-gaps`:

| Item | Commit |
|---|---|
| The player's clip gives way to Fluid under Reduce Motion and Low Power Mode, and goes at once when the track changes unseen | `992f379` |
| The player's clip is dimmed by its brightness, 4.5:1 (7:1 with Increase Contrast) for white text | `992f379` |
| A failed clip download is tried again once | `e0ee995` |
| Apple Music's catalog: 10 minutes alone after a 403 or 429, searched without the album's edition | `54eb39b` |
| A settings section whose rows all hide takes its heading and note; the ticker follows rows, sliders and menus | `08a9eeb` |
| Below iOS 26 the Lock screen page says Full-screen artwork needs iOS 26 | `be1a478` |
| The Mod Settings row comes back when Spotify empties its settings list or drawer | `8f9f839` |
| The install warning waits for Spotify in front; an unreadable version is not a wrong one | `e26e8a5` |
| Lyrics are looked up for the next track in the background | `28e9e2e` |
| Speed and pitch: no second mixer pull after a failed render, a silent mixer buffer zeroed | `b7bb9d7` |

Still open from the beta gaps: Fluid artwork's settings (SGRFluid.m is being changed elsewhere); the lyrics
opening for Karaoke on a song without lyrics; Karaoke's background download, output latency, interruption and
route handling, seeks and read-ahead limit (the Karaoke rewrite owns them). A change to or from Lyrics on the lock screen
now applies at once (LyricsArtwork.x), as does the star's swap. Deliberate differences: the Off default for the lock screen artwork, the lock
screen page's flag rows, the Reinvented Free player mode turned off, the title kept over the lyrics left alone.
Not gaps: Hide social proof (both flags ship off), recvmsg (neither Spotify nor SpotifyShared imports it in 9.1.90 or 9.2.0).

### From upstream pull requests

Rebuilt from behavior-only descriptions; each commit credits the PR's author.

| PR | Item |
|---|---|
| 165, 192 | QQ Music and KuGou lyrics sources; Thai, Lao, Burmese and Khmer lines wrap |
| 153 | Imported LRC files, a native-look lyrics page for local files, local covers |
| 179, 184 | A scrub never closes the player; lyrics left alone keep the title and scroll |
| 195 | The Live Activity ends when Spotify is swiped away |
| 200 | Music Haptics: None, Generated or Native iOS, by exact ISRC |
| 120, 99 | Accent preset menu with a swatch; custom .ttf and .otf fonts |
| 138 | The now playing bar's glass stays on the card in a Jam |
| 180, 187, 134 | Clean shared links, dead code removed, Mix row fix |

### Upstream 1.0.0-beta.1 and 0.51.0 (described by behavior)

A describer read the two release notes, the open issues and upstream's site (behavior only, no code); the notes
give no numbers, so the limits below are Retrine's own.

| Item | Where Retrine stands |
|---|---|
| The player grows out of the mini player and follows the finger | Already done (PlayerMorph.x) |
| Square animated covers play inside the cover | Done (PlayerMotion.x); device check outstanding |
| Mod Settings searchable | Done: search on the Mod Settings page, two pages deep, read a page at a time, with keywords and recent places (SGSettingsSearch.m, SGSettingsIndex.m) |
| KuGou and QQ Music lyrics, pronunciation for most scripts | Already done (QQMusic.m, KuGou.m, Romanise.m, Pronunciation by AI) |
| Lyrics kept for offline listening | Done (LyricsStore.m): 1000 tracks, 30 MB, oldest first |
| Your own photo or pure black behind the player | Done (PlayerBackdrop.m); device check outstanding |
| An automatic accent colour, the accent following the song | Already done (Follow the cover) |
| A volume slider in the player; the DJ's redesigned player; tinted Home shortcuts | Already done |
| Album, artist and playlist pages like the Music app; more Appearance options; lock screen styles | Open: the notes and site name them without a behavior to build from |
| Web Player, Siri and Shortcuts, settings backup, Workshop, sign-in | Leave out: Plus, upstream's account or its server |

### Upstream 1.0.0-beta.4 (described by behavior)

The first batch taken from beta.4, described by behavior only and built against Retrine's own code, and the second
round under it: per-song speed and pitch, the player's line under the cover, album notes, artist artwork, the player
refinements and the page previews.

| Item | Where Retrine stands |
|---|---|
| Lyrics pronunciation in Hangul: Japanese and Chinese lines read in Hangul, every other script in Latin | Done (Romanise.m): offline kana and pinyin to Hangul, under Pronunciation alphabet; harness/hangul-pronunciation/ |
| Teaching gestures checked against 20 seconds of ordinary movement, a threshold stored only if it never fires there | Done (HeadGesturesTeach.m, SGHeadEvaluate): the harness covers rejection, a kept previous threshold and Cancel |
| Hardware keyboard: ⌘↑ / ⌘↓ volume, ⌘1 / ⌘2 / ⌘3 Home, Search and Library, ⌘F Search with its field focused, Esc and ⌘W the player closed | Done (Shared/Keyboard, Core/SGTopController.h); harness/keyboard-commands/ and harness/keyboard-top-controller/; the keys themselves are a device check |
| Hold a lyrics line for Copy, Share and, where it has one, Meaning | Done (Redesigned/Lyrics/SGRKaraokeView.m); harness/lyrics-hold/; the press itself is a device check |
| Own lyrics as TTML, LRC or plain text, pasted too, the same 1 MB and content rules, replaced files deleted at the next launch | Shared import page links any song URI; only local files also match by name. The shared lyrics engine checks the link, then local ID3/FLAC/M4A tags, before ordinary lyrics. `harness/local-files/`, `harness/lyrics-sources/` |
| Advance work (the next track's lyrics and artwork) stands down on Low Power Mode, serious or critical heat, an unavailable network, Low Data Mode and the Load ahead switch | Done (Core/SGOptionalWork.h, asked by KaraokeSource.x's track watcher and SGMotionFollower.m's fetch ahead, both re-aimed when the up-next track changes) |
| With shuffle and repeat both hidden, previous and next move out to where the Music app keeps them | Done (Redesigned/Player/PlayerControls.x); a device check on a narrow and a wide iPhone is outstanding |
| Recent accent colors, up to 8, each look keeping its own | Done (Native/Appearance/AccentHistory.m, Redesigned/Kit/SGRAccentHistory.m); harness/appearance-page/ (rows) |
| Album play counts Off, In the row or In menu, the switch it replaced migrated | Done (Redesigned/Album/AlbumPlaysPlace.m, AlbumPlaysMenu.x); harness/ui-refinements/; the sheet in Spotify itself is a device check |
| Speed, pitch, pitch-follow and reverb kept per song, and the speed menu localized | Done (Shared/Player/SpeedPitchSongs.m, SpeedPitchMenu.x, SpeedPitchEvents.h): Keep for This Song on the menu, the newest 200 records, the pre-keep values restored for every other song; harness/song-audio/ (two processes, so the relaunch is real); the menu itself is a device check |
| The line being sung under the cover: a long line shrinks and then splits into portions of whole words, read on a one-shot timer aimed at the next portion or line, and standing down where Spotify's own lyric preview shows | Done (Redesigned/Player/PlayerLyricFit.m, PlayerLyricLine.x); harness/player-lyric-line/ |
| Album editorial notes from Apple Music's catalog, under Play, under the tracks or off | Done (Redesigned/Album/AlbumNotes.m, AlbumSections.x; SGMotionCatalog.m's SGMotionAlbumNotesIn): exact artist, edition, count, year and rating only; harness/album-notes/ |
| Artist page: Apple Music's artist photo and animated artist artwork | Done (Redesigned/Artist/ArtistArtwork.m, ArtistHeader.x; SGMotionArtistMatch): two agreeing releases and one namesake only; harness/artist-artwork/ |
| Hold Play to shuffle the displayed artist | Done (Redesigned/Artist/ArtistHeader.x, ArtistShuffleHold.h); Spotify artist-context playback checked on 9.1.90 and 9.2.0. |
| The player's time digits rolling only the characters that changed, and the add button as a star | Done (Redesigned/Kit/SGRRefinements.m, SGRRollingDigits.m, SGRPlainCheck.x, PlayerControls.x, PlayerSettings.m); harness/player-refinements/ |
| A live preview at the top of the redesign's page settings, following the switches as they are flipped | Done (Redesigned/Kit/SGRPagePreview.m in the Playlists, Home, Search, Albums and Artists pages); harness/page-previews/ |

Judged equal, already there, or not taken, from the same beta.4 round:

| Item | Why |
|---|---|
| Lyric-layer ordering, the two-column lyrics and the press highlight | Already in Retrine: the lines sung over each other are lit together and the stack moves on in order (Redesigned/Lyrics), and a press on a line opens the edit menu (harness/lyrics-hold/) |
| Glass on the full-height Queue and Connect sheets | Tried and dropped: on the iPhone 13 Pro (iOS 27.2) UIKit's `_nonLargeBackground` is nil for Spotify's sheet, so there was no material to carry to the large detent, and Spotify paints its own content opaque (#1F1F1F) there over a #1C1C1E drop shadow view; kept as a follow-up |
| A translucent download badge | Not built: the download state is not readable from Objective-C, so only a color heuristic was possible, and a wrong badge is worse than none |
| The iPad full-screen player | Not adopted: no iPad was available to verify it |

Judged not better, or not ours to take:

| Item | Why |
|---|---|
| Autoplay shuffle | Unsolved, and no answer of ours either: on 9.1.90 autoplay continuation reports `{autoplay}`, and despite the serialized restriction override the core answers Code=101 and leaves shuffle and repeat as Spotify set them (harness/radio-modes/README.md) |
| Rewriting an MP3's metadata tags | Left out for its data-loss risk: it edits the user's own files, and the gain is cosmetic |
| Account, Plus, server and telemetry features | Out of scope, as in Leave out: no account, no paid tier, no upstream server |

### Upstream 1.0.0-beta.4, the whole feature set (compared with Retrine's code)

The earlier rounds took what was new in beta.4 and judged the older features from Retrine's documentation. This round
compared the whole feature set with Retrine's code at the logic level (upstream's side by static reading only, behavior
described and no code taken): edge cases, limits, retries, caching and where work runs.

| Item | Where Retrine stands |
|---|---|
| Artwork transfers owned by their consumers: a request hands back a ticket, a shared transfer stops when its last consumer leaves unless more than half of a known size is in, and only transient failures (timeout, lost connection, DNS, HTTP 408, 429, 5xx) are tried again | Done (Shared/AnimatedArtwork/SGMotionTicket.*, SGMotionStore.m, MotionSources.m, SGMotionCatalog.m, SGMotionFollower.m); harness/motion/ |
| A change of the up-next track re-targets the next track's artwork and lyric prefetch | Done (Shared/Player/PlayerState.x's SGPlayerUpNextIn and playerUpNextDidChange:, Shared/Lyrics/KaraokeSource.x, SGMotionFollower.m, which cancels the old target's artwork fetch) |
| Load ahead, for advance work only | Done (Core/SGOptionalWork.h, AnimatedArtworkSettings.m's SGLoadAheadRow, App/Pages.m): `spotifyglass.loadAhead`, on, on the Player page; the current track is never touched |
| Spotify's auth headers captured only from https `spclient.wg.spotify.com`, and one metadata transport for them | Done (Shared/Lyrics/KaraokeSource.x's rememberHeaders, Shared/SpotifyMetadata/): ephemeral session, no redirect, 2 MiB |
| QQ Music word timing (QRC) | Done (Shared/LyricsSources/QQMusic.m): 1 MiB bound, parsed off the main queue, plain LRC when the QRC cannot be read or a clock is malformed; harness/lyrics-sources/ |
| Lyric source matching: an artist name under four characters never matched inside another name, joined credits with aliases, a NetEase title check, JSON parsed off the main queue | Done (SongMatch.m's SGLyricsSameArtist, NetEase.m, LyricsSources.m's SGLyricsGetJSONTransform, KuGou.m, QQMusic.m); harness/lyrics-sources/ |
| Generated pronunciation as timed words anchored to source ranges, in the pronunciation role; reading segments of 4,000 UTF-16 units that never split a grapheme | Done (Shared/Lyrics/Romanise.m's SGLyricsPrepareExtras, Redesigned/Lyrics/SGRKaraokeView.m); harness/hangul-pronunciation/, harness/lyrics/ |
| Meanings matched and furigana prepared on worker queues, with bounded shared results | Done (Shared/LyricsMeanings/Meanings.m, Romanise.m, SGRKaraokeView.m) |
| Translation in the meaning sheet, on a tap | Done (Redesigned/Lyrics/MeaningSheet.m, Shared/LyricsTranslation/TextTranslation.m, ProseSegments.m): the explanation and its quote go only to the configured service, in paragraph- and sentence-bounded segments sent one after another (16 at most a tap), and a segment that fails, stops short or is cut fails the whole; harness/meaning-translate/ |
| Settings search read a page at a time, with keywords and recent places | Done (Settings/SGSettingsIndex.*, SGSettingsSearch.m, SGModPage.* searchKeywords and searchIdentifier, the main page's keywords in App/ModSettings.x and Pages.m): the six newest places under `spotifyglass.search.recents`, stored by stable setting names, never by title or text typed; harness/settings-search/ |
| Player: header glass, Fluid grain, Music app icons switches | Done (Redesigned/Player/PlayerHeader.x, PlayerFooter.x, DJPlayer.x, PlayerSettings.m; Kit/SGRFluid.m, SGRFluidGPU.m): `spotifyglass.redesign.player.headerGlass` (on), `spotifyglass.redesign.fluid.grain` (0 to 200 %, 100, Smooth only), `spotifyglass.redesign.player.musicIcons` (on); the open player follows them at once; harness/player/ |
| Animated artwork's clip recovery | Done (Redesigned/Player/PlayerMotion.x): a clip that has drawn and then fails is played again from its local file, 3 rebuilds, then given up; harness/fluid-clip/ |
| Automatic accent | Done (Redesigned/Kit/SGRAccent.x, SGRAccentContext.m, Player/PlayerCoverAccent.x): Accent source, `spotifyglass.redesign.accent.auto`, Picked until switched; the page in front, then the cover; recolors by token provenance, never by a similar hue; harness/appearance-accent/ |
| Explicit badge hiding, in each look | Done (Native/Appearance/ExplicitBadge.x, Redesigned/Kit/SGRExplicitBadge.x): `spotifyglass.hideExplicit` and `spotifyglass.redesign.hideExplicit`, off; a transparent mask on Spotify's own badge views; harness/ui-refinements/ |
| Glass material, tint and touch response in the redesign | Done (Redesigned/Kit/SGRGlass.m, SGRAppearanceSettings.m; the glass tab bar, the now playing card and the bars' stand-ins through SGRGlassEffect/SGRGlassRestyle): `spotifyglass.redesign.glass.material` (Regular or Clear), `spotifyglass.redesign.glass.tint` (None, Light or Dark) and `spotifyglass.redesign.glass.interactive` (on), read as the redesign starts; iOS 26 glass only, Reduce Transparency still solid, the control always takes the touch, including Home's Filter beside its pill's glass (SGRGlassBacks); harness/appearance-page/, harness/glass-choices/, harness/tabbar/glass-check.py. Also the search field; the full screen lyrics page keeps its own glass under the words. Checked on an iPhone 13 Pro (9.2.0): Clear + Dark on the tab bar, the now playing bar and the search field, controls working with touch response off |
| A saved song shown as a dot | Done (Redesigned/Kit/SGRPlainCheck.x, SGRRefinements.m): Saved mark, `spotifyglass.redesign.savedMark`, Spotify's, Plain checkmark or Dot, in Plain checkmark's place, carrying `spotifyglass.redesign.plainCheck` over while unset and never writing it; harness/appearance-page/, harness/player-refinements/, harness/glass-choices/. Checked on an iPhone 13 Pro (9.2.0): the dot on saved album and search rows, unsaved rows keeping Spotify's plus |
| Separate album and playlist cover settings (the global Full bleed row removed) | Done (Redesigned/Kit/SGRHeaderInfo.m's SGRPageFullCover, Album/AlbumSettings.m, Playlist/PlaylistSettings.m): Cover layout, Card or Full screen, `spotifyglass.redesign.album.fullCover` and `spotifyglass.redesign.playlist.fullCover`, Full screen unless set; the old `spotifyglass.redesign.fullBleedCovers` is carried over once and kept; harness/album/, harness/page-previews/ |
| Compact library and the Library settings page | Done (Redesigned/Library/LibraryMenu.m, LibrarySettings.m, LibraryHeader.x): `spotifyglass.redesign.library.hideChips`, off; a menu of Spotify's own sort, list or grid and clear filter, the chips staying where the menu cannot reach them; a preview leads the page; harness/library/ |
| Tab bar fade switch | Done (Redesigned/Navbar/TabBar.x, NavbarSettings.m): `spotifyglass.redesign.navbar.fade`, on, with the fade in the page's preview; harness/tabbar/ |
| Spotify plays as a play count source | Done (Redesigned/Album/AlbumSpotifyCounts.*, AlbumPlaysText.m, AlbumRows.x, Shared/SpotifyMetadata/): `spotifyglass.redesign.album.playCounts.source`, Your plays unless set; one JSON GET and one batched POST per album, no automatic retry, 500 tracks an album, 64 albums and 2 MiB kept, 24 hours (five minutes after a failure); an unknown count is nothing, never 0; harness/album-counts/ |
| Per-disc album track numbers | Done (Redesigned/Album/AlbumRows.x, AlbumSpotifyCounts.m): Track numbers, `spotifyglass.redesign.album.trackNumbers`, off; each row's position within its disc from Spotify's album metadata, matched by the row's track URI (a title only when unique on the album), never by index; harness/album/, harness/album-counts/. Checked on an iPhone 13 Pro (9.2.0): disc 2 restarting at 1, no overlap with or without in-row plays, rows on screen numbered once the album's metadata arrives |

Judged equal, already there, or not taken, from the same round:

| Item | Why |
|---|---|
| Search short-video carousels | Already in Retrine: the redesign's watch feed carousels collapse with the Search page's watch feed switch (on) and come back when it is off (Redesigned/Search/SearchSections.x) |
| The iPad full-screen player and the beside-cover lyrics opt-out | Not adopted: no iPad to verify them |
| Writing an MP3's metadata tags | Left out: data loss in the user's own files |
| A translucent download badge | Not built: there is no reliable download state to read |
| Visualizer Auto and shuffle | Not taken: they cross paid-gated paths |
| Car suppression | Not taken: upstream's behavior is untraced, so there is nothing to build from |
| Glass on the full-height sheets | Unchanged from the last round (see the Queue and Connect row above) |
| Lock screen styles and the clock | Not taken: they are interleaved with Plus |
| Home snapshot replay, and the Library settings button in the header | Unresolved: upstream's behavior was not traced to the end |

Debt from this round: none left; the follow-up sweep fixed every item (ruby over wrapped compounds, the offline
store's provider translations and credits, the protobuf field budget, the previews' right to left and the Library
title row's sizes).

### Upstream 1.0.0-beta.5 (described by behavior)

What beta.5 adds over beta.4, compared with Retrine's code and built from behavior specs only.

| Item | Where Retrine stands |
|---|---|
| The artist under the title in the minimized mini player | Done (Redesigned/NowPlayingBar/NowPlayingBar.x): `spotifyglass.redesign.inlinePlayer.artist`, off; only when both lines fit with 6 pt to spare; harness/now-playing-bar/ |
| Clear downloaded covers and artist photos | Done (Shared/AnimatedArtwork/SGMotionStore.m, SGMotionCatalog.m, AnimatedArtworkSettings.m): the store's own clips and the album answers only, leased clips kept, pre-clear work keeps and starts nothing; harness/artwork-clear/ |
| Podcasts and audiobooks hidden on Home | Done for Home's filter chips (Redesigned/Home/HomeHeader.x): `spotifyglass.redesign.home.hidePodcasts`, shown unless set; harness/home-podcasts/. Search's category cards are deferred: rewriting the two-column grid's layout attributes overlapped on scroll, so they wait for a traced data-source boundary |
| A full-screen cover when a song has no clip | Done (Redesigned/Player/PlayerMotion.x): `spotifyglass.redesign.player.animatedStill`, off, with a top scrim; harness/player/ `still` |
| Page headers: covers blur and dim on scroll, the title faded under the top bar, a round artist Play, Play in the accent | Done (Redesigned/Kit/SGRHeroVeil.m, SGRHeaderInfo.m): `spotifyglass.redesign.hero.scrollVeil` and `.artist.roundPlay`, off; `spotifyglass.redesign.playInPageColour`, on; harness/album/veil-check.sh |
| The Music app's player close | Done, off by default (Redesigned/Player/PlayerMorph.x): `spotifyglass.redesign.player.musicClose` stages the close inside 9.1.90's own CompactOverlayTransition animator (traced on a phone: tap, drag and cancel), lands on the measured mini player, shapes a release by its velocity and leaves cancellation to Spotify; an owner without those parts keeps Spotify's timing and the old path; harness/morph/check.sh |
| Ambient sounds | Not taken: the recordings come from upstream's server, and the user chose to leave the feature out |

### Upstream 1.0.0-beta.6 (described by behavior)

What beta.6 adds over beta.5, compared with Retrine's code and built from behavior specs only. Every new switch is off.

| Item | Where Retrine stands |
|---|---|
| Album pages coloured from what the cover is, the cover sharp under the title | Done (Redesigned/Kit/SGRCoverRead.m, Album/AlbumHeader.x): Picture-aware cover, `spotifyglass.redesign.album.adaptiveCover`; harness/album/cover-check.sh |
| Artist pages coloured from the photo with faces left out | Done for the colour (Kit/SGRCoverRead.m, Artist/ArtistHeader.x): `spotifyglass.redesign.artist.adaptivePhoto`. Upstream's extension under the photo is not taken: Retrine's photo fills the hero |
| Round artist Play with its triangle cut out, white or in the accent | Done (Kit/SGRActionRow.m, SGRHeaderInfo.m): `spotifyglass.redesign.artist.cutOutPlay`, `spotifyglass.redesign.accentPlay`; Play in the page's color is kept for every other Play; Round artist Play moved to the Artists page; harness/artist/cutout-check.sh |
| Monthly listeners in About | Done (Artist/ArtistSections.x): `spotifyglass.redesign.artist.listenersInAbout` omits the header line from the first layout unless Hide About is on. Spotify's About card and page already show the count (seen on a 9.1.90 phone) and are unchanged by this switch; harness/artist/listeners-check.py |
| A pinned whole-player preview, one Song without a clip choice, Buttons chips | Done (Redesigned/Player/PlayerSettings.m): over the existing keys; the preview shows the current song, not demo songs; harness/player/settings-check.sh |
| Music app icons folded into Music app style | Not taken: Retrine keeps the two switches apart |
| Visualizer shaders, motion presets | Not taken: paid upstream |

### Upstream 1.0.0 (described by behavior)

What 1.0.0 adds over beta.6, compared with Retrine's code and built from behavior specs only. Every new switch keeps
today's look until it is changed.

| Item | Where Retrine stands |
|---|---|
| Album artist picture, a choice and up to three faces | Done (Redesigned/Kit/SGRHeaderInfo.m, Album/AlbumHeader.x): `spotifyglass.redesign.album.artistPicture`, on; the faces come from Spotify's own artist line, nothing fetched; harness/album/faces-more-check.sh |
| Album track rows' ⋯ in the page color | Done (Redesigned/Album/AlbumRows.x): no switch; a glyph with its color baked in gets a layer masked by its own picture; harness/album/faces-more-check.sh |
| Transitions in the progress bar and the queue, artwork that moves with the mix | Done for Spotify's own Crossfade and Automix (Shared/AutoMix/SGTransitionFacts.m, Redesigned/Player/PlayerMix.x, PlayerQueue.m): `spotifyglass.automix.show-progress`, `.show-queue`, `.artwork`, off. Spotify's Automix gives only its cue points, so its pairs are named in the queue but get no segment or artwork move; harness/automix/, harness/player/automix-check.sh |
| A preview of the transition on the AutoMix page | Done (Shared/AutoMix/AutoMixPreview.m): drawn from the switch, style and Blend length |
| Apple Music's AutoMix planning the transitions | Not taken: on a 9.1.90 phone Spotify accepted a queue write but dropped the transition fields written into it and played its own timing, so a plan has no way into the player |
| Spotify's DJ loops, spinbacks and stops; Apple's curve effects | Not taken: both only reach the player through the same written transitions |
| iPhone Duo layout | Not taken: no device or simulator to check it on, and it reworks the tab bar every phone uses |
| The album blur running to the foot | Not taken: Retrine's 40 pt ramp was measured against the scanner-border seam |
| Shake to report | Not taken: upstream telemetry |

### Upstream 1.0.1 and 1.1.0-beta.1 (described by behavior)

1.0.1 showed no user-facing change beyond its version. What 1.1.0-beta.1 adds, built from behavior specs only:

| Item | Where Retrine stands |
|---|---|
| Lyric line views built on a time budget | Done (Redesigned/Lyrics/SGRKaraokeView.m, `showLinesInSight`): four a pass as before, none after the first once 1 ms is spent, the next pass resuming; harness/lyrics/model-budget-check.inc |
| Backing vocals in machine-made TTML | Done (Shared/LyricsSources/SGTTML.m): with `byModel="true"` on the root, a line's parenthesised runs become its backing row; explicit x-bg wins; harness/lyrics/model-budget-check.inc |
| Comparative charts in listening stats | Done (Shared/ListeningStats/SGTopCharts.m, TopChartPage.m): each top list's heading opens up to 50 ranked entries with moves, NEW, runs in the top 5, played and discovered counts; harness/listening-stats/ |
| A year's recap | Done (Shared/ListeningStats/SGRecap.m, RecapStory.m): free and on the phone, seven shareable cards for a year with 30 days with plays, announced from 1 to 14 January in Retrine Settings by default; harness/listening-stats/ |
| Local artist, album and folder pages | Done (Shared/LocalFiles/LocalMusicPages.m, LocalMusicPlayback.m): for the files Retrine imported; Play, Shuffle, Play Next and Add to Queue on Spotify 9.1.90 for files Spotify has been seen playing, browse only elsewhere; several songs at once to Play Next left out, Spotify answering Conflict to the second; harness/local-files/pages-check.m |
| Weekly and monthly recaps | Not taken: upstream's paid tier |
| Animated cover geometry, edition-safe animated covers, header creator fades, profile avatar, DJ visualization, AutoMix changes | Not taken: the behavior could not be read completely enough to specify |

### Chroma 1.1.0-beta.2 (clean-room behavior)

| Item | Where Retrine stands |
|---|---|
| AI-content badges | Labs: AI badges and dependent Likely AI badges force only Spotify's specified classification flags; both default off, unlike Chroma, leaving Spotify's values alone until enabled. |
| Karaoke first placement | Newly measured layouts compute the current sung/active state before placement; demo/plain lyrics and invalid positions are excluded, with no new timer. |
| Hide playlist recommendations | Redesign → Playlists → Recommended songs; off by default (Chroma: on), applies when the playlist reopens. |
| Playlist header details | Redesigned → Playlists: creator and length, creator picture, and description; all shown unless switched off. |
| Hide the scrolled page title | Redesign → Appearance → Page title when scrolled; shown by default (Chroma hides it), live. |
| Inline Up Next, Track Info, page snapshots, search-ahead warming, cover-look backgrounds, stand-in mask reveal | Not taken: the behavior could not be read completely enough to specify, or it adds unannounced Spotify traffic |

### Chroma 1.1.0-beta.3 (clean-room behavior)

| Item | Where Retrine stands |
|---|---|
| Hide the playback-context title, SF Symbols for Spotify's tabs, a separate tweak-language page | Already in Retrine (Redesigned/Player/PlayerHeader.x, Redesigned/Navbar/TabBar.x, App/About/AboutSettings.m), defaults unchanged |
| iPad: lyrics or queue beside the artwork, mini-player capsule controls, side-by-side album and playlist headers | Already in Retrine (see the iPad entries in docs/tweaks.md) |
| Spotify 9.1.98 | Not taken: only the target version changed in what could be read; supporting it needs Retrine's own Spotify inspection and regression runs on every supported build |
| Nine more interface languages, artwork-origin page transitions, reset to defaults, Live Activity countdown wording | Not taken: coverage, timings or resulting state could not be read; Retrine's reset stays stock-off and its countdown already shows |

### Upstream Plus features, Retrine's own versions (described by behavior)

Retrine has no paid tier, so where a Plus feature could be built from its behavior alone it now has one of its own,
with no gate and nothing from upstream's code, server or content.

| Item | Where Retrine stands |
|---|---|
| Visualizer when there's no clip, shuffle styles, ignore heat | Done (Redesigned/Player/PlayerMotion.x, PlayerVisualiser.m): `spotifyglass.redesign.player.animatedVisualizer`, `spotifyglass.visualizer.shuffle`, `.ignoreHeat`, all off; the full-screen cover and the Visualizer fallback exclude each other; harness/player/ `autoviz`, `shuffle`, `heat` |
| Hold edge speed | Done (Shared/Gestures/GestureHold.m): `spotifyglass.gestures.hold`, on, and `.hold.speed`, 1.5×, 2× or 3×; the speed from before the hold comes back, not 1×; harness/gesture-hold/ |
| Lock screen lyric styles Messages and Vinyl | Done (Shared/LockScreenLyrics/SGLyricsClip.m): two more Layout choices, kept between 17% and 65% of the screen; harness/lyrics-clip/ |
| Suggested tags for local files | Done as Find Info (Shared/LocalFiles/LocalInfoLookup.m, LocalInfoReview.m): iTunes Search, reviewed field by field, saved only through Retrine's overlay; the audio file is never written, unlike upstream's tag rewriting; harness/local-files/ |
| Effects preset per output, headphone form filter | Done (Shared/AudioEffects/AutoEq.m): a baseline stored before applying and restored only while unchanged, both directions crash-safe; harness/audio-effects/ `route`, harness/autoeq/ |
| Liveprog CPU budget | Done (Shared/AudioEffects/SGDSPEngine.m): half of real time, a click-free bypass and a quarantine, a 2 s start deadline; harness/liveprog-guard/ |
| Audio import | Done (Shared/LocalFiles/LocalAudioImport.m, LocalAudioPage.m): Player › Local files copies picked audio into Documents, which Spotify's own Local Files page scans and plays (seen on a 9.1.90 phone), never overwriting; Imported files lists and deletes only what Retrine copied, checked by file identity, never recursively; harness/local-files/audio.m |
| Your Files page, folders, offline animated covers for local albums | Not built yet: a phone trace showed Spotify's Local Files rows start playback by a path outside SPTEsperantoPlayer's play methods, so Retrine's own page has no proven command; moving files risks the user's data |
| AutoMix per context and its info line | Not built yet: when Spotify reads the transition preferences must be shown on a phone first; upstream's rewriting of Spotify's remote-config files is not taken |
| Poster and Cut lyric visualizers | Done (Redesigned/Player/PlayerLyricStages.m, PlayerVisualiser.m): layers and text, no Metal; the halftone made once per artwork off the main queue; parameters in `spotifyglass.visualizer.params`, rows only for the chosen style; harness/player-visualiser/ |
| Lock screen style templates with a clock, lyrics shaders | Not taken: a template language for little gain over iOS's own clock; lyrics shaders exist only as downloads from upstream |
| DSP suite, AutoEq, AutoMix styles | Already in Retrine (Shared/AudioEffects, Shared/AutoMix) |
| Bundled DDC and EEL example files | Not taken: each file's source and license would have to be checked first |

### Ported from GPL-3 forks

| Source | Item | Where Retrine stands |
|---|---|---|
| SUB2-8687 `3bf218e9` / `8191c859` | Korean UI localization and permission prompts; optional extension removal | Remaining English UI literals use SGL with unchanged English, Korean wording is revised, and the IPA pipeline updates Korean motion permission text without dropping Spotify's other entries. `NO_PLUGINS=1` optionally removes app extensions; default builds retain them. No WireGuard or CI cache changes included. |
| kes158 `efb9dd02` / `1fbd7d15` / `9f44ee7c` (`codex/spotify-9.1.90-wireguard`); SUB2-8687 `3bf218e9` / `8191c859` | App-local WireGuard / proxy | Included in IPA builds by default; off until a profile is imported or a proxy saved, enabled and the app restarted (docs/wireguard.md). `WIREGUARD=0` excludes it and drops enforcement. Hardened after security review: armed fail-closed state on the inspected paths, slot-complete import accounting, build and Mach-O UUID admission, initializer and ABI checks, engine-side destination validation. The forks' in-place SOCKS handshake on caller sockets is not taken; remote BSD TCP/UDP is denied while armed. Not a leak-proof or device-wide VPN. No CI tweak cache. |
| jadetheda `9c3c3f5` (`feat/connect-volume`); hardware follow-ups `7fd8ee2` / `6e71450`, `43f7b07` / `8bcaa88` not ported | Connect volume bar only | Adapted in Redesigned/Player/PlayerConnectVolume.x and PlayerVolume.m: active remote state and volume API, return/argument signature gating, current-service reads rather than stale callback values. Hardware buttons stay Spotify's: local-volume deltas fail at phone limits, change local volume during remote playback, and suppression can double-handle off-main callbacks. No forwarding or suppression. Local MPVolumeView and Native retained; real Connect delivery still needs hardware. |
| michaelmelita1 `29ace72` (volume portion only) | Volume bar Vibrations | Shared/Haptics/SGFeedback.m attaches sixteen-step ticks, firmer ends and grab/release feedback to local and Connect sliders. Existing Controls default and strength, no additional switch; no Top picks or replacement player port. |
| upstream `e033415` (#147, volume portion only) | Volume stays hidden while lyrics are alone | Replaced Retrine's partial fade-set guard with fitting-row registration/removal in PlayerLyrics.x and PlayerVolume.m, including newly created rows and no-room wakeups; harness/player/lyrics-layout-check.sh. |
| jadetheda `6c619c3` (`feat/apple-music-queue`), `e804f6b`; michaelmelita1 `7df9b5e`, `3163c8a` / `6491011` | Read-only queue History | Redesigned/Player/PlayerQueue.m: Spotify's recent songs above Now Playing, with app-font rows. Editing and History replay are not shipped: the forks' same mutation/direct replay APIs did not take effect in the tested 9.1.90 context, including with Spoof Premium. No fork player removals or retry/reinsert fallbacks; Native retains Spotify's queue. |
| jadetheda `d10fb43`, `6e9056b` (with `af6e54e`, `181a58f`); upstream `69730d1` (#150) | Mini player Next button and artwork shape; a tap on the player's cover opening the full screen cover as a switch of its own | Done (Redesigned/NowPlayingBar/NowPlayingBar.x, Redesigned/Player/PlayerMorph.x, each look's PlayerGestures.x): `spotifyglass.redesign.nowPlayingBar.nextButton`, off; `spotifyglass.redesign.nowPlayingBar.artworkShape`, Circle (the fork's default was Rounded square, and its smaller cover for a 56 pt capsule is not needed on Retrine's 24 pt corners); `spotifyglass.hide.fullScreenCover`, shown; harness/now-playing-bar/ |
| upstream `9221256` | ElleKit/Substrate inline audio hooks on jailbreaks | Core/SGRebind.m and SpeedPitch.x: Start/Stop/Dispose installed inline all-or-none at tweak load, optional speed hook last, Spotify-__TEXT caller filter, canonicalized jailbreak paths; sideloaded installs keep the rebind path; harness/prefs/rebind.m. Not run on a real jailbreak. The SGPrefs per-key invalidation of `430766c` is not taken: nested writes needed app-wide notification interception for a small gain. |
| ciowfreshh `d829851` (archive codec only) | Saved lyric translations export/import | Core/TranslationStore: the ZIP field codec; storage, migration, recovery and the management page are Retrine's own (Shared/LyricsTranslation/SavedTranslations.m, TranslationLibrary.m); harness/lyrics-translation/check-storage.m. |
| Shilog62 `814d12460c`, `3a685eb69a` | Canvas with late authentication headers; lock-screen artwork from the track already playing | Shared/AnimatedArtwork/MotionSources.m waits for Spotify's asynchronously delivered headers with cancellation-aware waiters, not the fork's fixed eight-second timer; LockScreenMotion.x starts its follower from the current state without a second lookup; harness/motion/, harness/now-playing/ |
| Shilog62 `cf9d77ee17`, `8a75b08de6`, `caa81f0c60` | Spotify's syllable-synced lyrics; the lyric clock from the published player state | Shared/Lyrics/KaraokeTiming.m reads `SYLLABLE_SYNCED` through Retrine's strict time parsing (the fork's lenient integer parsing is not taken) and keeps line timing where syllable clocks are incomplete; KaraokeSource.x prefers `SGPlayerState()`; harness/lyrics-sources/ |
| upstream `910823a0`; jadetheda `b82cfbaeb6` | Gemini model guidance | Shared/LyricsTranslation/LyricsTranslation.m: 404 and timeouts point to the model setting; the unset default is `gemini-4-hydrogen`, a saved model stays the user's; no model rankings or quota claims; harness/lyrics-translation/ |
| upstream `87adc60c`; jadetheda `a56b51c018` | SF Symbol custom tabs | Redesigned/Navbar/TabBar.x hands UIKit the real symbol and its `.fill` selected variant for custom and Apple-symbol tabs, previews included; Native unchanged; harness/tabbar/ |
| Mate5000 `d666f10def`–`9eb0064c7d` (access only) | Quick EQ | Redesigned/Player/PlayerMenu.m: Audio effects in the player's ⋯ opens Retrine's existing Audio effects page in a sheet; the fork's second equalizer engine is not taken (it would stack on the existing effects on the render thread); Native keeps Spotify's sheet; harness/system-menu/ `effects` |

### Before the fork point, or not needed any more

| # | Item |
|---|---|
| 2 | Audio effects on the mod's own engine (`413b2d3`) |
| 3 | Find in playlist |
| 4 | Genius line meanings |
| 5 | Mod > Licenses |
| 7, 9 | Follow and add to library glyphs |
| 8, 10, 11, 12 | 0.22.0 fixes |
| 51, 65 | Update sheet once per release (debug line removed in `0f1d768`) |

## Leave out

| # | Item | Why |
|---|---|---|
| 19, 35, 86 | Certificate offer, Arctic Sign card, usage ping | Third-party signing upsell and upstream telemetry |
| 91, 99, 100, 102, 131 | Plus categories, locks and offer | No paid tier |
| 95 (Account page) | Upstream account | No account. The system Settings style is below |
| 129 | "sing limit" | Says nothing buildable |
| 96 | "More visualisations" | One commit in upstream's private repo after 0.23.0-beta. Nothing public says what it adds |

## Still open

- Device checks: Settings, the player footer and the Lyrics Style sheet were checked on an iPhone 15 Pro
  (iOS 27) for beta.1. Still unchecked: Karaoke with a freshly downloaded model, Delay with AirPods, the Live
  Activity options and preview, the font families, Settings at the largest accessibility text size, and
  VoiceOver. Each commit body lists what to check.
- From beta.4, on a phone: the hardware keyboard's keys, holding a lyric line, the player's spacing with shuffle and
  repeat both hidden on a narrow and a wide iPhone, and an album's ⋯ sheet with Play counts In menu.
- From beta.5 and the Plus round, on a phone: every new switch above (the mini player's artist line, Clear
  Downloaded Covers, the Home chips, the full-screen cover and its scrim, the page veils and round Play, the Visualizer
  fallback and shuffle, the hold speeds, Messages and Vinyl on the lock screen, Find Info against the real iTunes
  Search, a preset following AirPods and the speaker, a runaway Liveprog script).
- From beta.6 and 1.0.0, on a phone: everything above was checked on an iPhone 13 Pro (iOS 27.2, Spotify 9.1.90),
  which found and fixed three defects (only one face of several artists, a seam where AMOLED blackened a near-black
  page under the Picture-aware cover, and a layout loop across Spotify's three progress sliders). Still unchecked:
  the cut-out Play and the album ⋯ with Increase Contrast, which the phone driver cannot switch.
- From the second round, on a phone: Keep for This Song across a relaunch, the line under the cover with Spotify's own
  lyric preview on, the album notes' two placements and their sheet, an artist's photo and animated artwork, and the
  rolling digits and star. The Queue and Connect sheets' glass is not checkable until UIKit hands the sheet a
  background below full height on iOS 27.
- From the whole-feature round, on a phone (iPhone 13 Pro, 9.1.90): checked are Spotify's own lyrics with the narrowed
  header capture, the new rows in Korean, settings search and its recents, the cover layouts, the tab bar fade, the
  header glass and Music app icons switched off, Automatic accent, and the next track's lyrics prepared when Up Next
  changes. Spotify plays matched the artist page's Popular counts exactly and now show in the rows. Still unchecked:
  Compact library's menu, the E masks (the album tried had Korean 19 badges), the next track's artwork, and the meaning
  sheet's Translate. The artist line's change does not reach a loaded 9.1.90 row, whose explicit badge sits inside the
  SubtitleView it would hide.
