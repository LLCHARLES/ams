# Now playing harness

The two hooks of `MPNowPlayingInfoCenter`'s setter, `Shared/Player/NowPlayingExtras.x` and
`Shared/LockScreenLyrics/LockScreenLyrics.x`, through Logos and nested as in the tweak, run on the Mac as a
Mac Catalyst tool. The system's setter and getter are replaced under both, so the check reads exactly what
the system was given. Karaoke is a stub with two lines of lyrics.

It checks that:

- once lock screen lyrics let a line go, the info sent with the artist back carries the elapsed time moved
  on, not the one Spotify reported a while ago, and a later resend of an extra is not pulled back by it
- an extra cleared while the info still carries it (the next track has the same title, or Spotify copied
  it onto its next info) is taken off at once, another owner's extra stays, and nothing is sent when there
  is nothing to take off

It runs once with lock screen lyrics off and once with it on (`LSL=1`).

    THEOS=$HOME/theos ./build.sh

`SRC=<checkout>/tweak/Sources` builds another checkout instead, to see a bug before its fix.

The harness also compiles `LockScreenMotion.x`, `LyricsArtwork.x` and `SGMotionFollower.m` from that
source tree. It requires macOS 26 and the corresponding Catalyst SDK; no simulator or network is used.
`artwork.m` supplies controlled source/poster completions and tiny renderer stand-ins, captures the real
animated-artwork object's request blocks, and redirects caches to a unique temporary directory.

The added checks exercise:

- delayed posters after lyrics take ownership, after switching off, and after a same-title track change
- plain → lyrics → plain generation changes
- late animated-artwork capabilities without source re-downloads, polling or resend recursion
- pending presentation cancellation when lyrics take ownership or artwork is switched off
- cold off-main lyric publication, previous-frame fallback, same-ID static artwork reuse and
  direct Lyrics → Every song native-cover restoration (`publication-check.inc`)
- coalesced main-thread info notifications without blocking background setters or notifying extras resends
- Every song waiting for a paused track's late cover and retaining it for lazy requests
- a paused lyric line acquiring its late cover under distinct preview and disk identities, including
  the prefetched next line, without reusing the coverless cached output

Use `OUT=$(mktemp -d /tmp/retrine-now-playing.XXXXXX) THEOS=$HOME/theos ./build.sh` to leave existing
build artifacts untouched. The checks still run with artist-row lyrics both off and on.

The shared background renderer is real; render/encode stand-ins still isolate lifecycle behavior.
An isolated volatile preference domain exercises paused background changes, slider-burst coalescing,
stale request cancellation, current/prefetched disk identity changes, full-raster cover requests,
and safe no-cover → real-cover recovery without source downloads.

The lyrics cover checks compile the real `SGLastTrack.m`: track metadata passes through
`SGShownTrackNow` and `SGShownTrackArtwork`, with only HTTP transport intercepted by an in-process
`NSURLProtocol`. A non-nil native photo placeholder remains in now-playing info while the metadata
cover arrives; previews and disk clips must go from dark fallback to the real cover, including the
prefetched line. Same-title URI changes, same-URI artwork URL revisions, at most one failed-load retry
followed by no further requests, paused retry recovery, and disabling during a load or retry are
also checked. This boundary was missing from the older
nil → image now-playing tests. Rendering/encoding and the OS remain stand-ins, so these checks do
not establish the origin of a device's placeholder or validate device video playback.

The harness also compiles the real `Shared/LiveActivity/LiveActivity.x`, replacing only its
ActivityKit bridge and unrelated services. Saved-translation store completions are controlled:
paused artist-row/artwork deletion without a lyrics view, activity restore/save/delete/language
and source replacement, and no activity-triggered automatic translation are covered. A held
clip encoder checks that same-track seeks discard obsolete next-line jobs and serve current
demand before the latest prefetch. A held filesystem cleanup interleaves an already-queued
worker with a new track's cleanup and video request; the delivered URL must remain readable
after both cleanups finish.

Device ActivityKit delivery,
actual video decoding/encoding, and lock-screen presentation still need a device check.
