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
every filled box, a ground pool, edge lights, and a frosted blur under
chrome ([lamp.md](lamp.md#the-dark-appearance)). Those effects scale
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
| lamp's ops as shaders: pool, rim (with edge lights), face and sheen, shadow, glow, frost blur | the op list itself and every cache key it carries |
| tiles the CPU still computes, uploaded once as textures under their existing keys | the partial-raster decisions, which the GPU path does not use: it redraws whole frames |
| presenting, paced by the display | goldens, proofs and the audit |

The proof order is deliberate: OP_FROST and OP_GLOW read pixels, so
the first GPU frame reads them back to the CPU and runs today's
arithmetic, and the shaders replace that readback afterwards — a
correct slow frame before a fast one.

## The readback rule for goldens

A GPU frame is compared only with another GPU frame from the same
machine and driver: render at the base commit, render at head, read both
back, and diff the bytes. A change is then a change in nokre, never a
change in the driver. The committed golden set stays CPU bytes, so
`-Dgolden` means what it always meant, and a GPU readback never enters
it.

## The proof plan

macOS and Metal first, as a go/no-go:

1. The Skia build: Ganesh on Metal for macOS arm64
   ([skia-build.md](skia-build.md#macos-with-metal-the-gpu-build)).
   *Built.*
2. `-Dgpu` in build.zig: the shim's GPU half compiled beside the CPU
   one, the GPU archive and Metal linked. *Next; not built yet.*
3. The shim's GPU path: one Metal context, one surface per drawable,
   ops replayed in order, tiles as cached textures, frost and glow by
   readback, and a readback entry for goldens and screenshots.
4. The macOS shell presents a `CAMetalLayer`, paced by the display
   link, with no CGImage per frame.
5. **Go/no-go:** a full-screen measurement on the owner's Mac —
   `bench-lamp` with `-Dgpu` and the real shell's frame log. If lamp is
   not smooth at full screen on the GPU, the reversal stops here and the
   record says so.
6. Lamp's ops as shaders; then the other shells, each with its
   goldens by readback.

## Presenters per shell

What each shell presents with today, and what the GPU path makes it:

| Shell | Today (CPU) | GPU |
| --- | --- | --- |
| macOS | `drawRect` → a CGImage of the whole frame, no vsync pacing | Metal: `CAMetalLayer`, display-link paced |
| iOS | `drawRect` → CGImage, the same as macOS | Metal: `CAMetalLayer`, `CADisplayLink` paced |
| Android | `SurfaceView` + `ANativeWindow_lock`, Choreographer paced | Vulkan or GLES on the same `SurfaceView`, still Choreographer paced |
| Windows | `SetDIBitsToDevice` of the whole frame | not chosen yet |
| Linux | `wl_shm` double buffer, no frame callback | not chosen yet |

The web is not on this list: the DOM substrate has no Skia and no frame
of its own ([dom-substrate.md](dom-substrate.md)).
