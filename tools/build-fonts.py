#!/usr/bin/env python3
"""Subset nokre's bundled faces into the web fonts this site serves.

    python3 -m venv .venv && .venv/bin/pip install fonttools brotli
    .venv/bin/python tools/build-fonts.py [path/to/nokre]

The site renders in the same faces nokre renders in — that is the whole
point of the exercise, and the reason there is no font stack anywhere in
the stylesheet. What changes on the way to the browser is the container
and the coverage, not the outlines:

  - **woff2**, because a TTF over HTTP is the same bytes without the
    compression, and this site is about not spending what it does not
    need.
  - **subset**, because nokre embeds whole faces for an app that may
    localize into anything, and this site is English with the Persian
    and Arabic samples the localization docs quote. Everything outside
    those ranges is coverage nobody here will ever request.

The icon face is not here. nokre's own build derives it — lucide.ttf
subset to the glyphs an artifact's sources spell — and the generator
writes what it is handed (`../nokre/docs/elements.md`, the `icon`
element), so there is nothing about it for this script to keep in step.

Output is deterministic: fontTools writes no timestamps here (see
`--no-recalc-timestamp` equivalents below), so re-running produces
byte-identical files and the committed assets stay reviewable.
"""

import os
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

# Text coverage. Latin plus the punctuation, arrows, math and box-drawing
# the docs actually use (they carry ASCII diagrams and → ⇒ ≤ × §).
LATIN = (
    "U+0000-00FF,U+0100-017F,U+0180-024F,U+2000-206F,U+20A0-20BF,"
    "U+2190-21FF,U+2200-22FF,U+2500-257F,U+25A0-25FF,U+2713-2718"
)
# Code needs ASCII, the punctuation the prose faces need, and the
# box-drawing characters the internals docs draw diagrams with — the
# accented Latin a mono face carries is coverage no code block asks for.
MONO = "U+0000-00FF,U+2000-206F,U+2190-21FF,U+2500-257F,U+25A0-25FF,U+2713-2718"
# The Arabic-script companion: Persian and Arabic, their presentation
# forms, and the zero-width non-joiner Persian needs.
ARABIC = "U+0600-06FF,U+200C-200D,U+FB50-FDFF,U+FE70-FEFF,U+0020,U+002C,U+002E"

# The vendor sign-in marks (nokre's LICENSE-Brand.txt): Apple's logo and
# the Google G's four arcs. No site page draws one today, but the
# stylesheet nokre emits declares the face, and a site that declares a
# font serves it — five glyphs subset to almost nothing.
BRAND = [0xE900, 0xE901, 0xE902, 0xE903, 0xE904]

FACES = [
    ("prose.ttf", "prose.woff2", LATIN, None),
    ("prose-bold.ttf", "prose-bold.woff2", LATIN, None),
    ("prose-italic.ttf", "prose-italic.woff2", LATIN, None),
    ("prose-bolditalic.ttf", "prose-bolditalic.woff2", LATIN, None),
    ("mono.ttf", "mono.woff2", MONO, None),
    ("mono-bold.ttf", "mono-bold.woff2", MONO, None),
    ("mono-italic.ttf", "mono-italic.woff2", MONO, None),
    ("mono-bolditalic.ttf", "mono-bolditalic.woff2", MONO, None),
    ("arabic.ttf", "arabic.woff2", ARABIC, None),
    ("arabic-bold.ttf", "arabic-bold.woff2", ARABIC, None),
    ("brand.ttf", "brand.woff2", None, BRAND),
]


def build(src_dir, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    for src, out, unicodes, points in FACES:
        font = TTFont(os.path.join(src_dir, src), recalcTimestamp=False)
        opts = subset.Options()
        opts.flavor = "woff2"
        opts.desubroutinize = True
        opts.layout_features = ["*"]  # kerning and shaping stay whole
        opts.name_IDs = ["*"]
        opts.notdef_outline = True
        opts.recalc_timestamp = False
        sub = subset.Subsetter(options=opts)
        if points is not None:
            sub.populate(unicodes=points)
        else:
            sub.populate(unicodes=subset.parse_unicodes(unicodes))
        sub.subset(font)
        dst = os.path.join(out_dir, out)
        font.flavorData = None
        font.save(dst)
        font.close()
        print(f"{out:24} {os.path.getsize(dst) / 1024:7.1f} KB")


if __name__ == "__main__":
    repo = sys.argv[1] if len(sys.argv) > 1 else "../nokre"
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    build(os.path.join(repo, "src/assets/fonts"), os.path.join(here, "assets/fonts"))
