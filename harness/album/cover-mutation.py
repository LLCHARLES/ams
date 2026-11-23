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
    if "SGMotionPageAlbumCover(" in source:
        replace("SGMotionPageAlbumCover(", "SGRAlbumTestPageCover(")
    else:
        replace("SGMotionAlbumCover(artist, album, pixels,", "SGRAlbumTestAlbumCover(artist, album, pixels,")
    if "SGMotionAlbumRowMatcher(" in source:  # earlier BASELINE revisions have no row lookup
        replace("SGMotionAlbumRowMatcher(", "SGRAlbumTestRowMatcher(")
    if "SGMotionPageIdentifierCover(" in source:
        replace("SGMotionPageIdentifierCover(", "SGRAlbumTestIdentifierCover(")
    replace("SGMotionPoster(file,", "SGRAlbumTestPoster(file,")
    replace("SGRCoverRead(poster,", "SGRAlbumTestStillRead(poster,")
    replace("[AVPlayerLayer playerLayerWithPlayer:_player]", "SGRAlbumTestPlayerLayer(_player)")
    replace("cache = [NSCache new];", "cache = SGRAlbumTestRenderCache();")
else:
    raise SystemExit(f"unknown setup mode: {mode}")
path.write_text(source)
