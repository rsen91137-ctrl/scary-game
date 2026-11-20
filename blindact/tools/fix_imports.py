#!/usr/bin/env python3
"""Set import options Godot can't infer for script-built materials.

Run after `godot --headless --import` has created the .import files, then
import again:
  godot --headless --path . --import && python3 tools/fix_imports.py && godot --headless --path . --import
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOOPS = {"bgm_corridor", "amb_night", "lamp_buzz", "tinnitus", "dizzy"}


def edit(p: Path, subs):
    s = p.read_text()
    for pat, rep in subs:
        s = re.sub(pat, rep, s, flags=re.M)
    p.write_text(s)


for p in (ROOT / "assets" / "textures").glob("*.png.import"):
    normal = "_normal" in p.name
    edit(p, [(r"^compress/mode=\d", "compress/mode=2"),
             (r"^mipmaps/generate=\w+", "mipmaps/generate=true"),
             (r"^compress/high_quality=\w+", "compress/high_quality=%s" % ("false" if normal else "true")),
             (r"^compress/normal_map=\d", "compress/normal_map=%d" % (1 if normal else 2)),
             (r"^detect_3d/compress_to=\d", "detect_3d/compress_to=0")])
for p in (ROOT / "assets" / "ui").rglob("*.png.import"):
    edit(p, [(r"^mipmaps/generate=\w+", "mipmaps/generate=true")])
for p in (ROOT / "assets" / "ui").rglob("*.svg.import"):
    edit(p, [(r"^svg/scale=[\d.]+", "svg/scale=2.0"), (r"^mipmaps/generate=\w+", "mipmaps/generate=true")])
for p in (ROOT / "assets" / "audio").glob("*.ogg.import"):
    if p.name.split(".")[0] in LOOPS:
        edit(p, [(r"^loop=\w+", "loop=true")])
print("import options fixed")
