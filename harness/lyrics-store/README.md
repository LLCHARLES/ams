# Offline lyrics store

Run from the Project root:

```sh
HARNESS_BUILD_DIR=$(mktemp -d /tmp/fix-offline-lyrics.XXXXXX) sh harness/lyrics-store/build.sh
RETRINE_STORE_ONLY=1 sh harness/lyrics-sources/state-build.sh
```

The Mac Catalyst command-line harness runs without a simulator or network. It links
the actual store and lyric models and extracts the production credit registry
from `LyricsSources.m`, leaving the unrelated provider walk and UI unlinked.
Its unique build directory is removed on exit; lyric files use isolated temporary
directories, never the user's store.

Checks cover provider translations (including backing lines), credit titles/URLs
and mandatory attribution, generated-content exclusion, literal old-format records,
malformed/oversized optional fields, byte accounting, single-record overflow,
oldest-first eviction, main-queue completion and binary plist storage.
Rejected asynchronous loads leave the live credit untouched, including when the
stored link field is malformed; accepted loads explicitly register returned metadata.
Each translation carries its own production-time language tag, never the save-time
preference. Unknown/Any translations stay untagged. Delivery checks each line, including
backing/pronunciation lines, against the current selection: a specific language drops
mismatched or unknown translations, while Any accepts them, as providers do.
Tests cover cached English results saved under Korean, mixed per-line tags, a selection
changed during a read and previous-format records (whose root tag is ignored).
The raw Decode codec does not apply preferences.
The focused keeper integration uses the actual TTML parser and its regional-language
matching, verifies that an English saved answer permits a Korean community lookup,
and checks Musixmatch copies stamped with the captured request language.
Spotify's actual offline presentation and link opening remain device checks.
