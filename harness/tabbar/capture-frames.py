#!/usr/bin/env python3
"""The expand out of a recording capture.sh cut into 1/60 s frames: the last run of moving frames, from the still frame
before it to the one it settles on, each frame the screen drew written once as expand-NNN.png (NNN its 1/60 s from the
start), and sheet.png with all of them, four across.

    capture-frames.py <dir of numbered PNGs> <out dir>
"""
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageStat

# A frame moved when its pixels differ from the last frame's by more than this on average (0 to 255): the recording's
# compression alone stays well under it.
MOVED_LEVEL = 0.5
# Still frames that end a run of moving ones: the spring has settled. Fewer may be a frame the simulator skipped.
STILL_FRAMES = 15
SHEET_COLUMNS = 4


def moved(a, b):
    return max(ImageStat.Stat(ImageChops.difference(a, b)).mean) > MOVED_LEVEL


def main():
    source, out = Path(sys.argv[1]), Path(sys.argv[2])
    paths = sorted(source.glob("*.png"))
    frames = [Image.open(path).convert("RGB") for path in paths]
    if len(frames) < 2:
        sys.exit(f"capture-frames: {len(frames)} frames in {source}")
    changes = [i for i in range(1, len(frames)) if moved(frames[i - 1], frames[i])]
    if not changes:
        sys.exit("capture-frames: nothing moved in the recording")
    # The last run: back from the last moving frame while the moving frames stand closer than STILL_FRAMES.
    first = changes[-1]
    for i in reversed(changes[:-1]):
        if first - i > STILL_FRAMES:
            break
        first = i
    start, end = first - 1, changes[-1]
    kept = []
    for i in range(start, end + 1):
        if i == start or moved(frames[kept[-1]], frames[i]):
            kept.append(i)
    for i in kept:
        frames[i].save(out / f"expand-{i - start:03d}.png")
    width, height = frames[0].size
    rows = (len(kept) + SHEET_COLUMNS - 1) // SHEET_COLUMNS
    sheet = Image.new("RGB", (width * SHEET_COLUMNS, height * rows))
    draw = ImageDraw.Draw(sheet)
    for n, i in enumerate(kept):
        x, y = (n % SHEET_COLUMNS) * width, (n // SHEET_COLUMNS) * height
        sheet.paste(frames[i], (x, y))
        draw.text((x + 8, y + 8), f"{i - start:03d}", fill=(255, 64, 64))
    sheet.save(out / "sheet.png")
    print(f"expand: {len(kept)} frames drawn over {end - start} sixtieths of a second")


main()
