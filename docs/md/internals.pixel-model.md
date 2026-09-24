# The pixel model

nokre's promise: **same logical viewport ⇒ same bytes**, every run and
every machine, on the platform that drew them. Why that promise is worth
making — and why it deliberately stops at the platform's edge — is
[introduction.md](../introduction.md)'s story; this document is the
normative contract that makes it true.

## Logical pixels, integer scale

- All layout happens in integer logical pixels (`i32`). There are no
  fractional coordinates anywhere in the API.
- HiDPI is an integer scale factor applied as a transform at the raster
  surface (`Surface.init(w, h, scale)`). A 2× frame is exactly the 1× frame
  with every logical pixel rendered into a 2×2 block (text re-rasterizes at
  the larger size but at identical logical metrics — hinting is off).
- Fractional OS scale factors are rounded to the nearest integer —
  125% → 1×, 150% → 2× (the Windows shell computes `(dpi + 48) / 96`,
  and every shell applies the same policy). No shell letterboxes:
  logical size is the ceiling, and the sub-scale remainder is cropped
  at the window's edge.

## Grayscale, thirteen steps, four ramps

The full palette, from [src/core/color.zig](../../src/core/color.zig): thirteen
steps `g0`–`g12`. A step is a *semantic* position, not a byte — each (theme,
appearance) pair supplies its own ramp, and a dark one is deliberately not its
light one reversed. The theme is the look (`eink`, the default, or `depth`;
choosing one is [getting-started.md](../getting-started.md), "A theme"); it
changes paint and never a rect.

| Name | Eink light | Eink dark | Depth light | Depth dark |
| --- | --- | --- | --- | --- |
| `g0` | `0x00` | `0xDE` | `0x00` | `0xDE` |
| `g1` | `0x15` | `0xCD` | `0x15` | `0xCD` |
| `g2` | `0x2B` | `0xB8` | `0x2B` | `0xBD` |
| `g3` | `0x40` | `0xA5` | `0x40` | `0xA6` |
| `g4` | `0x55` | `0x91` | `0x55` | `0x91` |
| `g5` | `0x6A` | `0x80` | `0x6A` | `0x84` |
| `g6` | `0x80` | `0x6B` | `0x80` | `0x6E` |
| `g7` | `0x94` | `0x5A` | `0x8A` | `0x67` |
| `g8` | `0xAA` | `0x49` | `0xAA` | `0x49` |
| `g9` | `0xBF` | `0x3B` | `0xBF` | `0x3B` |
| `g10` | `0xD4` | `0x2C` | `0xD4` | `0x2D` |
| `g11` | `0xEA` | `0x15` | `0xEB` | `0x25` |
| `g12` | `0xFF` | `0x00` | `0xFF` | `0x1C` |

Depth's ramps are eink's except where its page ground (below) forced a step
to move; why each moved is the ramp's own doc in color.zig. The ratios quoted
in the rest of this section are eink's. Every text and focus gate they
illustrate is asserted in all four ramps by color.zig's tests, and text on
`paper` against both ends of depth's page ground too; the non-text gate on
control boundaries is asserted in eink alone ("The one waived gate", below).

Eink's light ramp is thirteen evenly spaced bytes across the full range, `g6` (the
middle) being the 50-50 gray. `g7` is the one exception: even spacing puts it at
`0x95`, which is 2.995:1 against paper and so misses the non-text-contrast floor
it exists to satisfy, and it is pulled one byte to `0x94` (3.03:1) instead. A
dark ramp descends — that descent *is* the inversion, which is why no draw site
inverts anything.

Semantic aliases: `ink` = `g2`, `dark` = `g3`, `mid` = `g5`, `light` = `g9`,
`paper` = `g12`.

The aliases sit where WCAG compliance holds by construction, in every
ramp — in eink: `mid` on `paper` is 5.4:1 light / 5.3:1 dark (AA body text), `dark`
is 10.4:1 / 8.5:1 (AAA), and `g7` — the lightest step permitted for an
interactive border — is 3.0:1 / 3.0:1 (non-text contrast).

Boundaries come in three tones, and the difference is always which ground they
sit on — the rule is one line: the lightest step that clears 3:1 on *both* sides
of the stroke. The labeled fields (`text_input`, `text_area`, `select`,
`copyable`) outline in `g7`: their borders run the full width of the pane, where
a heavier tone reads as a box rather than a hairline. The compact controls
(toggle, checkbox, radio ring, segmented chips) stay at `g6`, because their
borders sit against the `g11` track, where `g7` falls to 2.5:1. The nav's current
chip goes one further to `mid`: with the bar's track gone the chip carries its
own `g10` fill, and `g6` is only 2.7:1 against that. `g10` is separately the
grouping tone used by `box`, `tile_group`, `badge`, and the separators — that use
carries no state and is not subject to 1.4.11 at all.

The focus indicator is a third thing again: one 2px stroke in `ink`, in one of
two placements, and never two lines at once. Where the element already owns an
outline — the labeled fields, the radio-group box, an outlined button, the rows
and chips packed into groups — focus *takes that outline over*: the box does not
move, its boundary thickens and darkens. Everything else gets the outset ring,
held two pixels clear of the rect. The clear is structural rather than
decorative: two anti-aliased arcs sharing a boundary do not sum to full
coverage, and the shortfall reads as a light hairline tracing the corner —
which is what a ring drawn flush against a filled pill produced. The one
exception is an inline link, whose ring hugs the line box, because the lines
above and below leave no room for the clear and a line box paints nothing at its
own edge anyway.

`ink` and not `dark` is forced by the first placement: WCAG 2.4.13 asks for 3:1
between the focused and unfocused states of the indicator's own pixels, and over
a field's `g7` outline `dark` is 2.8:1 in the dark ramp where `ink` is 3.5:1. One
case is left short deliberately — a chip that is both selected and focused
starts from a `g6` outline, which `ink` clears in light (3.6:1) but not in dark
(2.7:1), so half its perimeter carries the change rather than all of it. The
selection fill states it a second way, and the alternative is a 3px stroke on a
44px row.

Contrast is bounded *above* as well: `ink` on `paper` is 14.2:1 light and 10.6:1
dark, not the 21:1 that `g0` on `g12` would give. WCAG 2.x has only a floor
because it treats contrast as monotonically good; APCA and the WCAG 3 draft do
not. Past roughly this point more contrast stops buying legibility and starts
costing comfort — halation at the extremes is worst for astigmatic readers, and
worse light-on-dark than dark-on-light.

That asymmetry is the whole reason a dark ramp is its own ramp. Light-on-dark stems read
heavier (irradiation), so dark should be *gentler* than light at equal authored
intent — and a mirror cannot do that, because it moves every ratio together. The
dark ramp eases the body-text pair by a quarter while holding the secondary-text
and boundary ratios within a percent of their light values, and keeps enough
elevation spacing that a raised surface still reads as raised.

Eink's dark page is true black, which is a choice rather than a leftover. The ramp
is solved as ratios *against the page*, so the page byte sets the whole ramp's
altitude and the easing holds either way — pinning it at `0x00` is paid for at
the text end, where `ink` comes down from `0xC6` to `0xB8` to keep the same
10.6:1. Pure black costs nothing on a raster display and switches OLED pixels
off outright, which is most of nokre's mobile surface. What matters for
halation is the luminance step at the glyph edge, and that is set by the *text*
byte, not the page — which is why `ink` is nowhere near `0xFF`.

`g0` and `g12` survive as the two steps the design system itself never draws.
They are reachable only through a canvas pinned to eink light (`Canvas.light`), for the
two surfaces that want maximum modulation whatever the look: the QR tile,
because a scanner wants it and a photo-negative code is a different code, and
the vendor sign-in marks, because Apple's HIG sanctions black / white /
white-outlined and nothing between. `Tree.append` rejects text at that contrast
(`error.ExcessiveTextContrast`), so an app cannot reach it by hand.

Tests in `color.zig` prove all of this; a ramp byte that breaks compliance —
in either direction, in any ramp it is gated in — fails the build.

### The one waived gate

Depth does not hold WCAG 1.4.11 for control boundaries and graphic tracks
(meters, progress). The owner decided it: depth is the expressive look, drawn
in tonal fills and soft shadows rather than outlines, and eink is the fully
gated one. The cost is plain — a depth app's controls are not guaranteed to
meet 1.4.11, and nokre does not claim they do.

What is not waived: text contrast (1.4.3, floor and ceiling) in every ramp,
the focus indicator's 3:1 in every ramp — in depth against every fill a target
sits on, both ends of the page ground included — and every gate in eink. An
app that needs 1.4.11 conformance chooses eink. `color.zig`'s proofs assert
the waived gates for eink only, and each skip points here. Like the G below,
this is a recorded reversal of a guarantee rather than a gap; it spends
nothing an app can author.

### The one colored artwork

One thing on any nokre screen is not gray: the multicolour G on the
Google sign-in button, drawn because Google's branding rules refuse a
gray variant of their trademark. This is an *infrastructure* fact, not
an API one — the four colour values live in `element.google_g_rgb`,
reach pixels through the renderer's `google_g` table and the canvas's
single rgb operation (`drawTextRgb`), and are not reachable from any element: no element
carries a colour, no consumer call accepts one, and the palette an app
authors in remains the thirteen grays above. The colours resolve
through no ramp and follow no appearance — a trademark has no dark
mode. The decision record (this was a refusal for a long time, and the
reversal was the owner's) is in [oauth.md](oauth.md).

Surfaces are `kRGB_888x` — rgb with no alpha channel: the frame is
opaque, and the only blending in it is nokre's own (below). No canvas
operation except `drawTextRgb` can make r, g and b differ — every other
op paints a gray, or composites a gray over a pixel at one coverage
for all three channels alike — so the frame is grayscale by
construction everywhere that one mark is not. `on_frame` hands shells
tightly packed RGBX (4 bytes per pixel; the padding byte is outside the
promise and readers ignore it). Anti-aliased text and rounded corners
produce intermediate bytes; square-cornered geometry never does.

### What depth paints that is not a step

Three canvas ops carry no `Gray`, because no element may author what
they paint; each resolves its bytes from color.zig, and each draws
nothing — or, for the ground, the flat `paper` a clear would — under eink.

- **The page ground** (`fillPageGround`, `color.pageGround`). Depth's
  page is a vertical gradient a few bytes deep, lit from above and
  anchored to the *window*, not to the scrolled content. A gradient that
  shallow bands visibly, so it is dithered — by nokre, not the
  rasterizer, whose dither would be its pixels: an ordered 4x4 Bayer
  pattern, each 4-column block reading the matrix one row further down so
  every 16-pixel row holds all sixteen thresholds and its mean is the
  row's level exactly (`canvas.pageGroundByte`). The byte at a device
  pixel is integer math over the window's height and the pixel's
  position; the shim samples a tile of those bytes nearest-neighbour in
  device space. Eink's page is still a `clear(.paper)`, so every eink
  frame is the bytes it was before depth existed.
- **The drop shadow** (`dropShadow`, `color.dropShadow`), which depth
  light casts under a card and every plate in the nav's row and, smaller,
  under a control's lit plate, knob or field plate. Its coverage is nokre's too (`canvas.ShadowMask`): a smoothstep
  of each device pixel's distance to the rounded box, integer throughout,
  shipped to the shim as a nine-patch of coverage tiles. Black
  composited at that coverage, so it can only darken.
- **The scrim veil** (`scrimVeil`, `color.scrimVeil`): an end of the
  ramp composited at one coverage over every pixel beneath a modal
  layer, by the shadow's route in the shim — white in depth light, so
  the page recedes toward the sheet's paper without turning into a
  grayer paper of its own, black in depth dark. Eink's scrim stays the 1px `paper`
  checkerboard (`dither`), which writes only ramp bytes.

These are the only ops that composite, and they are why depth frames
hold grays on no ramp as *surfaces* — the ground's in-between bytes, a
shadow's falloff, everything under a veil — where an eink frame's only
off-ramp bytes are anti-aliased edges. Every one of them is still
r=g=b: a gray composited over a gray by one coverage stays gray.

## Geometry: anti-aliased only at rounded corners

Rects take a corner radius. At radius 0 they are integer-aligned fills with
AA off; square strokes are decomposed into four fills (see `hsk_stroke_rect`
in [shim/nokre_skia.cpp](../../shim/nokre_skia.cpp)) so no stroke ever
straddles a half-pixel. Rounded rects are drawn with grayscale AA — still
deterministic per Skia build, like text. Lines are axis-aligned only —
the shim ignores anything else by design.

## Text: shaped, grayscale AA, no hinting, no subpixel

- Bundled fonts only ([src/assets/fonts](../../src/assets/fonts)):
  twelve faces — mono and prose each in regular, bold, italic,
  and bold-italic, the icon face (the one that is not embedded whole:
  it is subset at build time to the glyphs the artifact's sources
  spell, [../elements.md](../elements.md#icon)), the Arabic-script companion
  (Vazirmatn regular and bold; the script has no italic tradition, so
  italic requests resolve to the upright weight), and the brand face
  (five glyphs — Apple's logo and the Google G's four arcs;
  renderer-only, `text.Family.brand`, which no app text can reach).
  Variants are real
  drawn faces from the same upstream builds as the regulars (Skia's
  fake-bold and oblique are never enabled — synthesis is
  rasterizer-dependent); the system font stack is never consulted for
  rendering. Face selection is the shim's face index,
  `family * 4 + variant`, icons at 8, the companion at 9/10, the brand
  face at 11
  ([canvas_skia.zig](../../src/render/skia/canvas_skia.zig) is the
  authority; the shim header's comment stops at the companion). Core
  never requests the companion: any
  Arabic-script codepoint in a run makes the shim substitute it.
- Every text call is shaped by HarfBuzz (pinned in
  `tools/fetch-deps.sh`, compiled into the shim — never into Skia).
  Each call is one direction run; the shim shapes it as a single buffer
  with explicit script and language (HarfBuzz's guesses read the
  process locale, which a deterministic renderer cannot allow) and
  draws resolved glyph IDs at positions accumulated in 26.6 fixed
  point. Advances are integer math from the font's own units, so
  measured widths — and therefore wrap points — are identical on every
  platform, independent of the platform scaler.
- Run order is core's: [bidi.zig](../../src/core/bidi.zig) implements
  UAX #9 in full (validated against the UCD's BidiCharacterTest) and
  the renderer hands the shim visual-order pieces. Direction is derived
  from content — first strong character per hard paragraph — and an RTL
  paragraph right-aligns its lines. Every draw and every measurement
  **states** its piece's direction; the shim asks the bytes nothing.
  That parameter is what buys UAX #9's L4, the mirrored glyph: HarfBuzz
  substitutes a mirrored character's partner in any buffer shaped
  right-to-left, so `(` prints `)` in a Persian line and `«` prints `»`
  — nokre carries no mirroring table of its own, and there is one
  answer rather than a per-run guess that could disagree with the
  resolved level. It used to guess, from whether the run held an Arabic
  *letter*, which is not a question about direction at all: a piece of
  pure punctuation between a Persian word and a Latin one — the ` (` of
  `FQDN (مثلاً company.com)` — sits at an odd level and holds no
  letter, so it was shaped left to right, drew an unmirrored bracket
  and put its space on the wrong side of it. Measurement takes the same
  parameter as the draw for the same bytes, so a pen advance and the
  ink it advances past cannot come from different glyphs.
  Kerning across piece boundaries
  (face changes, digit runs amid RTL) is forfeited exactly as it is
  across span boundaries, which is what keeps every width a sum of
  identically shaped pieces.
- **A caret is not a piece boundary, and neither is a selection edge.**
  An editable field's line is one run whatever the cursor is doing in
  it — the pre-edit spliced in where the cursor stands
  ([editing.zig](../../src/core/editing.zig)'s `shownLine`) and the
  whole thing handed to one draw — and the inks a selection or a
  pre-edit puts on part of it are painted by drawing that same run
  again under a clip. It used to be cut at the cursor into a `pre` and
  a `post`, and both consequences were visible: in Arabic script the
  letters at the cut lost their joining context and came apart as the
  caret passed, and the pen for the second half was the sum of two
  standalone widths rather than the whole string's, so the words slid a
  pixel or two sideways as the caret moved through them.
- `SkFont` settings are fixed: grayscale anti-aliasing, hinting off,
  subpixel positioning off. Hinting off is what keeps 2× exactly
  proportional to 1×.
- Run widths are ceiled to integers (`hsk_text_width`), so layout never
  underestimates and wrap points are integer-stable. Where a caret
  stands *inside* a run is the same shaping asked a second question
  (`hsk_text_caret_x`, reached through `text.Measurer`'s `caretRunX`):
  the run is shaped whole and its glyph clusters walked to the offset,
  summing the advances of the glyphs left of the caret — the earlier
  ones in a left-to-right run, the later ones in a right-to-left one.
  Under the same ceiling, so the caret at a run's end is the run's
  width; and an offset inside a cluster lands on that cluster's edge,
  because a caret between a ligature's two letters is a caret nothing
  can draw.
- A surface rasterises in horizontal bands, in parallel, and the bytes
  are the single surface's ([nokre_skia.cpp](../../shim/nokre_skia.cpp),
  the bands section): draw calls are recorded and replayed when the
  pixels are asked for, each band an `SkSurface` over its own rows of
  the one frame, so each pixel is one band's and every band sees every
  op in order. Rects, lines, the dither, depth's three ops and glyph
  masks are per pixel —
  a clip only decides which pixels are written — so a band draws them.
  An anti-aliased path is not: Skia chops a path at the clip's bounds
  when the path exceeds them and subdivides the chopped piece
  differently, so a rounded fill or stroke whose rows cross a band edge
  is drawn by the calling thread on the whole surface between the band
  segments, under the same clip stack, exactly as the single surface
  draws it. The band count is a platform property, stated in
  [canvas_skia.zig](../../src/render/skia/canvas_skia.zig)'s
  `renderThreads`: the five native shells get the *performance* cores —
  on a big.LITTLE phone each small core added lengthens the slowest
  band and the frame with it (a 2+6 tablet: one thread 14.8 ms, two
  12.7, four 13.8, eight 15.0) — and the web, which has no threads and
  no Skia, would get one band on the same path. `tests/goldens/band-edges.ppm`
  was minted on the single surface and holds every kind of ink across
  every band edge.
- Measured widths are memoised
  ([measure_memo.zig](../../src/render/measure_memo.zig)): layout asks
  for a screen's every run on every frame — ~700 on a statement list,
  wrap growing each line a word at a time — and a scroll changes none
  of the bytes. A width is a pure function of the bundled faces, so the
  memo can skip HarfBuzz for a run it has seen and can never answer a
  different number. On a 1600x2560 tablet it took a scroll frame from
  27 ms to 15 ms, of which shaping is now the 1 ms the draw path spends.

## The type scale

Fixed, from [src/core/text.zig](../../src/core/text.zig):

| Scale | Size px | Line height px |
| --- | --- | --- |
| `small` | 12 | 16 |
| `body` | 16 | 24 |
| `h4` | 18 | 26 |
| `h3` | 20 | 28 |
| `h2` | 24 | 32 |
| `h1` | 32 | 40 |

Word wrap is greedy at spaces, honors `\n`, and never hyphenates. A word
with no break opportunity in it that is still wider than the line breaks
at the box edge and continues on the next — CSS `overflow-wrap:
break-word`, which is what the DOM substrate asks the browser for so the
two substrates answer this the same way. It used to overflow instead, and
the box it overflowed was the screen: a German compound in a 360pt title
was painted past the frame and cut mid-word, losing the end of the word
outright. Breaking rather than eliding, because those glyphs are
content; `copyable` is the one element that elides, and it drops the
*middle* of a verbatim value whose two ends are what a reader checks it
by. The break lands between grapheme clusters, so a combining mark never
opens a line with nothing to sit on.

Which CSS value asks for it depends on what sizes the box, and the two
answers are not interchangeable. A box whose width is already forced —
`.tile-text`, at `flex: 1; min-width: 0` — takes `break-word`, which
breaks the word without touching min-content. A box sized by its own
content takes `anywhere`, the only value that reaches min-content: the
pill is the case, and under `break-word` a compound wider than the
column kept the button 301 wide against a 288 column at 320 and stepped
outside the page, one line tall. The raster substrate has no such split —
`wrap.breakWord` breaks against the column it is handed either way — so
picking `break-word` for a content-sized box is exactly how the two
substrates come apart.

**Marking that break with a hyphen was asked for and refused**, on three
grounds and not on taste. No CSS produces it, so the DOM substrate could
not follow: `overflow-wrap: break-word` never inserts one, and
`hyphens: auto` is a different mechanism — dictionary soft-break points,
per-language, per-browser — that does not reach an emergency break. A
raster-only hyphen is therefore permanent substrate divergence, which is
the defect this rule exists to close, not a nicety on top of it. It also
cannot be a line: `WrapIterator` yields slices of `content` precisely so
callers can recover byte offsets from the pointers, and bidi paragraphs,
span segmentation, link geometry and the text-area caret all do. And in
Arabic script it is wrong on its own terms — the break inside
«الکترومغناطیسی» leaves a final and an initial form, and a hyphen between
them cuts the join (`tests/goldens/long-word-title-rtl.ppm`, and the
mirrored tile beside it). A per-script hyphen would buy German a mark the
web substrate still could not draw.

## Partial frames

The frame source a shell installs
([skia_frame.zig](../../src/platform/skia_frame.zig)) keeps its buffer
from frame to frame and rasterises only the pixels the app's own state
says can differ from the frame the buffer holds. The buffer is always the
whole frame, and **every shell presents the whole buffer**: what a
partial frame saves is the CPU raster in core, not the blit.

**What is partial**, decided in
[render/damage.zig](../../src/render/damage.zig) by comparing the scroll
owners the renderer noted while drawing the last frame with the ones it
notes drawing this one — each owner's rect as drawn (moved by every
overshoot it is drawn inside, cut by the clips it is drawn under), its
bar's strip, extent, offset, overshoot and bar tone
(`scroll_bar.barTone`, the one rule the renderer draws by):

- a scroll region, a desk region, a segmented track or a code block
  whose offset or overshoot moved rasterises its rect, bar included;
- a bar that appeared, went, or changed tone rasterises its strip —
  which is how the latch moving from one surface to another reaches two;
- an owner carried by one of those (a nested region, a track in a
  region) adds nothing, as long as its rect before and after lies
  inside one of the rects already found.

Such a frame is asked for through `App.damage_inputs`, never
`needs_frame`, and only by the writers of scroll state: scrolling.zig's
offset and overshoot writers and `setBarVisible`, the latch release in
`dispatchInput` and `deliverSemantic`, and a bar grip's press, release
and cancel.

**What is whole** is everything else: the window's own offset or
overshoot, since the root is unclipped and the page shows between the
nav's plates and through the safe band; any frame asked for through
`needs_frame`, and any relayout `layout_dirty` asked for —
`damage_inputs.unbounded_changes` counts both, so a frame another caller
drew in between still counts; a change of viewport, safe band, theme,
appearance, presentation, direction, shape or focus; an owner set that
changed, or a geometry change no found rect covers; the first frame, a
new surface, and a frame drawn into a shell's own buffer
(`render_into`). The comparison, not the setters, finds what moved, so a
setter that forgot to say so is still seen, and a writer that sets
`needs_frame` can never be mistaken for a scroll. A tree edited without
`invalidate` is the one change nothing sees until the next whole frame.

**Rasterising inside a rect** replays the frame's whole op list under a
clip to it (`hsk_surface_pixels_within`), so chrome drawn after the
content is drawn again inside the rect too. Rects, lines, the dither,
the clear, the page ground, the drop shadow, the scrim veil and glyph
masks are per pixel. The three depth ops are per pixel by construction
rather than by luck: each is a nokre-computed tile sampled nearest in
device space, the ground's bytes are a function of the pixel's place in
the window rather than in the rect it was asked for, and a shadow
records its reach rather than its casting box, so a rect that only
touches the fringe still replays it. An anti-aliased path is not,
for the raster bands' reason above, and clipping every op to the rect
alike moved bytes at tile edges across the golden suite. What moves
is where a corner's curve crosses a scanline, so a rect is refused — and
the frame rasterised whole — when it reaches a corner square of a
rounded fill or stroke that it neither holds whole nor holds the clip
stack of (`cutsPath`). A region scrolled inside a sheet is the common
case: the nav's plates under the scrim have corners in its rect.

## Where the guarantee stops, and why there

Text glyph rasterization is determined by the font binary **and the Skia
build**, and each platform links the font backend it has (CoreText on
macOS and iOS, FreeType elsewhere). So the promise above is a
per-platform one: cross-*run* and cross-*machine* identity, not
cross-*platform*. That boundary is chosen, not pending. A tree carries no
visual intent, a substrate is entitled to draw it as its device draws
things ([substrates.md](substrates.md)), and a library that forced one
rasterization onto every screen would be overruling the only party that
knows what the screen is — the same argument that lets the DOM substrate
wrap text where the reader's settings say and not where a golden says.

What *is* identical everywhere is everything upstream of the scaler:
shaping, glyph choice, advances, and therefore all layout come from
HarfBuzz's integer math over the bundled binaries. Two platforms
disagree about the ink inside a glyph's box; they do not disagree about
where the box is, what wrapped, or what a screen reader is told.

Goldens follow from that: a golden set belongs to the platform that
generated it. The committed set is macOS-generated, so `-Dgolden` on
Windows or Linux mismatches by design and a shell validates against its
own regenerated set ([../testing.md](../testing.md)).

## Enforcement

Golden tests ([testing.md](../testing.md)) compare full frames byte-for-byte —
no tolerance, no perceptual diff. If a byte changes, a human reviews a
picture. Partial frames are held to the same bytes by their own gate
([contributing.md](contributing.md), "What nokre tests for itself").
