# Shared lyrics background harness

`OUT=$(mktemp -d /tmp/retrine-background.XXXXXX) sh harness/lyrics-background/build.sh`

Runs the production Foundation/CoreGraphics-only renderer on macOS: default/clamped/finite preferences
without persistent writes; all five modes; retained two-pixel detail; equal grayscale channels; actual
album-derived gradient colors; selected solid RGB; blur/darkness bounds; no-cover behavior; and
source/style/raster cache separation. Prints per-mode cold-render time at 1200×1600 and process peak RSS.
Encoding/layout checks live in `harness/lyrics-clip` and `harness/fluid-clip`; lifecycle checks in
`harness/now-playing`.
