# The lamp theme

`lamp` is the third look beside `eink` and `depth`: depth's surfaces
under one light. Its thirteen ramp bytes are depth's in both
appearances, every rect and metric is depth's, and what it changes is
paint alone, on the Skia substrate alone. This page is the design
record — what each op draws, the numbers it draws with, what holds by
construction, and what it costs. The palette it paints over is
[pixel-model.md](pixel-model.md); how an app declares a look, and what
depth itself paints, is [getting-started.md](../getting-started.md#a-theme).

The formulas below are the definitions. They were settled on a
per-pixel reference renderer the design was reviewed on, which is kept
outside this tree; the renderer evaluates them in integer arithmetic
like every byte nokre produces
([contributing.md](contributing.md#conventions)), and where a formula
meets a gate, the gate is a proof in
[color.zig](../../src/core/color.zig), not a sentence here.

## What the theme is

**One lamp, fixed in the window.** A point light at 50% of the window's
width across and 40% of its height down, in logical pixels. Its
attenuation at distance `d` is inverse-square with an ambient floor:

```
att(d) = AMB + (1 − AMB) / (1 + d² / D²)
D      = 0.8 · diag      (the window's diagonal)
AMB    = 0.14
```

and every response to it is scaled by one amplitude, `0.65`. The lamp
is anchored to the window the way depth's page ground already is, so
the page scrolls under it: a card passing beneath lights as it
approaches and dims as it leaves, and nothing else moves.

**Nothing ticks.** There is no clock, no sensor, no animation, and no
place the light could come from other than the viewport. A frame is a
function of the viewport, the scroll offsets and the rects, as every
frame already is ([pixel-model.md](pixel-model.md)). A tilt-driven or
time-of-day lamp would need a sensor or a clock in `src/render`, which
the pixel model refuses.

**The lamp is above everything.** Chrome is lit like any card: a nav
plate or a sheet takes the same rim, face and shadow a card on the page
takes, and casts its shadow onto the page.

**Paint only.** No op here moves a rect, changes a metric or touches
the tree. Every text and focus position, the accessibility snapshot,
focus order and scroll extents are depth's, and the test that holds
themes to one geometry holds lamp to it too
([testing.md](../testing.md#golden-screenshot-tests)). A second test
holds the draw itself: lamp's recording with its own ops set aside is
depth's, op for op, but for two substitutions — a frost stands where
depth filled the same glass, and depth's drop shadows are gone, since
lamp casts its own from every plate.

## The dark appearance

The dark appearance is where the lamp exists: depth dark's paper is
`0x1C` over a ground of `0x08`–`0x00`, which leaves room to light
things. The ops, in paint order:

1. **The page.** The ground and its pool; then each filled box as it
   is drawn — its shadow, its fill, its face and its rim, the rim lit
   by the lamp and by every chrome edge that reaches it at once
   ([below](#chrome-edges-are-lights)) — with the text and the rules on
   it drawn after it as in depth. So the chrome's edges are known
   before the page is drawn.
2. **The bottom row.** First every plate's contact line: each nav
   plate's and the notices indicator's. Then plate by plate: its
   shadow, its frost, its glass face and rim, its glyph and words. A
   notice banner in the row's place takes a nav plate's treatment.
3. **Each modal layer** — a sheet, the notices pane, a picker — in the
   order they stack: the dim over everything drawn so far, the layer's
   shadow, its contact line, its frost, its glass face and rim, then
   its content, whose filled boxes are plates like the page's and which
   no edge lights. The collapsed nav's section list is a card on the
   dim, not glass.

### The ground pool

The page ground gains the lamp's pool, a lift of

```
pool(d) = 12 · max(0, 1 − d / (0.72 · H))²   bytes
```

at distance `d` from the lamp, `H` the window's height, added to
depth's ground before the dither, with the sum capped at `0x10`. The
pool is dithered the way depth's ground already is — the ordered 4×4
Bayer, each 4-column block reading the matrix one row further down
([pixel-model.md](pixel-model.md#what-depth-paints-that-is-not-a-step))
— because a lift of a few bytes bands exactly as the gradient would.
The cap is the elevation floor: `paper` must stay 1.1:1 above the
brightest ground pixel ([below](#what-holds-by-construction)), and
`0x10` is where that ratio still clears against `0x1C`.

Like the ground, the pool is a function of the pixel's place in the
window, so it ships as one tile per viewport change and every frame
after is the same blit depth already does.

### Every filled box is a plate

Anything drawn with a background fill is a plate and takes all three
plate ops — rim, face, shadow — with no exceptions: cards, icon plates,
buttons, a picker's chosen row, meter tracks and meter fills, nav
plates and sheets. An exception list is a list somebody has to keep
honest against the element set; a rule stated on the fill cannot drift.

Each plate answers the lamp through a material — how bright its lit
rim runs, how bright its far rim, how strong its specular point, and
how heavy a shadow it casts. The reference's six, by role:

| Material | Role | Rim high | Rim low | Specular | Shadow weight |
| --- | --- | --- | --- | --- | --- |
| card | a card on the page | 0.28 | 0.03 | 0.34 | 1.0 |
| cta | a primary button | 0.30 | 0.05 | 0.30 | 1.2 |
| plate | an icon plate, a chosen row | 0.20 | 0.03 | 0.18 | 0.0 |
| well | a meter's track | 0.18 | 0.02 | 0.12 | 0.0 |
| fill | a meter's fill | 0.26 | 0.04 | 0.22 | 0.0 |
| chrome | a nav plate, a sheet | 0.26 | 0.03 | 0.30 | 1.0 |

A weight of zero is a plate lying on another plate's face: it runs the
shadow op like every plate, and the op casts nothing. So under lamp
light the knob and the field that depth light raises by a `.control`
shadow lie flat: lamp casts depth's drop shadows nowhere, and a plate
casts only by its material. An off plate lies flat too, as depth's off
lit plate does: a filled button disabled or working casts no shadow.

**Materials by element.** Which material each filled box answers the
lamp with, by the role it plays; the renderer's draw sites are this
table.

| Element | Box | Material |
| --- | --- | --- |
| `box` (bordered or filled), `tile_group`, `radio_group` | the card | card |
| the collapsed nav's section list | the card, on the dim | card |
| `button`, filled | the pill | cta |
| `button`, secondary or waiting on its words | the pill | plate |
| `tile` | the mark's well | plate |
| `segmented`, `ranking`, `dial` | the lit plate, a ranking row, a step button | plate |
| `picker_item` | the chosen row | plate |
| `badge`, `checkbox`, a notice in the notices pane | the chip, the box, the row | plate |
| `toggle` | the knob | plate |
| `text_input`, `text_area`, `select`, `copyable` | the field on the page | plate |
| the same | the field on a paper surface | well |
| `meter`, `diverging_meter`, a working button | the track | well |
| `toggle`, `segmented`, `dial` | the track | well |
| `meter`, `diverging_meter`, a working button | the fill, the arms | fill |
| `nav_item`, `nav_here`, `nav_current`, the notices indicator | the plate, glass | chrome |
| `sheet`, `notices_pane`, a picker, a notice banner | the pane, glass | chrome |

Not plates, and drawn as depth draws them: glyphs (a radio's discs
among them), hairlines and rules, the blockquote's bar, a diverging
meter's centre tick, a pending run's block, the QR tile and the vendor
sign-in pills (both pinned to eink's light ramp), the selection band,
the caret and its handles, and the scroll bars.

**The rim.** One device pixel of white, composited inside the plate's
edge along its whole perimeter, brightest on the side facing the lamp.
Per device pixel on the ring:

```
a0   = att(dc) · 0.65                 dc: lamp to the box's centre
t    = clamp((dFar − dp) / (dFar − dNear), 0, 1)
a    = (low + (high − low) · t) · a0
     + specular · a0 · exp(−2.2 · (ds / specR)²)
cov  = min(a + Σ edge, 0.30)
```

`Σ edge` is the light of every chrome edge reaching the plate
([below](#chrome-edges-are-lights)), zero for most of them. A rim is
**one mask, the sum of every light on it, capped once**: a cap on each
light alone is no cap on the rim, since white composited twice lands
brighter than either coverage — a card under two nav plates reached
`0x75`, stacked, while each light alone held its own cap.

where `dp` is the pixel's distance to the lamp, `dNear = max(1, dc −
min(w, h)/2)` and `dFar = dc + hypot(w, h)/2` bound it over the box,
`ds` is the pixel's distance to the rim point nearest the lamp, and
`specR = clamp(0.8 · min(w, h), 10, 30)`. The coverage cap is the rim
gate: 30% white over `paper` is `0x60`, 2.7:1, under `g7`'s `0x67`, the
first step that clears 3:1 on paper — so a lit edge never carries the
contrast a boundary or a focus change is read by, and at one device
pixel it cannot be mistaken for the 2px ring. A **well** is concave:
it mirrors the lamp through its own centre, so a track's lit inner
edge is the one away from the lamp, as a groove's is.

**The face.** A matte surface falls into shadow away from the lamp:
black composited over the fill by a darkening that is zero at the
box's nearest point to the lamp and full at its farthest. It is linear
in *squared* distance:

```
nx = max(0, |Lx − cx| − w/2)     fx = |Lx − cx| + w/2
ny = max(0, |Ly − cy| − h/2)     fy = |Ly − cy| + h/2
span = (fx² + fy²) − (nx² + ny²)
kx = ((px − Lx)² − nx²) / span   ky = ((py − Ly)² − ny²) / span
k0 = cap · att(dc) · 0.65
```

and the darkening at a pixel is `k0 · (kx + ky)`. Inside the box `d²`
lies between the nearest and farthest points' squares, so `kx + ky`
stays in `[0, 1]`, the clamp never engages, and the radial form *is*
`f(x) + g(y)` exactly. That identity is the whole reason for the
squared distance: a separable face ships as two strips — the x term
as one row repeated down, the y term as one column repeated across —
each with four corner tiles where the rounded edge covers part of a
pixel, through the route the drop shadow's nine-patch already takes to
the shim: about 12 KB a card at 3× where a per-pixel tile would be
about 750 KB. The two strips are two black composites rather than one
of their sum, and composing `(1 − a)(1 − b)` darkens by `u·a·b` less
than `1 − a − b` would. A composite also rounds, and two rounded
composites of fractional coverages overshoot the radial form's byte a
few pixels in a hundred, so each strip's coverage is chosen by the
byte it leaves on the fill instead: the x term darkens it by the floor
of its bytes and the y term by their round, each at the coverage the
compositing needs for that. So chosen, the pair lands on the radial
form's byte or one lighter, never darker.

`cap` is per fill. On `paper` it is six bytes wherever the ground
beside the box is depth's own, and less where the pool has lifted it: a
darkened paper corner must stay 1.1:1 above the ground at that corner,
and six bytes cannot over `0x10` (paper `0x16` over `0x10` is 1.05:1).
So paper's cap is the lesser of six and what that floor leaves over the
ground byte at the box's farthest point from the lamp, where the face
is darkest and the pool dimmest: six over ground `0x00`–`0x09`, then
5, 4, 4, 3, 2, 2, 1 over `0x0A`–`0x10`, and 0 over `0x11`, the
brightest byte the ground may take. A face only ever darkens: `mid` on `paper` is 4.56:1 in depth dark, which leaves one
byte of lift before AA fails, and a lamp's sheen spends more than one
byte or nothing. The reference's caps for the other fills are `ink`
13, `g11` 4, `g6` 8 and `g9` 5 bytes; color.zig's proofs own the final
value of every one.

**The shadow.** Depth light's shadow, given a direction: the same
smoothstep of signed distance to the rounded box, integer throughout
and shipped as a nine-patch of coverage tiles
([pixel-model.md](pixel-model.md#what-depth-paints-that-is-not-a-step)),
cast away from the lamp. For a caster whose centre is `dc` from the
lamp along unit direction `n`:

```
off  = (2 + 0.012 · min(dc, 1000)) · m.off
blur = min(10 + 0.07 · dc, 36) · m.blur
peak = (0.12 + 0.30 · att(dc)) · weight · 0.65 · m.peak
```

drawn in two passes: a tight contact shadow (offset `0.35 · off`, blur
`0.3 · blur`, peak `0.9 · peak`) and a wide penumbra (`off`, `blur`,
`0.6 · peak`), each box shifted by `n` times its offset and one pixel
down. So a shadow is sharper and darker the nearer its caster stands to
the lamp, and fans with the caster's place in the window. `m` is 1 for
the page; chrome stands higher — `m.off = 1.2` and `m.blur = 1.2` for a
nav plate, `1.6` blur for a sheet. What is new against depth light's
shadow is an x offset and a per-caster offset, blur and peak; the mask
is the same, so it tiles its reach once like depth's does.

### Chrome edges are lights

A frosted plate glows where it meets the page, and the page's boxes
nearest it catch that light. Each chrome edge is a short area light: a
segment inset from the edge's ends, adding to the rims of the page's
boxes just above it

```
edge = high · amp / (1 + (d / reach)²)
```

`d` being the rim pixel's distance to the segment and `high` the box's
material's rim high. It is not an op of its own: it is a term of the
rim's one sum, capped with the lamp's light
([above](#every-filled-box-is-a-plate)), so the renderer gathers the
frame's chrome edges — the bottom row's plates or the banner, and each
modal layer's top edge — before it draws the page.

| Edge | Inset | Reach | Amplitude |
| --- | --- | --- | --- |
| A sheet's top edge | 20 px | 70 px | 1.1 |
| Each nav plate's top edge | 10 px | 50 px | 1.25 on the chosen plate, 0.9 on the others |

Which of the page's boxes an edge lights is `lamp.Edge.lights`: a box
whose top is no more than 8 px below the edge, whose bottom is within
four reaches above it, and which overlaps the lit segment across. Only
the page's boxes are lit — a layer's own plates stand above every edge.

A sheet's edge light is in the page's rims, so the dim lowers it with
the page: under a sheet over the scrolled page, a card's lower rim just
above the sheet's edge is `0x3F` lit by the sheet against `0x20` by
the lamp alone, both dimmed — the sheet's light reads, and the cap
still holds beneath the dim. Each edge also lays a contact
line on the ground beside it: the shadow's smoothstep field around the
plate, unshifted, 5 px deep for a nav plate and 6 px for a sheet,
lightening toward `0x24` at a peak coverage of 0.8, never darkening
anything already brighter, and clamped at `0x11`, the brightest byte
`paper` stays 1.1:1 above. The clamp is the gate, not a margin: over a
pool at `0x10` the unclamped line reaches `0x18` at 40% coverage, and
paper stands 1.04:1 off that. Over the pool the line is a byte of lift,
not the reference's glow; the floor wins.

The contact line is the one op here whose byte depends on the byte it
lands on in a way no Skia blend spells — a lift toward a tone, clamped
at a ceiling, leaving brighter pixels alone. So the shim writes it
itself: its coverage ships as the shadow's pieces, and each pixel they
reach takes the byte `lampGlowByte` gives for its own byte, from a
table nokre builds from that function. It reads no neighbour, so it
bands and repaints like any composite.

**Rejected: a haze.** A wide leak of light onto the ground around the
chrome, toward `0x2C`, was refused as unmanaged: it reads as mood
rather than as an edge, and at that byte it lifts the ground past the
elevation floor the pool is capped at.

### Frosted chrome

Nav plates and sheets are frosted glass: they show the page beneath,
blurred, instead of an opaque fill — and so are the notices indicator,
a notice banner, the notices pane and a picker. A banner and the
indicator frost as nav plates do, the panes as a sheet does.

- **Blur.** The frame beneath the plate blurred by three passes of a
  separable integer box blur — close to a Gaussian, deterministic, and
  nokre's own arithmetic rather than Skia's, whose blur would be its
  pixels — at half resolution. The frame is first averaged 2×2 into a
  half frame, each value the four bytes' mean in 8.8 fixed point
  exactly. Each pass sums the `(2r+1)²` box around a half pixel, its
  indices clamped into the half frame (so its edges are replicated,
  pass by pass), and divides once, rounding; the values between passes
  stay 8.8. The result is sampled back to every device pixel
  bilinearly — a device pixel's centre lies a quarter of a half pixel
  from the nearest one's, so the weights are ¼ and ¾ — with the half
  plate's edge samples replicated and one rounding. Radius 9 logical px
  for nav plates and 12 for a sheet, times the scale, halved at half
  resolution; two scales are mixed, 65% of the wide blur and 35% of one
  at a third of the radius (halved, at least 1), so the shapes passing
  beneath keep structure instead of turning to fog. The read reaches
  twice the three half radii, plus two device pixels, past the plate
  (`Glass.reach`).

  The full-resolution blur is the reference, and stays in the code as
  `lamp.frostBlur`: at 2× and 3× the half-resolution frost is within two
  bytes of it — over a kitchen sink frame about one byte in ten moves by
  one and one in ten thousand by two — and at 1×, where the fine radius
  halves to a single pixel, within four (lamp_test holds both on a
  deliberately harsh frame). Away from the frame's edge, that is: there
  the half frame replicates the mean of the edge pixel and its
  neighbour, where the full one replicated the edge pixel alone, and a
  hairline on the window's very edge moves the frost beside it further.
  The half resolution halves the frost's time; its bytes are the
  goldens'.
- **Gain and tint.** The mix is lifted by a gain of 1.35 (capped at
  255), so what shows through reads as light, and shown through a paper
  tint at 58% coverage — `g9` for the chosen nav plate.
- **Grain.** A fixed per-device-pixel hash, high-passed by its own 3×3
  mean, so it is fine and directionless, at most ±2.5 bytes:

  ```
  h     = x · 374761393 + y · 668265263             (wrapping, 32-bit)
  h     = (h ^ (h >> 13)) · 1274126177
  hash  = (h ^ (h >> 16)) >> 24                     (its top byte)
  g     = 9 · hash(x, y) − Σ₃ₓ₃ hash                (±2040)
  grain = g · 2.5 / 2040                            (±2.5 bytes)
  frost = tint · 0.58 + seen · 0.42 + grain
  ```

  The reference wrote `(hash − mean₃ₓ₃) · 1.5 · 5` and called it
  "about ±2.5"; its extremes are ±6.7 bytes. nokre takes the stated
  ±2.5 as the peak, so the grain moves a frost byte by three at most
  and has no mean over any block (both held by a test). No state and
  no randomness: the same pixel always carries the same grain, however
  the page beneath scrolls. Not interleaved-gradient noise, whose
  pattern runs along a diagonal and reads as texture with a direction.
- **Dim, not veil.** Under a sheet the page is dimmed 30% toward black
  (`v · 0.7`) instead of depth's even veil. The frost is what says
  "out of reach", so the page beneath keeps its shapes for the glass
  to show.
- **Generation.** A backend keeps a frost for as long as its caller's
  generation stands. The renderer's is a hash of everything drawn
  beneath the glass by the time the frost is drawn: the damage model's
  whole-frame inputs (the viewport, the safe band, the appearance, the
  scroll presentation, the direction, the shape, and
  `DamageInputs.unbounded_changes`), then every scroll owner as it is
  noted — offset, overshoot, extent, bar tone and rect — and every
  focus as it is drawn. So the nav's frost takes a new generation on
  every window scroll frame, a sheet's on any change to the page or the
  window beneath it, and neither on a scroll of the sheet's own region,
  which is drawn after its frost.
- **Glass answers the lamp at full strength.** A frosted face falls off
  three times harder than its tint's (`k0 × 3`) and also catches a white
  sheen toward the lamp, coverage `s · (1 − (kx + ky))` with `s = 0.06 ·
  att(dc) · 0.65`. Measured on a full-width sheet: 40 near the lamp, 26
  at the far corner. Paper cannot do this — its six-byte cap made a 500
  px sheet vary by three bytes, which reads as flat — but a frosted fill
  is outside the text proofs already ([below](#what-is-waived)), so
  its face is not held to them. The sheen is not separable, so it is
  drawn as `s` over the whole plate and the face's two strips take it
  back toward the far corner along with the darkening — `s − (3·cap +
  s) · (kx + ky)`, a fill and two strips, within a byte of the
  reference's per-pixel form over the tint. The frost is drawn first,
  then the sheen and the face, then the rim.

**Rejected: glyph glow.** Bloom from the chrome's ink-tone glyphs or
its primary button, through the glass or onto the page, in any form.
Light around a glyph changes the very bytes a text proof measures that
glyph against.

## The light appearance

Depth light's paper is `0xFF` over a ground of `0xF3`–`0xEF`. There is
no byte above paper to spend, so the pool, the rims, the faces and the
edge lights do not exist in light: a lamp in daylight is invisible.
What the theme keeps in light is direction and glass.

- **Shadows** are depth light's, given a direction from a lamp *above*
  the window — 50% across, 15% of the window's height above its top
  edge — as the sun. They still never point up (a caster above the
  sun's height would cast upward, so the direction's upward part is
  dropped); they fan with x and sharpen near the top, by the dark
  formula with its peak scaled ×0.4.
- **Frost** is the dark recipe with a gain of 0.95, and under a sheet
  the page is lifted 30% toward white (`v + (255 − v) · 0.3`) instead
  of depth light's white veil.
- **Reduce Transparency** in light is depth light as shipped
  ([below](#what-the-end-user-sees)).

## What holds by construction

Each of these is a proof in [color.zig](../../src/core/color.zig), run
over every ramp its gate applies to, and a byte that breaks one fails
the build:

- `paper` stays 1.1:1 above the brightest ground pixel the theme can
  draw, the pool and the contact lines included — the floor depth's
  ground is already proved to.
- The rim's brightest byte on `paper` stays under `g7`'s `0x67`: at
  most `0x60`, however many lights reach it, because the rim is one
  mask capped once. The golden suite checks it too, over every
  lamp-dark take against depth dark's bytes pixel for pixel.
- A face on `paper` only darkens, by at most six bytes and by less over
  a ground the pool has lifted, and never lifts: one byte of lift is all the headroom `mid` on `paper` has.
- lamp's thirteen ramp bytes are depth's, in both appearances — one
  proof asserts the equality, so every text and focus proof depth
  passes, lamp passes on the same bytes.
- depth and eink keep every byte they had: their goldens are the
  regression gate, byte-identical.

And by the pixel model rather than a proof: no clock, no sensor, no
timer. A frame renders when state changes and otherwise nothing runs.

## What is waived

Two things, both on record in
[pixel-model.md](pixel-model.md#the-one-waived-gate) beside depth's
1.4.11 waiver, which lamp inherits with depth's bytes: text on a
frosted fill cannot be gated, and the frost reads pixels. Neither is
restated here.

## What a frame costs

At 3× on a phone, per scroll frame unless stated:

| Op | Cost | Note |
| --- | --- | --- |
| Rim | ≈7 KB per page plate | four edge strips, four corner tiles |
| Face | ≈12 KB per page plate | two strips, each a row or a column and four corner tiles |
| Shadow | ≈9 KB per page caster | the nine-patch depth light uses today |
| Chrome's rims, faces, shadows and contact lines | none per scroll frame | kept by the surface across frames |
| Ground pool | one ≈3 MB tile per viewport change | kept by the surface across frames, then the same blit as today |
| Edge lights | none of their own | a term in the rim's one mask |
| Frost, nav | ≈1.5 M adds | two half-resolution blurs under one 390×48 bar; per scroll frame |
| Frost, sheet | ≈12 M adds once per open | two half-resolution blurs under a full-width 560-tall sheet; kept while the sheet is up |

Everything but the frost is a tile nokre computes and the shim samples
nearest in device space, the path depth's three ops already take. A
plate on the page moves with every scroll frame, so its tiles are
filled again each frame it shows — and only then: a mask the frame or
its clips cannot show is never given tiles. Chrome stands where the
window puts it, so the shim keeps its masks (the last 32) under a key
of every input its bytes are a function of — the rect, radius,
material, finish, window, scale, look and edge lights — and a frame
that asks for the same key fills nothing (canvas_skia.zig's
`ChromeKey`; skia_test flips each input and holds the kept bytes to a
fresh fill's).

The frost is the one op whose cost scales with what it covers and
recurs per scroll frame. Its counts are derived, at 3× in a 390×844
window: a pass is a running sum across then down, two adds a value
plus `2r+1` to start each row and column, computed only where the next
pass reads (the plate out to `2r`, then `r`, then the plate). At full
resolution a 1170×144 bar at `r = 27` was 3.4 M adds for the wide blur
and 2.5 M for the fine one at `r = 9`, and a 1170×1680 sheet at
`r = 36`, clamped by the window's sides and bottom, 25.0 M and 24.0 M
at `r = 12`. At half resolution the same bar is 0.85 M and 0.62 M at
`r = 13` and `4`, the sheet 6.2 M and 6.0 M at `18` and `6`, plus
four reads a half pixel for the 2×2 mean (0.36 M, 2.1 M). On top of
the blurs, each plate pixel is still sampled, hashed once and mixed at
full resolution — 0.17 M pixels for the bar, 2.0 M for the sheet.

Measured on an M4 Mac with `zig build bench-lamp -Dskia`, the kitchen
sink in lamp dark, mean ms per frame (every one a whole frame):

| Scene | 1440×900@2 | 390×844@3 |
| --- | --- | --- |
| Window scroll | 6.3 | 3.7 |
| Sheet open | 12.7 | 13.4 |
| Scroll inside the sheet | 8.9 | 8.1 |
| Focus move | 10.5 | 9.8 |
| The sheet's frost alone | 7.5 | 11.2 |

A Debug build is within a few milliseconds of those (window scroll 8.2
and 6.3): the per-pixel loops are lamp_pixels.zig, compiled at
ReleaseFast into every build as the Skia shim is (build.zig's
`addLampPixels`). Before that, a Debug scroll frame took 98 ms.

**The CPU did not keep up, so lamp moves to the GPU.** The window
scroll's 6 ms at 1440×900@2 is the measurement that decided it: at full
screen, where depth scrolls smoothly, lamp visibly does not, and the
effects are not to be reduced to fit. The owner reversed the GPU
refusal for this theme on 2026-09-26; the decision, what stays on the
CPU, and the proof it waits on are [gpu.md](gpu.md).

## What the end user sees

There is no theme picker, and nokre offers none: an app declares its
look, and the reader gets two accessibility preferences nokre owns —
Increase Contrast, which draws `eink`, and Reduce Transparency, which
draws `depth` in place of `lamp`. Each follows the OS's own setting
unless the reader overrides it in the app. The resolution order, the
OS signals per platform, and where each row is shown are
[accessibility.md](../accessibility.md#increase-contrast-and-reduce-transparency);
the element that carries the rows is
[elements.md](../elements.md#accessibility_toggles). A change of the
resolved look is a change of theme: one whole frame, and nothing
reflows ([pixel-model.md](pixel-model.md#partial-frames)).

## Skia only

Every op above is nokre's own arithmetic over a frame nokre owns, and
only the Skia substrate owns its frame. On the DOM substrate `lamp`
resolves to `depth`: the document root says `depth`, and the page never
offers Reduce Transparency, because there is nothing for it to reduce
([dom-substrate.md](dom-substrate.md#the-four-facts-no-markup-carries)).
The same holds everywhere outside the Skia renderer that switches on a
theme — packaging's launch screens and window backgrounds, the
`theme-color` metas, the share card and the store shots: to them lamp
*is* depth. Whether the browser could draw the theme its own way is
[../explorations/frosted-dom.md](../explorations/frosted-dom.md), and
parked.

## Implementation order

Pool, rim, shadow, faces, edge lights, frost — each its own golden
review, and each cap added to color.zig's proofs before the renderer
draws the op it bounds. The ground's floor bounds everything drawn over
it, so it comes first; the frost is the only op that reads pixels, so
it comes last, over a frame whose every other byte is already settled.
