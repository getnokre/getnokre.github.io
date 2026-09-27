# The GPU: a reversed refusal

nokre refused the GPU from its first release, and on 2026-09-26 the owner
reversed that refusal for one reason: the `lamp` theme
([lamp.md](lamp.md)). This file is the record — what was refused and
why, what changed, what stays exactly as it was, and the plan that
proves the reversal on one platform before any other shell moves. The
build that carries the GPU backend is
[skia-build.md](skia-build.md#macos-with-metal-the-gpu-build); the
refusal list that points here is
[../introduction.md](../introduction.md#what-nokre-refuses-to-do).

## The refusal as it stood

CPU rasterization only, for three reasons that were one reason:

- **Driver variance.** A GPU's bytes are the driver's: two machines on
  the same platform with different GPUs, or one machine before and after
  an OS update, can draw the same frame differently. "Same viewport,
  same bytes" is only promisable when no driver is involved.
- **Flicker.** A presenter with its own queue and its own timing is a
  second place a frame can be half-drawn, torn or late.
- **A capability matrix.** Every GPU feature is a question of which
  devices have it, and every answer is a branch someone has to test.

The CPU paid for all three with time, and for eink and depth the time
was never the problem: their frames are boxes, lines and text, and a
whole frame fits the budget on every shell.

## The decision (2026-09-26)

Lamp is depth's bytes plus per-pixel light: a rim, a face and a shadow on
every filled box, a ground pool (a void since), edge lights, and a
frosted blur under chrome ([lamp.md](lamp.md#the-dark-appearance)). Those effects scale
with the pixels they cover, and a full-Retina window has a lot of
pixels. Measured on an M4 Mac, a lamp scroll frame at 1440×900@2 costs
6.3 ms, a sheet opening 12.7 ms — past the
8.3 ms a 120 Hz display allows — and at full screen, where depth
scrolls smoothly, lamp visibly does not
([lamp.md](lamp.md#what-a-frame-costs) has the table).

Two answers were on the table: make the effects cheaper until the CPU
keeps up, or move them to hardware built for per-pixel work. The owner
chose the second. **The design's effects are not to be reduced** —
fewer lights, a smaller blur, or a coarser grain would be a different
theme, and lamp is the theme that was designed. So the GPU draws lamp.

## What stays

The reversal spends the promise for GPU-backed frames and nothing else:

- **The CPU raster path remains**, in every build, on every shell. A
  build without `-Dgpu` is byte-for-byte what it was.
- **eink and depth stay CPU-exact.** They never needed the GPU, and
  their bytes keep the full promise of
  [pixel-model.md](pixel-model.md).
- **The CPU path is the golden oracle.** The committed golden set is
  CPU bytes, generated and compared exactly as before; the planners,
  partial-raster proofs and `skia_test`'s kept-bytes checks all run
  against the CPU surface.
- **GPU goldens are compared base-vs-head per driver.** See the
  readback rule below — never against the committed CPU set, and never
  across machines.

## What is GPU and what stays CPU

| On the GPU | On the CPU |
| --- | --- |
| rasterizing the op list into the drawable, in order, on one canvas | the tree, layout, shaping and every planner |
| lamp's ops as shaders: rim (with edge lights), face and sheen, shadow, glow, frost blur | the op list itself and each planner's parameters |
| a lit glyph's paint: the rim's shader over its plate's field | the partial-raster decisions, which the GPU path does not use: it redraws whole frames |
| presenting, paced by the display | goldens, proofs and the audit |

The proof order was deliberate: OP_FROST and OP_GLOW read pixels, so
the first GPU frame read them back to the CPU and ran the CPU's
arithmetic, and the shaders replaced that readback afterwards — a
correct slow frame before a fast one ([The shaders](#the-shaders)).

## The readback rule for goldens

Byte for byte, a GPU frame is compared only with another GPU frame
from the same machine and driver: render at the base commit, render at
head, read both back, and diff the bytes. A change is then a change in
nokre, never a change in the driver. The committed golden set stays CPU
bytes, so `-Dgolden` means what it always meant, and a GPU readback
never enters it. Against that set a GPU frame is held only within
stated tolerances, by `check-gpu` ([What the shaders
measure](#what-the-shaders-measure)).

## The proof plan

macOS and Metal first, as a go/no-go:

1. The Skia build: Ganesh on Metal for macOS arm64
   ([skia-build.md](skia-build.md#macos-with-metal-the-gpu-build)).
   *Built.*
2. `-Dgpu` in build.zig. *Built*, for nokre's own `run-*` examples on
   macOS arm64 and nowhere else: the shim compiles with `NOKRE_GPU`
   plus `shim/nokre_skia_mtl.mm` against `deps/skia-macos-gpu`, and the
   app links that archive with Metal, QuartzCore and IOSurface in place
   of the prebuilt. Tests, goldens and a consumer's `addApp` stay on the
   CPU whatever the flag says (build.zig's `Raster`); the example
   drivers and `bench-lamp` import the app's module, so under `-Dgpu`
   they link the GPU shim and, with no layer attached, draw on the CPU
   through it.
3. The shim's GPU path. *Built.* One `GrDirectContext` over the layer's
   device, made when the shell attaches its layer; per frame the
   recorded op list replays in order on one canvas — no bands, no pool,
   no damage rects — onto the texture of the layer's next drawable,
   then submit, then the drawable is presented.
   `hsk_surface_pixels` replays offscreen and reads back whole, so a
   screenshot is the GPU's bytes: the one readback left.
4. The macOS shell presents a `CAMetalLayer` on the frame clock it
   already had (the display link), with no buffer copy. *Built.* A
   live resize's frame presents inside the transaction AppKit resizes
   the window in (`presentsWithTransaction`), so the drawable's size
   and the window's land together.
5. **Go/no-go:** measured below; the verdict is the owner's scroll.
6. Lamp's ops as shaders. *Built* ([The shaders](#the-shaders)). Then
   the other shells, each with its goldens by readback.
7. iOS. *Built*, verified on the Simulator only
   ([iOS](#ios)).
8. Android, on Vulkan. *Built*, verified on the emulator only
   ([Android](#android)).

### iOS

The shim's Metal half is platform-neutral, so iOS moves the shell
alone. `tools/build-skia-ios.sh --gpu` builds the macOS GPU profile for
both SDKs into `deps/skia-ios-gpu`
([skia-build.md](skia-build.md#ios-built-from-source)); `-Dgpu` on an
iOS target compiles the shim with `NOKRE_GPU` and
`shim/nokre_skia_mtl.mm` against it. The shell is compiled by Xcode,
not zig, so the example project carries the switch as one build
setting, `NOKRE_RASTER` (`cpu` by default): `gpu` passes `-Dgpu` to the
Zig phase, links `deps/skia-ios-gpu` and Metal, and compiles the shell
with `NOKRE_GPU=1`.

```
xcodebuild -project examples/kitchen_sink/ios/KitchenSink.xcodeproj \
  -scheme KitchenSink -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  NOKRE_RASTER=gpu build
```

On the iOS 26.5 Simulator (iPhone 17 Pro, 1206×2436 frame), the kitchen
sink in lamp dark drew on the Mac's GPU through the Simulator's Metal,
and a screenshot of it against the same build without the flag differs
by at most 1 over the ground and 14 at most in the nav chip's frost and
glyph edges (mean 0.002 over the whole frame) — `check-gpu`'s split,
roughly, not held. Launch frames, Simulator only and not a device
number: the first 19.0 ms before the submit and 19.4 to submit on the
GPU (19.4 and 2.6 on the CPU), the second 2.4 and 0.6 (0.6 raster and
3.9 copy on the CPU), then the clock stops. No scroll was measured:
nothing on the host drives a Simulator touch without taking the Mac's
pointer. On a device, nothing is verified yet — the drawable pacing, a
rotation's transaction, ProMotion (the display link asks for the
screen's fastest rate, but an iPhone caps it at 60 without
`CADisableMinimumFrameDurationOnPhone` in the Info.plist, which
packaging does not write) and the frame costs.

### Android

One backend, Vulkan: no GLES and no ANGLE, and the CPU raster path is
the only fallback. The shim's replay and shaders are shared; what a
backend owns is the seam `shim/nokre_skia_gpu.h` names — the context, a
surface over the presenter's next image, the submit and the present —
which `shim/nokre_skia_mtl.mm` implements for Metal and
`shim/nokre_skia_vk.cpp` for Vulkan. (The submit moved behind the seam
with this: Metal's is a plain flush, Vulkan's signals the semaphore the
present waits on and leaves the image in the present's layout.)

The Vulkan half opens `libvulkan.so` at run time rather than linking it,
makes a Vulkan 1.1 instance (`VK_KHR_surface`,
`VK_KHR_android_surface`) and a device with one graphics queue and
`VK_KHR_swapchain`, no features, and hands Skia the rest
(`GrDirectContexts::MakeVulkan`, Skia's own memory allocator). The
context is made once and outlives windows. `hsk_gpu_attach_window`
makes the surface and a swapchain at the window's size: FIFO (the
display's vsync), three images unless the surface demands more, an
8-bit UNORM format, BGRA if offered and RGBA otherwise — never sRGB,
whose encode would change the bytes — opaque alpha, identity
pre-transform (the compositor rotates), and images sampled and copyable,
each wrapped once as an `SkSurface` texture for the frost's snapshot and
the glow's blend. A frame acquires the next image on a fresh semaphore
Ganesh waits on, replays, flushes with the image's own semaphore
signalled, submits, and presents; an out-of-date or suboptimal answer
remakes the swapchain at the next acquire, and the same window attached
again (surfaceChanged) remakes it at once. The window's size is the
extent, not the surface's `currentExtent`: inside surfaceChanged the
emulator's still answered the size before a rotation, and a swapchain
made at it showed each rotated frame stretched into the old shape.

The SkSL shaders compile to SPIR-V unchanged. `allowEs3` is still
needed: the SkSL 100 limit is the front end's, before any backend.

The switch is one Gradle property, `nokreRaster` (`cpu` in
gradle.properties): `gpu` passes `-Dgpu` to the Zig phase, which then
only checks the archive exists (the Zig is the same either way), and
`-DNOKRE_RASTER=gpu` to CMake, which compiles `nokre_skia_vk.cpp`, the
shim and shell.c with `NOKRE_GPU=1` against `deps/skia-android-gpu`
([skia-build.md](skia-build.md#android-built-from-source-freetype-from-memory)).
The GPU build's `minSdk` is 30, Android 11, the floor set for it; the
CPU build's stays 26. `zig build check-targets` parses shell.c both
ways and the Vulkan half with the NDK's clang, when an NDK is found.

```
cd examples/kitchen_sink/android
./gradlew installDebug -PnokreRaster=gpu
```

`adb shell setprop debug.nokre.frame_log 1` before launch logs the
macOS shell's frame line to logcat (tag `nokre`), on either path.

On the emulator (API 35, arm64, `-gpu host -feature Vulkan` on an M4:
gfxstream's Vulkan 1.1, device "Apple M4"), the kitchen sink in lamp
dark drew on the GPU, and a screenshot of it against the same build on
the CPU is byte-identical over the ground and every flat area, and
differs only in the nav chip and its picker — frost and glyph edges — by
at most 6 at rest and 30 with the picker open (whole-app mean 0.0004 and
0.0014); no pixel has r, g and b apart on either path. Not held, as on
iOS. Rotation both ways and a trip through the home screen redraw at
the new size. Emulator frames, not a device number: a scroll's frames
median / p95 1.66 / 2.59 ms raster and 0.71 / 1.35 present on the GPU,
interval 16.6 ms (the emulator's 60 Hz), against 29.4 / 30.6 raster and
an interval of 31.1 on the CPU; the context 12–19 ms; the first frame's
submit 28 ms with the host's pipeline cache warm and 992 ms cold.

On a device nothing is verified: a real driver's Vulkan (the emulator's
is the Mac's Metal under gfxstream), the swapchain's pacing under FIFO
and a real display's rate, rotation's `currentTransform` (the
compositor's rotation pass, and whether a pre-rotated swapchain is worth
it), the fallback on a device whose Vulkan refuses, and the frame costs.

### The shaders

Under `-Dgpu`, on a surface that draws on the GPU (`hsk_surface_is_gpu`:
a layer is attached, or the surface was made to), the lamp's ops no
longer ask the renderer for tiles. canvas_skia.zig plans each op as it
always did and hands the shim the planner's parameter block and the
pieces its tiles would have tiled (`hsk_lamp_op`, `hsk_lamp_frost`); a
Skia runtime effect then evaluates the same formula per device pixel.
The blocks are lamp_pixels.zig's extern structs, their sizes pinned on
both sides, and each shader is that file's function transcribed: where
the CPU keeps integers the shader keeps them (SkSL 300's `int` and
`uint`), and where a CPU value is a 64-bit square of sub-pixel lengths
it is a float, floored where the CPU divides.

| Op | Shader | Parameters |
| --- | --- | --- |
| Rim | `RimField.coverageAt`: the box's ring less its inner box's, times the lamp's light, the specular's `exp`, and every edge line, capped once | `RimField`: box, radius, lamp, `a0`, near and far, specular point and `specR²`, the material's high, low and specular, the cap, up to twelve edge lines |
| Face and sheen | `sheenAt`, `acrossAt`, `downAt`, one draw each over the planner's pieces | `FaceField`: box, lamp, the near squares, span, darkest, glass's `k0`, `σ` and bright tint, `under`, sheen |
| Shadow | `ShadowMask.coverageAt`: the smoothstep of rounded-box distance, both passes, and depth's drop shadow | `MaskField`: blur, radius, peak; the reach is the pieces' union, drawn as one rect |
| Contact line | the shadow's coverage, then a runtime *blender*: `lampGlowByte` of the destination's own byte, never darker, clamped at the ceiling | `MaskField`, the tone and the ceiling |
| Frost | the frame drawn so far, snapshotted on the GPU beneath the plate; halved; three separable box-blur passes at both radii; sampled back and mixed per plate pixel | `FrostStyle`: radius, tint, gain |

The CPU's comptime tables are their formulas again: the specular's
falloff is `round(4096 · exp(−2.2 · i/64))`, the glow's is
`lampGlowByte`'s arithmetic on the byte beneath, and the face's
`darkened` search is the inequality it solves, `under · c > 255 ·
bytes − 128` (lamp_pixels.zig holds the two equal for every byte).

**No readback in a frame.** The contact line blends with the
destination and the frost copies from it, both on the GPU, so a frame
draws straight onto the drawable's texture — which is why the layer is
not framebuffer-only — and the offscreen-then-copy path is gone. Ganesh
on Metal has no framebuffer fetch, so a blend that reads the destination
copies what it reads once per draw, and each copy ends the frame's
render pass: that is why a contact line is one rect rather than its
nine pieces (27 copies a nav row became 3).

**The frost is the CPU's integers.** The snapshot is the plate out to
its reach; the half frame is each 2×2 sum times 64, 8.8 fixed point in
two bytes of an RGBA8 texture; a sum across is written in three bytes
and a sum down divides by `(2r+1)²` once, rounding — so every value the
CPU holds, the GPU holds, and the grain is the same 32-bit wrapping
hash. Both blurs share one surface side by side, so a pass is one
render pass. Two limits shape it: a child's sample is `half` in SkSL,
which carries a byte exactly and sixteen bits not, hence bytes; and
Skia keeps a runtime effect at SkSL 100 (no `uint`, no bitwise
operators) behind an option it does not publish, which the shim sets
through an explicit instantiation (`allowEs3`).

**What stays cached on the GPU.** The kept chrome masks are gone: no
tile is asked for, so nothing is kept. A frost's result stays kept per
generation, as its two blurs: its entry carries the op either way, and
a sheet standing still then draws no blur passes — though recomputing
it every frame measured within noise (a scroll inside a sheet,
1440×900@2, 4.74 ms kept against 4.82 recomputed, each frame timed to
a synchronous submit). The ground needs no cache: it is the void, the
same 16-column tile depth's ground is, one byte throughout. (The pool
it replaced was kept as a texture, uploaded once per viewport, because
a shader computing it measured 0.8 ms of GPU time a full-screen frame
against 0.3 ms sampling it; the measurements below that name it are
from then.)

### What the proof measured

The kitchen sink in `ReleaseFast` on an M4 MacBook's built-in
display (120 Hz), dark appearance, a 5 s wheel scroll posted as
CGEvents at 120 Hz (down, then back up), `NOKRE_FRAME_LOG=1`; median /
p95 ms over every frame of the scroll. The CPU column is the merged
IOSurface presenter. On the GPU, "raster" is everything before the
submit (the Zig record, the replay, and lamp's readbacks and the CPU
arithmetic on them); "present" is the submit and the present.

| Theme, window | CPU raster | CPU present | CPU interval | GPU raster | GPU present | GPU interval |
| --- | --- | --- | --- | --- | --- | --- |
| eink, 1120×1440 | 2.33 / 2.95 | 0.55 / 0.76 | 8.34 / 16.7 | 0.97 / 1.48 | 0.14 / 0.53 | 8.35 / 16.7 |
| eink, full screen 2704×1696 | 2.17 / 2.68 | 1.42 / 2.50 | 8.34 / 16.7 | 1.75 / 2.58 | 0.30 / 0.51 | 8.34 / 16.7 |
| depth, 1120×1440 | 2.89 / 3.45 | 0.39 / 0.45 | 8.34 / 16.7 | 1.08 / 1.55 | 0.14 / 0.43 | 8.34 / 16.7 |
| depth, full screen | 3.42 / 3.92 | 0.91 / 0.97 | 8.34 / 16.7 | 1.82 / 3.00 | 0.27 / 0.43 | 8.34 / 16.7 |
| lamp, 1120×1440 | 5.66 / 7.84 | 0.20 / 0.24 | 8.33 / 16.7 | 8.48 / 10.21 | 0.07 / 0.14 | 9.34 / 16.7 |
| lamp, full screen | 7.26 / 11.52 | 0.81 / 0.85 | 10.60 / 17.7 | 7.76 / 9.26 | 0.05 / 0.10 | 8.51 / 16.7 |

Inside lamp's GPU raster at full screen: six reads a frame (three
contact lines, three nav frosts) cost 3.85 / 4.76 ms of waiting, the
arithmetic on them 0.87 / 1.65, the replay 0.79 / 1.04, and the Zig
record 2.29 / 3.44. With `NOKRE_GPU_SYNC=1` (the submit waits for the
GPU) the present of a full-screen frame is 1.89 ms for depth and
1.25 ms for lamp after its last read: the GPU itself is not the cost.

The first frame: the Metal context is 0.5 ms. On a machine that has
never compiled nokre's pipelines, the first lamp frame took 125 ms
before the submit (101 ms of it the first read, which waits on every
pipeline compile) and 14 ms to present; once the system's shader cache
holds them, a first frame is 4–5 ms before the submit and 3–4 ms after
for eink and depth, and 27–30 ms before and under 1 ms after for lamp.

**Reading it:** eink and depth scroll at the display's rate on either
path, at under half the CPU's raster time on the GPU. Lamp on the GPU
with reads is no faster than the CPU — the reads serialise the frame —
but it holds the display's rate at full screen where the CPU drops
frames (interval median 8.5 ms against 10.6). What the shaders remove
is the 4.7 ms of reads and arithmetic, which leaves about 3 ms, and the
Zig record's tile fills are most of that.

### What the shaders measure

**Accuracy.** `zig build check-gpu -Dskia -Dgpu` runs the golden suite
with the GPU shim linked and draws every lamp-dark take a second time on
an offscreen Metal surface, reads it back, and compares it with its
committed golden (tests/gpu_accuracy.zig). Dark only: lamp light is
depth light and draws no lamp op, so no shader has a light variant.
Pixels are sorted by what drew them: a lit glyph's box, and text and
anti-aliased edges (every other glyph run's box, and each rounded
fill, stroke and frost's corner squares), are reported and not held,
since Ganesh rasterises glyphs and curves its own way; what a frost
covers is held to 4 bytes; the plates and the ground — the void, rims,
faces, shadows, contact lines over depth's fills — to 2.
Max / mean byte difference on an M4:

| Take | Plates + ground | Frost | Lit glyphs | Text + AA (max) |
| --- | --- | --- | --- | --- |
| elements | 1 / 0.000 | — | — | 50 |
| button-forms | 1 / 0.000 | — | — | 23 |
| button-in-progress | 1 / 0.001 | — | — | 45 |
| meter | 1 / 0.000 | — | — | 27 |
| tiles | 1 / 0.000 | — | 1 / 0.011 | 35 |
| accessibility-toggles | 1 / 0.000 | — | — | 12 |
| dial | 1 / 0.000 | — | 4 / 0.012 | 8 |
| select-picker | 1 / 0.000 | 1 / 0.041 | 3 / 0.022 | 24 |
| nav-bottom | 1 / 0.000 | 1 / 0.006 | 2 / 0.053 | 7 |
| sheet | 1 / 0.000 | 1 / 0.049 | — | 47 |
| notice-banner | 0 / 0 | 1 / 0.025 | 1 / 0.032 | 1 |
| notices-pane | 0 / 0 | 1 / 0.054 | 1 / 0.057 | 3 |
| nav-with-indicator | 1 / 0.000 | 1 / 0.008 | 2 / 0.053 | 7 |
| frosted-chrome (2×) | 0 / 0 | 1 / 0.000 | — | 23 |
| page-scrolled | 1 / 0.001 | 1 / 0.071 | 2 / 0.060 | 45 |
| sheet-over-scrolled | 1 / 0.001 | 1 / 0.063 | 17 / 0.120 | 45 |

Every take meets both targets.

**Frames.** Measured as the proof was — the kitchen sink in
`ReleaseFast`, a 5 s CGEvent wheel scroll at 120 Hz, median / p95 ms
over every frame. `raster` is everything before the submit; on the GPU
it is the record (the tree walk and the op list, the planners
included), the wait for a drawable and the replay onto the canvas, and
`present` is the submit and the present. The CPU columns are the same
build without `-Dgpu`.

| Theme, window | CPU raster | CPU present | CPU interval | GPU raster | GPU present | GPU interval |
| --- | --- | --- | --- | --- | --- | --- |
| eink, 1120×1440 | 2.35 / 2.89 | 0.54 / 0.71 | 8.34 / 16.7 | 1.04 / 1.59 | 0.13 / 0.40 | 8.34 / 16.7 |
| eink, full screen 2704×1696 | 2.15 / 2.71 | 1.43 / 2.53 | 8.34 / 16.7 | 1.60 / 2.67 | 0.25 / 0.41 | 8.34 / 16.7 |
| depth, 1120×1440 | 2.86 / 3.36 | 0.39 / 0.45 | 8.34 / 16.7 | 1.14 / 1.74 | 0.12 / 0.34 | 8.34 / 16.7 |
| depth, full screen | 3.36 / 3.72 | 0.91 / 0.96 | 8.34 / 16.7 | 1.64 / 2.93 | 0.24 / 0.37 | 8.34 / 16.7 |
| lamp, 1120×1440 | 5.81 / 7.88 | 0.21 / 0.26 | 8.34 / 16.7 | 1.14 / 1.53 | 0.66 / 0.98 | 8.34 / 16.7 |
| lamp, full screen | 7.35 / 11.44 | 0.82 / 0.85 | 10.68 / 17.5 | 1.39 / 1.87 | 0.73 / 1.27 | 8.34 / 16.8 |

Measured again at revision 155 — the ground a void, the glyphs on
plates lit, lamp light drawn as depth — lamp at full screen on the GPU
is 1.54 / 2.13 raster, 0.70 / 1.08 present, 8.33 / 16.8 interval; the
record 1.06, the replay 0.47, the submit 0.69 (medians): within 0.15 ms
of the row above, the lit glyphs' planning in the record.

Inside the GPU frame, median ms, record / wait for a drawable / replay
/ submit (the present itself is under 0.02):

| Theme | 1120×1440 | full screen |
| --- | --- | --- |
| eink | 0.83 / 0.03 / 0.15 / 0.12 | 1.30 / 0.04 / 0.24 / 0.24 |
| depth | 0.92 / 0.03 / 0.18 / 0.11 | 1.29 / 0.04 / 0.32 / 0.23 |
| lamp | 0.74 / 0.02 / 0.38 / 0.65 | 0.91 / 0.01 / 0.47 / 0.72 |

With `NOKRE_GPU_SYNC=1` the submit waits for the GPU, so it is the
GPU's own time: depth 1.27 and 1.81 ms, lamp 4.61 and 4.46 — of lamp's,
about 2 ms the three nav frosts (their passes are small; the render
passes are what costs).

**First frames.** The context is 0.5 ms. With the system's shader cache
warm, lamp's first frame is 12.7–14.5 ms before the submit (the record
9.4–10.1, the pool's tile among it; the replay 2.7–3.7) and 5.8–6.2 to
submit; depth's is 5.9 and 2.9. With it cold, lamp's is 36.6 before the
submit — the replay 26.6, Skia translating nokre's effects — and 372 to
submit, Metal compiling their pipelines; depth's is 28.2 and 107.5.

**A live resize.** A 2 s drag of the window's corner drew 207 frames
at 167 sizes: raster 8.63 / 9.91 ms,
present 0.87 / 0.99. The record is 8.16 of it — the layout at a new
size and the pool's tile refilled for it.

**Reading it:** a lamp scroll frame now costs its record and a replay,
1.4 ms at full screen against 7.4 on the CPU and 7.8 in the proof, and
the frame holds the display's rate in both windows. What is left on the
CPU is the tree walk and the op list; what is left on the GPU is about
4.5 ms of its own time, most of it the frosts' render passes.

## Presenters per shell

What each shell presents with today, and what the GPU path makes it:

| Shell | Today (CPU) | GPU |
| --- | --- | --- |
| macOS | the frame copied into an IOSurface on the view's layer, display-link paced | Metal: `CAMetalLayer`, the same display link, a resize presented in its transaction (`-Dgpu`, built) |
| iOS | the frame copied into an IOSurface on the view's layer, `CADisplayLink` paced — macOS's presenter | Metal: the view's layer a `CAMetalLayer` (`+layerClass`), the same display link, a layout's frame presented in its transaction (`-Dgpu`, built; simulator-verified, unverified on a device) |
| Android | `SurfaceView` + `ANativeWindow_lock`, Choreographer paced | Vulkan: a FIFO swapchain on the same `SurfaceView`'s window, still Choreographer paced, remade on surfaceChanged (`nokreRaster=gpu`, built; emulator-verified, unverified on a device) |
| Windows | `SetDIBitsToDevice` of the whole frame | not chosen yet |
| Linux | `wl_shm` double buffer, no frame callback | not chosen yet |

The web is not on this list: the DOM substrate has no Skia and no frame
of its own ([dom-substrate.md](dom-substrate.md)).
