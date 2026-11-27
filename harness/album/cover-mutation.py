"""Inject external test boundaries into generated sources, never the working tree."""
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
mode = sys.argv[2]


def replace(old, new):
    global source
    if source.count(old) != 1:
        raise SystemExit(f"{mode}: anchor changed: {old}")
    source = source.replace(old, new)


if mode == "seams":
    source = f'#import "{Path(__file__).resolve().with_name("cover-seams.h")}"\n' + source
    if "SGMotionPageAlbumCover(artist, album, pixels," in source:
        replace("SGMotionPageAlbumCover(artist, album, pixels,", "SGRAlbumTestPageCover(artist, album, nil, pixels,")
    elif "SGMotionPageAlbumCover(" in source:
        replace("SGMotionPageAlbumCover(", "SGRAlbumTestPageCover(")
    else:
        replace("SGMotionAlbumCover(artist, album, pixels,", "SGRAlbumTestAlbumCover(artist, album, pixels,")
    if "SGMotionAlbumRowMatcher(artist, album, pixels," in source:
        replace("SGMotionAlbumRowMatcher(artist, album, pixels,", "SGRAlbumTestRowMatcher(artist, album, nil, pixels,")
    elif "SGMotionAlbumRowMatcher(" in source:  # earlier BASELINE revisions have no row lookup
        replace("SGMotionAlbumRowMatcher(", "SGRAlbumTestRowMatcher(")
    # Only the current hero runs the identifier scenarios. Baselines draw the off hero with their own API.
    if sys.argv[3] == "0":
        replace("SGMotionPageIdentifierCover(", "SGRAlbumTestIdentifierCover(")
    if "SGMotionPageStillEditionCover(" in source:
        replace("SGMotionPageStillEditionCover(", "SGRAlbumTestStillEditionCover(")
    replace("SGMotionPoster(file,", "SGRAlbumTestPoster(file,")
    replace("SGRCoverRead(poster,", "SGRAlbumTestStillRead(poster,")
    if "_clip = [[SGRHeaderClip alloc]" in source:
        replace("_clip = [[SGRHeaderClip alloc]", "_clip = [[SGRAlbumTestClipClass() alloc]")
    else:
        replace("[AVPlayerLayer playerLayerWithPlayer:_player]", "SGRAlbumTestPlayerLayer(_player)")
    replace("cache = [NSCache new];", "cache = SGRAlbumTestRenderCache();")
else:
    raise SystemExit(f"unknown setup mode: {mode}")
path.write_text(source)
