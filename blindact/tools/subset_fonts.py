#!/usr/bin/env python3
"""Build the bundled UI fonts.

  * Cinzel (OFL) for Latin text      - art/fonts/Cinzel-*.ttf  -> assets/fonts/
  * Noto Serif CJK SC (OFL) subset   - only the characters used by the UI
    (every string in scripts/i18n.gd + ASCII + punctuation), so the game does
    not ship a 20 MB CJK font. Re-run after adding Chinese UI text.

Source CJK font: Debian/Ubuntu package fonts-noto-cjk
  (/usr/share/fonts/opentype/noto/NotoSerifCJK-{Regular,Bold}.ttc, face index 2 = SC)
Usage: python3 tools/subset_fonts.py
"""
import re
import shutil
from pathlib import Path

from fontTools import subset

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "fonts"
OUT.mkdir(parents=True, exist_ok=True)
CJK_DIR = Path("/usr/share/fonts/opentype/noto")

text = (ROOT / "scripts" / "i18n.gd").read_text(encoding="utf-8")
chars = set("".join(re.findall(r'"([^"]*)"', text)))
chars |= {chr(c) for c in range(0x20, 0x7F)}
chars |= set("‹›—–·…，。：；？！、“”‘’（）《》【】％0123456789")

for weight in ("Regular", "Bold"):
    src = CJK_DIR / f"NotoSerifCJK-{weight}.ttc"
    opts = subset.Options()
    opts.font_number = 2          # SC
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.notdef_outline = True
    font = subset.load_font(str(src), opts)
    s = subset.Subsetter(opts)
    s.populate(text="".join(sorted(chars)))
    s.subset(font)
    dst = OUT / f"NotoSerifSC-{weight}.otf"
    subset.save_font(font, str(dst), opts)
    print("wrote", dst.name, dst.stat().st_size // 1024, "KB,", len(chars), "chars")

for name in ("Cinzel-Regular.ttf", "Cinzel-SemiBold.ttf"):
    shutil.copy(ROOT / "art" / "fonts" / name, OUT / name)
    print("copied", name)
