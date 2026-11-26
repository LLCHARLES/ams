# Visualizer harness

The player's Visualizer background reads Spotify's sound through `Redesigned/Player/SGRSpectrum.m`. `main.m`
runs it on the Mac as the tweak compiles it, fed in IO buffers of 1024 the way `PlayerVisualiser.x` is fed by
`AudioEffects.x`'s reader:

    ./build.sh && build/spectrum

It checks that nothing is analyzed before the tables are made, that a full scale 1 kHz sine reads 0 dB in its band
(and a tenth of it -20 dB) with every band more than one away at least 30 dB under, that 56 Hz and 10 kHz land in
the lowest band and the last but one at 48 and 44.1 kHz, that silence reads the floor, that white noise rises
about 3 dB an octave over the bands, and that it analyzes about 47 times a second at 48 kHz.
The original 11 checks are retained. Six waveform checks additionally verify unpublished silence,
published silence, exact signed PCM positions, clipping to [-1, 1], non-finite input sanitation, and
non-destructive reads by multiple consumers across repeated preparation. The log ends with
`spectrum checks: n of 17 right -- PASS` or `FAIL`.

`SGRSpectrumReadWaveform` publishes 128 actual PCM samples (every fourth sample of the latest 512
frames) on each FFT analysis. Its fixed atomic storage lives for the process, so a callback already
in flight when the output reader is removed cannot access freed storage. An odd/even atomic sequence
guards coherent reads; readers try at most three times and return silence if publication overlaps
every attempt. The render thread never retries, allocates, locks or sends Objective-C messages.

The four local styles are Hills (the original default), Bars (mirrored spectrum and actual waveform),
Nebula (cover-palette clouds), and Halo (a dim current cover and spectrum ring). The exact legacy key
`spotifyglass.visualizer.shader` is a compatibility exception to the redesign prefix rule; its values
are `builtin:hills`, `builtin:bars`, `builtin:nebula`, `builtin:halo`. Missing/invalid values read as
Hills without rewriting storage. `SGRVisualiserStyleRow` is a reusable string-backed menu and
`SGRVisualiserSettingsPage` opens from Player while Visualizer is the selected background.

Every style shares the existing reader count and display link. Detached windows, background,
Low Power Mode, serious/critical thermal state and player transitions stop the link and reader.
Pause/silence eases to rest, then stops the link; while a playing stream is silent, a 4 Hz timer
checks for newly published sound without drawing. Reduce Motion freezes spatial movement and uses
the existing slow easing. The display link always requests the screen's full rate, so it never drags
the player's 120 Hz transitions down; the tick skips drawing to its own cadence instead: Hills/Nebula
draw at 60 Hz, Bars/Halo at 120 Hz on a 120 Hz screen, 30 Hz behind the lyrics and 15 Hz with Reduce
Motion (harness/player-visualiser checks both). These are target cadences, not measured frame-time
or compositor-performance claims.

The view itself is laid out in the player harness (`harness/player`, scenario `visualiser`).
That existing scenario tests Hills only. It does not establish visual equivalence, contrast or device
performance for the new styles. Device/simulator coverage should include each style during playback,
silence/pause/resume, lyrics, Reduce Motion, Low Power/thermal changes, transitions, repeated switching,
two simultaneous views with either removed first, and Halo track changes with delayed/missing artwork.
