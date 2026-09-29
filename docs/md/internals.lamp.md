# The lamp theme

`lamp` is the third look beside `eink` and `depth`: depth's surfaces
under one light. Its thirteen ramp bytes are depth's in both
appearances, every rect and metric is depth's, and what it changes is
paint alone, in the dark appearance alone — in light it is depth light,
byte for byte ([below](#the-light-appearance)) — on the Skia substrate
alone. This page is the design
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
holds the draw itself: lamp dark's recording with its own ops set aside
is depth dark's, op for op, but for its substitutions — a frost stands
where depth filled the same glass, a lit glyph where depth drew the
same glyph in ink ([below](#glyphs-on-plates-are-lit-surfaces)), and a
button's and an on switch's knob's fills and words are repainted
([below](#buttons-under-the-lamp)). Lamp light's recording is depth
light's with nothing set aside.

## The dark appearance

The dark appearance is where the lamp exists: depth dark's paper is
`0x1C`, and lamp's ground under it is a void of `0x00`, which leaves
room to light things. The ops, in paint order:

1. **The page.** The ground; then each filled box as it is drawn — its
   shadow, its fill, its face and its rim, the rim lit by the lamp and by every chrome edge that
   reaches it at once
   ([below](#chrome-edges-are-lights)) — with the text and the rules on
   it drawn after it as in depth, and an icon glyph on it lit as its
   surface is ([below](#glyphs-on-plates-are-lit-surfaces)). So the
   chrome's edges are known before the page is drawn.
2. **The bottom row.** First every plate's contact shadow: each nav
   plate's and the notices indicator's. Then plate by plate: its
   shadow, its frost, its glass face and rim, its lit glyph and its
   words. A notice banner in the row's place takes a nav plate's
   treatment.
3. **Each modal layer** — a sheet, the notices pane, a picker — in the
   order they stack: the dim over everything drawn so far, the layer's
   shadow, its contact shadow, its frost, its glass face and rim, then
   its content, whose filled boxes are plates like the page's and which
   no edge lights. The collapsed nav's section list is a card on the
   dim, not glass.

### The ground is a void

Lamp dark's page ground is `0x00` at every pixel: lamp's own ground
(`color.pageGround(.lamp, .dark)`), where depth dark keeps its gradient
from `0x08`. The owner decided it on 2026-09-27, over a pool of light
under the lamp that the design first drew:

- **The plates say where the lamp is.** Every rim brightens toward it,
  every face falls away from it, every shadow points away from it. A
  pool on the ground says it a fourth time, on the one surface nothing
  stands on.
- **A bloom puts a surface where the eye wants nothing.** Lit, the
  ground between the cards reads as something to look at; black, it
  reads as the room the cards float in.
- **OLED off.** A true-black pixel emits nothing, and the ground is
  most of a frame.
- **The faces get their headroom back.** A lifted ground bounded paper's
  face: a darkened paper corner must stay 1.1:1 above the ground beside
  it, and over the pool's `0x10` twelve bytes of darkening could not
  ([below](#every-filled-box-is-a-plate)). Over the void the full
  twelve hold everywhere.

No lamp op lifts the ground: the chrome's contact line, which did, is
a contact shadow since 2026-09-27, and a shadow over `0x00` leaves
`0x00` ([below](#chrome-edges-are-lights)). The ground is flat, so it
is the 16-column tile depth's ground takes, every byte the same.

### Every filled box is a plate

Anything drawn with a background fill is a plate and takes all three
plate ops — rim, face, shadow — with no exceptions: cards, icon plates,
buttons, a picker's chosen row, meter tracks and meter fills, nav
plates and sheets. An exception list is a list somebody has to keep
honest against the element set; a rule stated on the fill cannot drift.

Each plate answers the lamp through a material — how bright its lit
rim runs, how bright its far rim, how strong its specular point, and
how heavy a shadow it casts. The reference's six, and the knob, by
role, as the owner tuned them on a live mockup (2026-09-27): every
specular at 1.0, which the rim's cap still bounds, so it widens and
hardens the hot corner rather than brightening it, and the well's and
the knob's rim high raised:

| Material | Role | Rim high | Rim low | Specular | Shadow weight |
| --- | --- | --- | --- | --- | --- |
| card | a card on the page | 0.28 | 0.03 | 1.0 | 1.0 |
| cta | a primary button | 0.30 | 0.05 | 1.0 | 1.2 |
| plate | an icon plate, a chosen row | 0.20 | 0.03 | 1.0 | 0.0 |
| knob | a control standing on a track | 1.0 | 0.04 | 1.0 | 1.0, as a control |
| well | a meter's track | 0.50 | 0.02 | 1.0 | 0.0 |
| fill | a meter's fill | 0.26 | 0.04 | 1.0 | 0.0 |
| chrome | a nav plate, a sheet | 0.26 | 0.03 | 1.0 | 1.0 |

A weight of zero is a plate lying on another plate's face: it runs the
shadow op like every plate, and the op casts nothing. Depth dark casts
no drop shadow, so a plate in lamp dark casts only by its material. An
off plate lies flat too, as depth's off lit plate does: a filled button
disabled or working casts no shadow, and neither does a disabled
segmented's or dial's lit plate. An off switch's knob casts, as depth
light's does, onto its dark well; an on switch's lies flat, in the off
knob's gray (`.g6`, `.g9` disabled), with its face and rim. The on
track is `ink`, the brightest surface in the scene, and reads as
luminous: a matte knob casting onto a light source reads wrong. The
track's fill carries the state, as it does in depth.
A radio's chosen disc is `ink` too and lies flat for the same reason:
a plate in its fill with its face and rim, no shadow op, and its dot a
mark on it. An empty disc is a small well, as an off track is, whose
inverted rim is the only edge it has (owner's, 2026-09-27).

The knob is the owner's (2026-09-27): a switch read flat, a `well`
track under a `plate` knob, both near the dimmest numbers in the table
and the knob casting nothing. A knob is raised — the brightest rim
high of any material, and the heaviest shadow for its size — and stands on its track the way a card
stands on the page, but a pixel off it rather than the page's 2 to 14
(the control caster, under "The shadow" below); a
segmented's and a dial's lit plate stand on theirs the same way.

**Materials by element.** Which material each filled box answers the
lamp with, by the role it plays; the renderer's draw sites are this
table.

| Element | Box | Material |
| --- | --- | --- |
| `box` (bordered or filled), `tile_group`, `radio_group` | the card | card |
| the collapsed nav's section list | the card, on the dim | card |
| `button`, filled (primary) | the pill, a `.g9` plate | cta |
| `button`, secondary | no plate: its stroke alone, no fill ([below](#buttons-under-the-lamp)) | none: a `.g6` stroke, lit on its own, as a pool row is |
| `button`, waiting on its words | the pill | plate |
| `tile` | the mark's well | plate |
| `segmented`, `dial` | the lit plate | knob |
| `ranking`, `dial` | a ranking's item row (a choice while picking among them), a step button | plate |
| `ranking`, picking | a pool row | none: a `.g6` stroke, lit on its own, one tone all the way round and nothing the lamp answers (owner, 2026-09-28; docs/elements.md, picking) |
| `picker_item` | the chosen row | plate |
| `badge`, `checkbox`, a notice in the notices pane | the chip, the box, the row | plate |
| `toggle` | the knob, lying flat when on | knob |
| `radio_group` | the chosen disc, lying flat | plate |
| `text_input`, `text_area`, `select`, `copyable` | the field on the page | plate |
| the same | the field on a paper surface | well |
| `meter`, `diverging_meter`, a working button | the track | well |
| `toggle`, `segmented`, `dial` | the track | well |
| `radio_group` | an empty disc | well |
| `meter`, `diverging_meter`, a working button | the fill, the arms | fill |
| `nav_item`, `nav_here`, `nav_current`, the notices indicator | the plate, glass | chrome |
| `sheet`, `notices_pane`, a picker, a notice banner | the pane, glass | chrome |
| a pending run, under a `stand_in` | the block, lying flat | plate |

Not plates, and drawn as depth draws them: glyphs off a plate (the
glyphs on one are [below](#glyphs-on-plates-are-lit-surfaces)), a
radio's dot, hairlines and rules (a ranking's line among them), the
blockquote's bar, a diverging meter's centre tick, the QR tile and the
vendor sign-in pills (both pinned to eink's light ramp, the pills in
their vendors' fills), a `link` (words, not a box), the selection
band, the caret and its handles, and the scroll bars.

**The rim.** One device pixel of white, composited inside the plate's
edge along its whole perimeter, brightest on the side facing the lamp.
Per device pixel on the ring:

```
a0   = att(dc) · 0.65                 dc: lamp to the box's centre
t    = clamp((dFar − dp) / (dFar − dNear), 0, 1)
a    = (low + (high − low) · t) · a0
     + specular · a0 · exp(−2.2 · (ds / specR)²)
cov  = min(a + Σ edge, cap)
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
gate: `color.lamp_rim_coverage_cap`, 83 of 255, lands `paper` on
`0x66`, 2.97:1, one byte under `g7`'s `0x67`, the first step that
clears 3:1 on paper — so a lit edge never carries the
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
the shim: about 22 KB a card at 3× where a per-pixel tile would be
about 750 KB. The two strips are two black composites rather than one
of their sum, and composing `(1 − a)(1 − b)` darkens by `u·a·b` less
than `1 − a − b` would. A composite also rounds, and two rounded
composites of fractional coverages overshoot the radial form's byte a
few pixels in a hundred, so each strip's coverage is chosen by the
byte it leaves on the fill instead: each term darkens it by its bytes
dithered ([below](#rounding-is-dithered)), at the coverage the
compositing needs for that. So chosen, the pair lands on the radial
form's floor or ceiling, or one lighter, and never past the cap.

`cap` is per fill, twice the reference's table as the owner tuned it.
On `paper` it is twelve bytes over the void — `0x10`, where `mid`
still reads at 5.09:1 — and would be less over a lifted ground: a
darkened paper corner must stay 1.1:1 above the ground at that corner,
and twelve bytes cannot over anything but the void. So paper's cap is
the lesser of twelve and what that floor leaves over the ground byte
at the box's farthest point from the lamp, where the face is darkest:
twelve over ground `0x00`, then 11, 10, 10, 9, 8, 7, 7, 6, 6, 5, 4, 4,
3, 2, 2, 1 over `0x01`–`0x10`, and 0 over `0x11`, the brightest byte
the ground may take — and the ground there is the void's `0x00`, so
every paper face takes the twelve. A face only ever darkens: `mid` on
`paper` is 4.56:1 in depth dark, which leaves one byte of lift before
AA fails, and a lamp's sheen spends more than one byte or nothing. The
other fills' caps are `ink` 26, `g11` 8, `g6` 16 and `g9` 10 bytes;
color.zig's proofs own the final value of every one.

**The shadow.** Depth light's shadow, given a direction: the same
smoothstep of signed distance to the rounded box, integer throughout
and shipped as a nine-patch of coverage tiles
([pixel-model.md](pixel-model.md#what-depth-paints-that-is-not-a-step)),
cast away from the lamp. For a caster whose centre is `dc` from the
lamp along unit direction `n`:

```
off  = (2 + 0.012 · min(dc, 1000)) · m.off
blur = min(10 + 0.07 · dc, 36) · m.blur
peak = (0.12 + 0.30 · att(dc)) · weight · 0.65 · m.peak · gain
```

drawn in two passes: a tight contact shadow (offset `0.35 · off`, blur
`0.3 · blur`, peak `0.9 · peak`) and a wide penumbra (`off`, `blur`,
`0.6 · peak`), each box shifted by `n` times its offset and one pixel
down. So a shadow is sharper and darker the nearer its caster stands to
the lamp, and fans with the caster's place in the window. `m` is 1 for
the page; chrome stands higher — `m.off = 1.2` and `m.blur = 1.2` for a
nav plate, `1.6` blur for a sheet. A **control** — a knob — stands a
pixel off its track wherever it is in the window, so its `off` and
`blur` are depth light's `.control` shadow's, 1 px and 3 px, and only
its direction and its peak (`m.peak = 1`) come from the lamp. Depth
light's peak, 14 of 255, does not carry over: over a dark track it
darkens two bytes and shows nothing. `gain` is the owner's
(2026-09-27): 0.5 for the page's and the chrome's casters, 2.0 for a
control's. What is new against depth light's
shadow is an x offset and a per-caster offset, blur and peak; the mask
is the same, so it tiles its reach once like depth's does.

**No inset shadow.** A well once took its own shadow inside it, along
the inner edge facing the lamp; the owner removed it (2026-09-27). A
well is concave by its rim alone — the lit edge is the far one
([the rim](#every-filled-box-is-a-plate)) — and its face.

### Buttons under the lamp

A white fill in a lit dark scene is a second lamp. Depth dark's
primary is an `ink` pill, `0xBD`, and under the lamp it read as a
light source rather than as a lit object; so the owner (2026-09-27)
stepped the forms down one each, paint only, in lamp dark only: the
primary is a filled plate, the secondary its stroke alone, and a
link stays words.

- **Filled.** A `cta` plate in `.g9`, `0x3B`, the chosen plate's tone,
  with `ink` words — the pair depth's tonal-fill proof already covers.
  `cta` because the role is the primary act's: the heaviest shadow
  weight at the page's ×0.5 gain says it can be taken now. Disabled, the
  plate is the off well's `.g11` with `disabled_ink`, and lies flat, as
  it does working. Working, its inner track is depth's, inside the plate.
- **Secondary.** Its `.g6` stroke alone, 1 point at the pill's
  corner, over no fill: the pool row's drawing, from the one function
  (the renderer's `drawStrokeFace`), and eink's. It is lit on its own —
  one tone all the way round, wherever the button stands — and nothing
  the lamp answers: no face, no well, no shadow. The words are `ink`,
  which clears every ground already. `.g6` is 4.12:1 on the void, 3.34:1
  on paper and 3.01:1 on a `.g11` well (color.zig proves all three). On
  the brightest frosted glass measured, `0x2B`, it is 2.78:1: glass is no
  opaque ground, and the stroke on it joins the waiver for text on a
  frosted fill
  ([pixel-model.md](pixel-model.md#what-lamp-waives-beside-it)).

  Until 2026-09-29 this form was a reflective ring, lifting what was
  beneath toward white by where it stood under the lamp; the owner asked
  for a solid stroke instead, and the ring, its shaders and its byte
  table went with it. Disabled, the stroke is `.g10`, with
  `disabled_ink` words, as the pool row's. Working with a percentage,
  the stroke's interior fills in the ambient track's `.g10` from the
  leading edge up to it, a flat fill, and the stroke lies over it. Focus
  is the in-place 2 px `ink` edge, as in depth: a change of width from 1
  to 2 points as well as of tone, since `ink` over `.g6` is 2.71:1, as it
  is on the pool row.
- **The vendor pills** are the exception, as everywhere: Apple's and
  Google's keep their store-facing fills, pinned to eink's light ramp.

Nothing moves: role, label and states are depth's, and depth and eink
draw every byte they did.

### Glyphs on plates are lit surfaces

An icon glyph standing on a plate is part of the lit scene, not ink
printed on it. A flat glyph in depth dark's `ink` is `0xBD`, the
brightest thing in a lit scene by far, and it read as printed on top of
the light rather than lit by it. So the glyph is a small lit object of
its own: the lamp's light normalised over the glyph's own ink box —
the run's glyph bounds, rounded out to device pixels — from a peak at
the pixel nearest the lamp to a floor at the farthest, linear in the
squared distance as a face's darkening is
([above](#every-filled-box-is-a-plate)):

```
t    = (d² − near²) / (far² − near²)
cov  = min(floor + (peak − floor) · (1 − t)
           + specular · exp(−2.2 · (ds / specR)²) + Σ edge, peak)
```

white composited over what the glyph stands on by `cov` times the
glyph's own coverage. `d` is the pixel's distance to the lamp, `near`
and `far` the ink box's nearest and farthest pixel centres'; the
specular stands at the nearest, `specR` two fifths of the box's
shorter side and its strength half of `peak − floor`, so it widens the
peak into a hot corner rather than passing it. `Σ edge` is every chrome
edge lighting the plate, by the rim's formula
([below](#chrome-edges-are-lights)). A well mirrors the lamp through
the box's centre, so its far corner is the lit one.

- **The two numbers** are `color.lamp_glyph_peak_coverage` and
  `color.lamp_glyph_floor_coverage`: `0xB2` and `0x35` on `paper`. They
  are coverages of white, so on a brighter fill each lifts by the same
  share of what is left above it: `0xB5` / `0x3D` on the `g11` well,
  `0xBC` / `0x51` on the chosen nav plate's `g9` (the frost's brightest
  tint), `0xA8` / `0x1C` over the void. The peak clears 3:1 on
  `paper` — a control's glyph is to be found — and stays under `ink` on
  every one of them: the owner asked for `0xBC` on `paper`, and `g9`
  bounds it, since the same coverage lifts `g9` further, so the peak
  is the largest coverage that keeps `g9` at `0xBC`, one under `ink`; the floor never falls under any material's rim
  `low` on the same fill. The proofs are
  [color.zig](../../src/core/color.zig)'s.
- **Why not the plate's field.** Normalised over the plate, a 24 px
  glyph spans a sliver of the plate's range and reads flat — a nav glyph
  measured `0x45` at its brightest against a `0x40` floor — and its
  peak was the rim's cap. Normalised over its own box, every glyph
  carries the whole range corner to corner, wherever it stands.
- **Why the rim's cap does not bound it.** The rim's `0x66` keeps a lit
  edge from carrying a boundary's 3:1
  ([above](#every-filled-box-is-a-plate)); a glyph is not an edge, and
  the control it names is one to find, so its peak carries the 3:1 the
  rim is kept from.
- **Where.** Every icon-only control's glyph, and the glyphs whose
  surface is a plate: an icon button's (on its bar plate, its notice or
  its pane), a sheet's close (on the sheet's glass), a nav item's,
  marker's and collapsed chip's glyph and the chip's chevron (on the
  nav plate), the dial's step glyphs (on their buttons), a tile's mark
  (on its well) and chevron (on its group's card), and a select's
  chevron (on its field). The back control and a header action stand
  on the page ground, on no plate: each answers as a `plate` standing
  on its own target, and is lit over its ink box as every other is. A
  disabled one is lit too: its plate and its words carry the state.
- **What stays ink.** A checkbox's mark, a radio's dot, a notice's
  icon, the standalone `icon` element, a ranking's glyphs, a picker
  row's and every glyph inline in reading text: each is a mark to be read against its ground, not the
  surface of a control, and each keeps its text proof. In light every
  glyph is ink: lamp light is depth light.

It is a canvas op of its own (`litGlyph`): the run is shaped and placed
as any run is, and the lit field is its paint. Its plate chooses the
material and the edge lights; the shim hands back the run's ink box,
and the field is planned over it. On the CPU the field is a tile over
that box and two pixels of fringe, which the glyph's coverage samples;
on the GPU the glyph's own shader is the paint, over the same field,
within 2 bytes of the tile ([gpu.md](gpu.md#what-the-shaders-measure)).
A glyph's semantics are its label, so the accessibility snapshot does
not see any of this. What it costs the contrast gates is
the third waiver ([below](#what-is-waived)).

### Chrome edges are lights

A frosted plate's edge is a light where it meets the page, and the
page's boxes nearest it catch that light. Each chrome edge is a short
area light: a segment inset from the edge's ends, adding to the rims
of the page's boxes just above it

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
still holds beneath the dim.

**Each edge also casts a contact shadow**: the shadow's smoothstep
field around the plate, unshifted, 5 px deep for a nav plate and 6 px
for a sheet, black at a peak coverage of 0.20
(`color.lamp_contact_shadow_peak`, 51 of 255), composited over what is
beneath. The field is centred on the edge, so the first pixel outside
takes about 0.09 and the peak lies inside, under the glass. It only
darkens: over the void it leaves `0x00`, so it shows only where the
page passes under the chrome, as a soft dark edge — over a scrolled
card at `0x18` beside a nav plate, the last three pixels before the
rim are `0x17`, `0x17`, `0x16`. It is drawn before the plate's frost,
which reads the frame beneath, so the frost blurs the darkened page
under the glass's edge, as it blurred the contact line's lift.

It was a contact *line* until 2026-09-27: a lift of the ground beside
the edge toward `0x24` at a peak coverage of 0.8, clamped at `0x11`,
the brightest byte `paper` stays 1.1:1 above. A Mac's display had
hidden the lift; on an Android tablet's LCD it read as a glow around
every nav pill on the void (1, 2, 4, 5, 7, 9, 11, 13 up to the rim). The owner decided it on 2026-09-27: "the glow wass supposed to
be a shadow, right? we have alpha channel, I'd say go with pitch black
and give it some alpha channel", and then set the alpha at 0.20. So it
is a shadow, drawn by the shadow's route on the CPU and the GPU, with
no table and no blend of its own.

What it costs the words passing under it: text and the paper it is on
darken by the same coverage, which narrows the pair. At the peak, which
lies inside the edge, `ink` on `paper` is 6.2:1 and `dark` 4.9:1 —
color.zig proves both keep AA — and `mid` 3.35:1; on the first pixel
outside the edge `mid` is 4.0:1. The chrome's directional shadow darkens
the same content further out; neither is gated, because what lies under
the chrome's edge is passing beneath it — at rest, nothing is
([pixel-model.md](pixel-model.md#what-the-chromes-shadows-cost-what-passes-under-it)
records how far, in each shape, as the owner's position of 2026-09-28).

**Rejected: a haze.** A wide leak of light onto the ground around the
chrome, toward `0x2C`, was refused as unmanaged: it reads as mood
rather than as an edge, and at that byte it lifts the ground past
`paper`'s elevation floor.

### Frosted chrome

Nav plates and sheets are frosted glass: they show the page beneath,
blurred, instead of an opaque fill — and so are the notices indicator,
a notice banner, the notices pane and a picker. A banner and the
indicator frost as nav plates do, the panes as a sheet does.
A pane's glass, rim, shadow and contact shadow are all drawn on its body
at the pane's corner (`layout.modal_pane_radius`), twice a card's in
every look ([elements.md](../elements.md#sheet), the owner's decision
of 2026-09-27), so every effect follows the larger arc.

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
  at the far corner. Paper cannot do this — its cap, six bytes then, made a 500
  px sheet vary by three bytes, which reads as flat — but a frosted fill
  is outside the text proofs already ([below](#what-is-waived)), so
  its face is not held to them. The sheen is not separable, so it is
  drawn as `s` over the whole plate and the face's two strips take it
  back toward the far corner along with the darkening — `s − (3·cap +
  s) · (kx + ky)`, a fill and two strips, within a byte of the
  reference's per-pixel form over the tint. The frost is drawn first,
  then the sheen and the face, then the rim.

**Rejected: glyph glow.** Bloom from the chrome's glyphs or its
primary button, through the glass or onto the page, in any form. Light
around a glyph changes the very bytes a text proof measures that glyph
against; a lit glyph ([above](#glyphs-on-plates-are-lit-surfaces))
changes its own bytes and nothing around it.

### Rounding is dithered

Every lamp op computes in fractions and rounds to a byte at the end,
and below about `0x30` one byte is a visible step: a paper face
darkening a dozen bytes across a 350 px card stepped every 30 px or
so, and a sheet's frost falling sixteen levels over 500 px drew
sixteen bands the grain did not hide. So where a smooth field is
quantised, the rounding is an ordered dither: the field's level in
sixteenths of a byte rounds up at a device pixel where its sixteenths
pass the page ground's threshold there — the ground's shifted 4×4
Bayer (lamp_pixels.zig's `orderedThreshold`), fixed to the frame as
the ground's pattern and the frost's grain are, so a scrolled page's
pattern stays put. Over any sixteen columns of a row every threshold
occurs once, so a level the row holds is its mean exactly, and a
block's mean is its field's within a sixteenth of a byte.

- **Faces.** Each strip's level is its term's darkening to the nearest
  sixteenth, dithered, and the strip's coverage is the one leaving that
  byte. The down strip dithers against the pattern's complement, so the
  two strips round up at disjoint thresholds and together darken by
  the floor or the ceiling of their sum — never past the cap, which
  two strips rounding up together could pass by a byte. A strip then
  repeats by the pattern's period rather than one row or column: the
  across strip four rows deep, the down strip sixteen columns wide.
  On glass the down strip stays a fraction: it lands on the frost,
  whose own rounding is dithered and grained.
- **Frost.** `frostByte`'s last rounding, from 256ths, is the same
  dither; the grain stays as it was, a separate, designed texture.
- **Not dithered.** A rim and a lit glyph are a pixel wide or a small
  box, and do not band. A shadow, the contact shadow included,
  composites over whatever is beneath, which the planner does not
  know, and a coverage step moves that byte by `under/255` — a ninth of
  a byte over `paper` — so a dither in the coverage cannot break a step
  in the byte; it falls on the void almost everywhere, which neither
  darkens nor bands. Over a card the contact shadow is 5 or 6 px deep
  and a few bytes at most, so it steps a byte a pixel or two at a time:
  on the scrolled page it runs `0x18`, `0x17`, `0x17`, `0x16` into the
  rim, with no run to band.

The GPU's shaders compute the same threshold from the device pixel in
integers, so the two paths round alike.

What it cannot do: the frame stays 8-bit. At the darkest levels one
byte is still a visible jump, and dithered it reads as faint grain
where rounded it read as a band.

## The light appearance

A lamp in daylight is invisible: depth light's paper is `0xFF`, there is
no byte above it to spend, and the theme is a dark-appearance
phenomenon. So in light lamp *is* depth light, byte for byte — its
ground, its drop shadows (`color.dropShadow(.lamp, .light, …)` is
depth's), its white veil under a sheet (`color.scrimVeil`), its opaque
chrome, its ink glyphs — and no lamp op draws: the renderer keeps no
lamp state in light, and every backend's lamp op answers only lamp dark.
The look is still lamp (`App.theme` stays `.lamp`, and the reader's
Reduce Transparency row stands); only the draw is depth's. The golden
suite holds it: a lamp scene's light take is its depth light frame and
its committed `-depth` golden, so lamp keeps no light goldens of its
own.

## What holds by construction

Each of these is a proof in [color.zig](../../src/core/color.zig), run
over every ramp its gate applies to, and a byte that breaks one fails
the build:

- `paper` stays 1.1:1 above the brightest ground pixel the theme can
  draw — the floor depth's ground is already proved to. Lamp dark's own
  ground is the void, and no lamp op lifts it.
- The contact shadow only darkens and leaves the void as it is, and
  `ink` and `dark` on `paper` keep AA under its peak.
- The rim's brightest byte on `paper` stays under `g7`'s `0x67`: at
  most `0x66`, however many lights reach it, because the rim is one
  mask capped once. The golden suite checks it too, over every
  lamp-dark take against depth dark's bytes pixel for pixel, the boxes
  lamp repaints ([above](#buttons-under-the-lamp)) set aside, and a
  bare stroke — a secondary button's, a pool row's — held to its own
  tone instead.
- Every word on a well — `ink` and `dark` over `g10` and `g11` — keeps
  its text band over the darkest byte its face leaves.
- A face on `paper` only darkens, by at most twelve bytes — the full twelve
  over the void, less over any ground above it — and never
  lifts: one byte of lift is all the headroom `mid` on `paper` has.
- A lit glyph's peak on `paper` is `0xB2`, 3:1 over it and under `ink`
  on every fill a glyph stands on, and its floor, `0x35` on `paper`, is
  no dimmer than any material's rim `low` on the same fill.
- lamp's thirteen ramp bytes are depth's, in both appearances — one
  proof asserts the equality, so every text and focus proof depth
  passes, lamp passes on the same bytes — and lamp light's ground, drop
  shadows and veil are depth light's.
- depth and eink keep every byte they had: their goldens are the
  regression gate, byte-identical.

And by the pixel model rather than a proof: no clock, no sensor, no
timer. A frame renders when state changes and otherwise nothing runs.

## What is waived

Three things, all on record in
[pixel-model.md](pixel-model.md#what-lamp-waives-beside-it) beside
depth's 1.4.11 waiver, which lamp inherits with depth's bytes: text on
a frosted fill cannot be gated, the frost reads pixels, and a glyph on
a plate sits under nokre's own icon contrast floor. None is restated
here.

## What a frame costs

At 3× on a phone, per scroll frame unless stated:

| Op | Cost | Note |
| --- | --- | --- |
| Rim | ≈7 KB per page plate | four edge strips, four corner tiles |
| Face | ≈22 KB per page plate | two strips, a row four deep and a column sixteen wide for the dither, and four corner tiles each |
| Shadow | ≈9 KB per page caster | the nine-patch depth light uses today |
| Chrome's rims, faces, shadows and contact shadows | none per scroll frame | kept by the surface across frames |
| Lit glyph | ≈4–6 KB per glyph | a tile over the run's ink box, two device pixels out: a 24 px glyph's is 64–76 px square at 3×; filled again each frame it shows, chrome's included |
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

In the real shell, scrolling the kitchen sink full screen (2704×1696)
costs 7.3 ms a frame on the CPU and 1.4 ms before the submit on the
GPU — 1.5 since the ground became a void and the glyphs on plates lit —
where every op above is a shader over its planner's parameters
(medians; every theme and both window sizes are in
[gpu.md](gpu.md#what-the-shaders-measure)).

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
draws `depth` in place of `lamp` (in dark; in light the two are one
frame). Each follows the OS's own setting
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

Ground, rim, shadow, faces, edge lights, frost, then lit glyphs — each
its own golden review, and each cap added to color.zig's proofs before
the renderer draws the op it bounds. The ground's floor bounds
everything drawn over it, so it came first (a pool then, a void since);
the frost is the only op that reads pixels, so it comes last among the
surfaces, over a frame whose every other byte is already settled.
