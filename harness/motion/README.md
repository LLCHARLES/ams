# Moving artwork harness

`SGMotionClip.m`, the steps of moving artwork that need no phone, run on the Mac: the size of the cut
for each shape, a 9:16 stand-in Canvas cut to 3:4 and read back (720 x 960, every frame, its length, and
by the color of its bands that it was cut about its middle, not squeezed), the same Canvas stored on its
side, the request for Spotify's Canvas service and its replies (a still then a video, each video type,
a GIF, empty and foreign replies), and when a Canvas that turned up late is asked for, for each order of
the sources.

    ./build.sh && build/motion

The build also runs `state-check`: the production follower receives a metadata-only Canvas report,
and the catalog uses offline HTTP replies to check launch-cache eviction, the logo pixel budget,
and pruning an isolated album plist. The issue #40 case replays the two albums in Apple's US UPC
reply for `196589805232` and `5054197493980`, and the album included for ISRC `GBN9Y2200015`
(only fields used here, with local video URLs). Spotify metadata is a double: the second UPC was observed
in Spotify 9.2.0; the harness does not call Spotify. `OUT=<unique directory>` isolates binaries and clips.
The clips land beside the executable in `clips/`. It prints how long the cut took,
on the Mac this was written on (about 10 s for a 10 s clip); it was not timed on a phone.
