# Alternate icons

Each `NAME.png` here becomes an app icon that Appearance > App icon offers. `scripts/pipeline.sh`
scales it for iPhone and iPad and adds it to Spotify's `Info.plist`.

- Square, 1024 × 1024, no transparency.
- `NAME` is letters, digits, `_` and `-`. An `_` shows as a space in the list.

`Retrine.png` is drawn by `source/reeded-light.html` (the idea is in `source/reeded-light.md`). Open the
page to try other seeds and settings, or render one headless at 1024 × 1024:

    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars \
      --window-size=1024,1024 --virtual-time-budget=60000 --screenshot=icons/Retrine.png \
      "file://$PWD/icons/source/reeded-light.html?render=1&seed=7"

The other `Retrine_*.png` are the same glass over other light, rendered the same way with `&palette=` (three hex
colors, no `#`) and a seed:

| Icon | Query |
|---|---|
| `Retrine_Glacier.png` | `seed=7&palette=3ab8ff,5b4dff,7ef0ff` |
| `Retrine_Emerald.png` | `seed=7&palette=1ed760,0f8f6e,b8ff5c` |
| `Retrine_Ember.png` | `seed=11&palette=ff6a1a,ff2d55,ffc93d` |
| `Retrine_Twilight.png` | `seed=3&palette=b36bff,ff4fd8,4d7cff` |
