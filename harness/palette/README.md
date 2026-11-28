# Palette check

    ./build.sh && build/palette-check

runs `Redesigned/Kit/SGRPalette.m` on the Mac (as Mac Catalyst, for UIKit): a blue cover with a pale border along
its foot, read once by its bottom edge (the player's field) and once by its main color (a playlist, album or
artist page, `mainColor`). The edge has to come out gray and the main color blue. It prints PASS or FAIL; the exit
status is the number of failures.

The backdrop check renders a scale-one opaque white 16×16 cover into a 160×400 backdrop. At rows
0, 109, 219, 220, 309 and 399, and columns 0, 79 and 159, it checks premultiplied sRGB RGBA against the
documented gradients, not a platform-specific bitmap. At pixel-center height `t = (row + 0.5) / 400`,
black dimming is `d = 0.25 + 0.30 × min(t / 0.55, 1)` and opacity is one through `t = 0.55`, then
`a = (1 - t) / 0.45`. White input therefore gives RGB `(1 - d) × a` and alpha `a`.
Each channel allows ±2/255: less than one code value for raster sampling (half a pixel on the
steeper alpha ramp is `255 / (2 × 400 × 0.45) ≈ 0.71`), plus one for 8-bit rounding/dithering.
The 400-pixel height places the gradient join on an integer pixel edge.
Changing bottom dimming from 0.55 to 0.45 moves the opaque midpoint by about 13/255, well outside
that bound, without requiring different Core Graphics versions to reproduce identical dithering.

`bash harness/palette/field-check.sh` runs the production artwork field and flow layer on Mac Catalyst
with controlled palette replies. It covers artwork arriving before Colours is selected, reusing retained
artwork after a completed mode change, late palette replies in both directions, and restoration of the
still backdrop after leaving Fluid, including repeated round trips and a late Fluid palette, and the flow
layer's drift: at rest until started, moved by its own steps with no window to animate it, held when
stopped and carried on from there. The palette
service, player-transition observer and Fluid renderer are test doubles; no Spotify or GPU run is implied.
The same script checks the still field and the player’s cover accent across inactive track changes, with
out-of-order palette replies. Its second executable runs the production Fluid renderer, checks its drawable
sizes, and controls when preparation jobs run. Hidden and inactive changes must queue no work, activation
and uncover must schedule only the latest cover, and a paused, visible layer must still prepare it.
