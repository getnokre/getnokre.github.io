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

The icon face is subset by *codepoint*, from the list below — the site
draws exactly these glyphs, and the 843 KB Lucide ships is a library,
not a page's worth of marks. Names and values are nokre's
`src/core/icon_names.zig`; a value that disagrees with it is a bug in
this file.

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

# The marks this site draws, by nokre's own name for each.
ICONS = {
    "house": 0xE0F5,
    "book_open": 0xE05F,
    "wrench": 0xE1B1,
    "file_text": 0xE0CC,
    "chevron_right": 0xE06F,
    "chevron_down": 0xE06D,
    "chevron_left": 0xE06E,
    "chevron_up": 0xE070,
    "check": 0xE06C,
    "copy": 0xE0A6,
    "feather": 0xE0BE,
    "milestone": 0xE298,
    "shapes": 0xE4B3,
    "signpost": 0xE540,
    "pilcrow": 0xE3A3,
    "accessibility": 0xE297,
    "languages": 0xE0FE,
    "flask_conical": 0xE0D5,
    "package": 0xE129,
    "map": 0xE110,
    "layers": 0xE529,
    "git_branch": 0xE0E2,
    "zap": 0xE1B4,
    "globe": 0xE0E8,
    "credit_card": 0xE0AA,
    "key": 0xE0FD,
    "ruler": 0xE14B,
    "monitor": 0xE11D,
    "component": 0xE2AD,
    "code": 0xE093,
    "lock": 0xE10B,
    "hammer": 0xE0EC,
    "cpu": 0xE0A9,
    "palette": 0xE1DD,
    "type": 0xE198,
    "ban": 0xE051,
    "external_link": 0xE0B9,
    "arrow_up_right": 0xE04D,
    "square_asterisk": 0xE168,
}

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
    ("lucide.ttf", "icons.woff2", None, sorted(ICONS.values())),
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
