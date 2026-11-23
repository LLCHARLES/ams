# Listening stats harness

`SGPlayLog.m` run on the Mac against synthetic files in both shapes of Spotify's data export
(`StreamingHistory_music_*.json` and the extended `Streaming_History_Audio_*.json`), loose and inside zips
made by `/usr/bin/zip` both stored and deflated. Checks podcasts, nulls and plays under 30 s are left out,
that a play already recorded, the same play in both shapes and a second import of the same files add
nothing, that the log reads back what it wrote, and that the week, month, year and all-time tops add up.
It also times parsing, merging, loading and adding up 100k extended rows.

    ./build.sh && build/listening-stats

## Local history parity (0.51.0)

The production model now also provides pure `SGStreaks` and `SGHourlyStats` functions. Each already-counted
play belongs to its ending day/hour in the supplied calendar and timezone, including recorded short tracks.
Current streak includes today, or ends yesterday if today is empty. Best streak ignores future days.
There are always 24 hourly buckets; a repeated DST hour combines both occurrences. The existing rolling
7/30/365-day period cutoffs and top-list ordering are unchanged. The page formats hours using the user's
12/24-hour preference and exposes both plays and duration as ordinary accessible Settings rows.

Retrine's own export is a JSON object, distinct from Spotify's array exports:

```json
{"format":"retrine.listening-history","version":1,"plays":[{"end":1700000001,"ms":12500,"uri":"spotify:local:short","title":"Short track","artist":"Artist","album":""}]}
```

All six `SGPlay` fields are included, with Unix seconds and integer milliseconds. It contains no account,
credentials or settings. Unknown versions, malformed rows, invalid types and unsupported timestamps
(outside years 1–9999) reject the local file as a whole. Spotify's original filtering remains unchanged.
Spotify formats use the existing title/artist + 90-second deduplication for their minute precision and clock
drift. Retrine backups compare all six persisted fields exactly, so legitimate nearby repeats survive while
selecting the same backup twice still adds nothing. Import never rewrites old TSV bytes.
The TSV's existing tab/newline-to-space normalization on disk is unchanged.

Import accepts selected JSON/ZIP files or a selected folder of JSON files. Security-scoped access and
coordinated file reads are balanced on a worker queue; traversal rejects symlinks, stays below selected
roots and ignores hidden/irrelevant files, packages and `__MACOSX`. Limits are eight entry levels, 10,000
visited entries, 1,000 files, 64 MiB per JSON, 256 MiB total input/expanded JSON and one million parsed plays.
ZIP decoding uses a fixed output buffer and charges failed decompression attempts to the same aggregate budget. Oversized or
unsupported items are skipped and reported. ZIP64 remains unsupported. Export refuses an over-limit
JSON rather than creating a backup the importer cannot read; the source history stays untouched.

Initial TSV loading, JSON parsing, folder walking, aggregation and export serialization run off main.
The build also runs the production Logos recorder in an isolated Catalyst home. Independent fake
player reports and a continuous clock cover metadata arriving on report-only updates: an unnamed
track receives its names and produces one forty-second play at the next track.
The recorder links the real preference accessors. Recording-off listening cannot
be rescued by enabling while paused; enabling during playback starts a fresh
interval immediately, disabling finishes only the enabled interval, and unrelated
defaults changes leave it intact. A worker-thread off/on pair while main is busy
checks notification delivery without blocking main or losing the disabled gap.
An older worker snapshot of recording-on queued behind a synchronous main-thread
switch-off cannot restart the interval or save the following disabled listening.
Use `BUILD_DIR=$(mktemp -d /tmp/r1-stats.XXXXXX) ./build.sh` for isolated build output.
The build also runs `album-plays.m` against the production album counter and log. It checks the
generation/suffix cursor on append, complete recounts after import and erase, and counting again
after erase. Already-loaded reads preserve the generation rather than republishing the history.
`SGPlayLog` serializes loading and indexed imports on its IO queue, with main-queue completions and
independently published snapshots/errors. A separate recorder queue appends and syncs each small
journal row in order, without blocking main, queuing behind imports, or rewriting history.
`finishPendingWritesWithCompletion:` acknowledges earlier writes/erases on main, independently of
bulk work; readers and folding wait off main. iOS holds a background-task assertion from enqueue
through acknowledgement (or expiration). Startup and imports
use the generation whose erase has actually completed on the recorder queue, never a merely
requested generation. Only application termination waits synchronously for the recorder, bounded
to one second and independent of bulk imports/main callbacks. Recorder errors are acknowledged
separately from load status and a later successful write clears the failure. Startup and imports
rotate/fold journal segments into atomic bulk commits. A seventh-column record ID makes recovery
exactly-once after a commit interrupted before cleanup; legacy six-column TSVs load unchanged.
Bulk appends first terminate an unterminated canonical tail inside the staged copy, preserving the
legacy loader's interpretation while keeping new rows intact before journals are consumed.
Startup reclaims abandoned staging files, and erase invalidates in-flight writers and removes all
writer-owned journals/stages as well as the canonical log. Load errors
are explicit and retry on reopening the page. Export uses the system document exporter; its temporary file
is removed after completion or cancellation. No SQLite migration or Account/Plus dependency was added.

The interrupted-import probes run in child processes against the production log. They block a staged
import, acknowledge two recorder writes, read main-thread snapshots/errors, and exit without termination flushing.
Recovery checks their ordering, partial-tail rejection, abandoned-file cleanup, and erasure during the
blocked write. The parent bounds a deadlocked child to ten seconds. Run only these probes with
`build/listening-stats --persistence-review`.

The same checks inject a blocked system `fsync` to prove record, erase, and snapshot reads do not
wait on persistence; rapid records retain their order and a pending write cannot survive a later
erase. Unterminated complete and partial legacy tails are folded and reopened with literal expected plays.

Additional harness cases cover spring/fall DST, a timezone that skips midnight, leap day, year boundaries,
non-Gregorian calendars, fractional timezones, yesterday/gap/empty/future streaks, hourly cutoffs, all-field
JSON round-trip, Unicode/escaped strings, short tracks, malformed/unknown JSON, duplicate import, append-only
byte preservation, selected-folder containment/depth/size limits, corrupt ZIP size declarations and async
load versus record/erase. The 100k benchmark also checks and times the new calendar aggregations.

2026-10-15 local verification: `./build.sh && build/listening-stats` passed all 71 checks.
For 100k rows (34.2 MB Spotify JSON): parse 426 ms, merge 289 ms, duplicate merge 133 ms,
TSV load 146 ms, top lists 153 ms, streaks plus hourly buckets 183 ms. These are Mac harness
measurements, not iPhone timings. `THEOS=$HOME/theos ./build-sim.sh` built successfully with
`-Wall -Werror`; the repository layer check and scoped `git diff --check` also passed.

## Calendar periods and the redesigned page

The page steps through calendar weeks, months and years rather than rolling 7/30/365-day windows. The model
adds pure, Foundation-only functions, safe on any thread (each copies the calendar it is given):

- `SGPeriodInterval(period, date, calendar)`: the week (from `calendar.firstWeekday`), month or year holding
  `date` as `[start, next start)`. The next start is found one unit past the middle of the period, so DST weeks
  (167/169 h), short months and zones that skip midnight (the day starts at 01:00) come out right.
- `SGPeriodStep(period, date, steps, calendar)`: whole periods back or forward, stepped from the middle so a
  month never clamps on the 31st.
- `SGStatsBetween(plays, start, end, top)` and `SGHourlyStatsBetween(...)`: `[start, end)` in Unix seconds;
  `INT64_MAX` means no end, which is what `SGStatsSince` and `SGHourlyStats` now call.
- `SGPeriodBuckets(plays, period, date, calendar)`: the period's local days (week, month) or months (year), empty
  ones included, each with its plays and listening time, for the chart.
- `SGListeningStreaks` also carries the first and last day of the current and the best streak (the latest best
  on a tie).

`periodChecks()` covers Monday-, Sunday- and Saturday-first weeks, the spring DST week (167 h) and Sunday (23 h),
the fall-back Sunday (25 h, its repeated hour counted once per play), the week across New Year, a week starting
on São Paulo's day without midnight, leap February, month stepping from the 31st and across years, year stepping
from 29 February, half-open period sums (a play at the exact end belongs to the next period), March's 31 day
buckets adding up to the month's plays, a year's 12 month buckets, a Hebrew leap year's 13 months and streak date
ranges (ties, leap day, a current streak ending yesterday, none without plays).

Page structure (sections): 0 the streak card; 1 the period card (Week/Month/Year control, previous, title,
next), the chart, Listening time, Plays, By hour of day; 2–4 Top tracks/artists/albums (five on a card, See all
while there are more of the 25; the heading opens the chart while the period has plays); 5 Recap; 6 All time,
total Plays, History; 7 Record plays; 8 Import history, Import a folder, Export history; 9 Erase listening history.

## Charts and the recap

`SGTopCharts.m` and `SGRecap.m` are pure and built into the Mac binary. `chartChecks()` ranks a synthetic
Monday-first January 2026 in New York: the tie-break (plays, then time, then name), moves against the week
before, New for an entry absent the week before and for one there but 54th (outside its top 50), a run of 3
weeks in the top 5 ending with the shown week, the discovered count (not an entry from two weeks back), a play
at the week's first instant in and one at the next week's out, an episode left out, an empty week, and artist
and album identity. `recapChecks()` covers 29 versus 30 active days, the year boundary by play end (31 Dec
23:59:59 in, 1 Jan 00:00 out), the top lists, discoveries leaving out what was played before 1 January, the
longest streak across the DST change, the peak hour and month, the album card dropped when no play names an
album, the announcement window (31 Dec, 1 Jan, 14 Jan, 15 Jan) and the preference fallback.

The simulator app adds `showcase` (four weeks of a chart and 40 days of last year), `chart=<0|1|2>` (the Top
heading tapped: the chart page opens and ranks), `story` (Recap opened and last year's story played: it opens,
moves on by VoiceOver's increment and by itself after 6 s, and Close dismisses it), `storyopen` and `storyshare`
(the share image read back at 9:16). Failures exit through `harness-fail.h`.

    xcrun simctl launch <udid> com.retrine.listeningstatsharness erase showcase chart=0
    xcrun simctl launch <udid> com.retrine.listeningstatsharness erase showcase story

2026-10-24 local verification: `./build.sh && build/listening-stats` passed all 97 checks.

## The page and the recorder in the simulator (`sim/`)

`ListeningStatsPage.m` on the real Settings/ framework, `ListeningStats.x` through Logos with `sim/stubs.m` standing in
for PlayerState.x and Spotify's player classes, and the page's picker kept rather than presented (the simulator's
picker is a remote service), so `pick` hands its delegate a JSON file and a zip as the system would.

    THEOS=$HOME/theos ./build-sim.sh
    xcrun simctl install <udid> build/sim/ListeningStatsHarness.app
    xcrun simctl launch <udid> com.retrine.listeningstatsharness erase seed select=1.0 dump
    xcrun simctl spawn <udid> log show --last 2m --predicate 'eventMessage CONTAINS "[harness]"' --style compact

2026-10-05, iPhone 17 Pro on iOS 27.0: the page with seeded plays (week 1 h 36 min, month 2 h 12 min, as the seed
adds up), the Past week and All time pages (a long title wraps), an import of an extended file and a zip holding
`Spotify Account Data/StreamingHistory_music_0.json` (2 added, 1 skipped; the same again adds 0; the import row reads
Importing… until the merge, a second tap on it ignored meanwhile), and `record`: a
31 s play and one of 35 s around a 10 s pause written down (32.5 s and 36.8 s, `dispatch_after` running late), a
5 s skip left out.

The local parity batch also builds this simulator app with the real page and dark document presentation
helper. Since the Recap section the import row is section 8, row 0 (folder import row 1, export row 2) and
the shown period's hourly page is section 1, row 4; the All time page's hourly row is section 0, row 2.

What it does not cover: Spotify's real player reporting, a real export from Spotify, cloud document-provider
access, or interactive system export completion/cancellation. The dated simulator observations above are
prior evidence, not a claim that the new picker paths were exercised on a device.
