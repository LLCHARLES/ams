"""Compile the two album rule tables without their Logos view hooks."""
from pathlib import Path
import sys

src, out = map(Path, sys.argv[1:])
native = (src / "Native/Album/Album.x").read_text()
redesign = (src / "Redesigned/Album/AlbumSections.x").read_text()
keys = [line for look in ("Native", "Redesigned")
        for line in (src / look / "Album/Album.h").read_text().splitlines()
        if line.startswith(("#define SGHideAlbum", "#define SGRKeyAlbumHide"))]
out.write_text("\n".join(keys) + "\n" +
               native[native.index("static const SGNativeSectionRule sections"):native.index("enum { kSections")] +
               redesign.split("#pragma mark - the switches")[1].split("// What a cell")[0] +
               redesign[redesign.index("static NSInteger sectionTitled"):redesign.index("// The section a heading opens")])
