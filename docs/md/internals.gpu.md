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

- **The CPU raster path remains**, in every build, on every shell. An
  app that does not declare lamp, and every test, builds byte-for-byte
  what it did.
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
| lamp's ops as shaders: rim (with edge lights), face and sheen, shadow, frost blur | the op list itself and each planner's parameters |
| a lit glyph's paint: the glyph's shader over its own ink box's field | the partial-raster decisions, which the GPU path does not use: it redraws whole frames |
| presenting, paced by the display | goldens, proofs and the audit |

The proof order was deliberate: OP_FROST and the contact line (then a
table op, OP_GLOW; a plain shadow since 2026-09-27) read pixels, so
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
   macOS arm64 (Windows and Linux followed, below): the shim compiles with `NOKRE_GPU`
   plus `shim/nokre_skia_mtl.mm` against `deps/skia-macos-gpu`, and the
   app links that archive with Metal, QuartzCore and IOSurface in place
   of the prebuilt. It is now the examples' explicit `.raster = .gpu`,
   and a consumer's app resolves its own ([Consumers](#consumers)). The
   example drivers and `bench-lamp` import the app's module, so under
   `-Dgpu` they link the GPU shim and, with no layer attached, draw on
   the CPU through it.
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
8. Android, on Vulkan. *Built*, verified on the emulator and on a MediaTek tablet
   ([Android](#android)).
9. Windows, on Vulkan. *Written and compile-checked, unverified: no
   machine* ([Windows](#windows)).
10. Linux (Wayland), on Vulkan. *Written and compile-checked,
    unverified: no machine* ([Linux](#linux)).

### iOS

The shim's Metal half is platform-neutral, so iOS moves the shell
alone. `tools/build-skia-ios.sh --gpu` builds the macOS GPU profile for
both SDKs into `deps/skia-ios-gpu`
([skia-build.md](skia-build.md#ios-built-from-source)); `-Dgpu` on an
iOS target compiles the shim with `NOKRE_GPU` and
`shim/nokre_skia_mtl.mm` against it. The shell is compiled by Xcode,
not zig, so it learns the raster from the packaging tree, as a
consumer's does ([Consumers](#consumers)); the example project's one
setting, `NOKRE_RASTER=gpu`, only passes `-Dgpu` to the Zig phase.

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
whose encode would change the bytes — opaque alpha, pre-rotated to the
display's turn (below), and images sampled and copyable,
each wrapped once as an `SkSurface` texture for the frost's snapshot.
A frame acquires the next image on a fresh semaphore
Ganesh waits on, replays, flushes with the image's own semaphore
signalled, submits, and presents. An out-of-date answer remakes the
swapchain at the next acquire; a suboptimal one only asks, at the next
acquire, whether the window's size or the display's turn has moved from
the swapchain's, and remakes it if so; the same window attached again
(surfaceChanged) remakes it when either moved and keeps it otherwise.
The window's size is the frame, not the surface's `currentExtent`:
inside surfaceChanged the emulator's still answered the size before a
rotation, and a swapchain made at it showed each rotated frame
stretched into the old shape.

**Pre-rotation.** The swapchain's `preTransform` is the surface's
`currentTransform` — the display's quarter or half turn, when the
surface lists it; identity otherwise — and a quarter turn swaps the
window's size for the extent, so the image is the display's own shape
and the compositor shows it as it is. The frame is drawn turned: the
turn (`nokre_gpu::turn`, clockwise, as Vulkan's transforms are) is the
replay canvas's base matrix, every op that draws in device space — the
ground, shadows, the frost's plate, the lamp's fields — returns to that
base rather than to identity, and the frost's snapshot is taken through
the turn and sampled back through its inverse. A turn takes each pixel's
centre onto a pixel's centre, so every effect that reads the frame reads
the pixel it reads unturned: `check-gpu` holds a take per effect at
all four turns to the same targets, and `check-gpu-sweep` every take
([What the shaders measure](#what-the-shaders-measure)). What moves is text: Ganesh
rasterises a glyph under the turn in the turned space, so a turned
frame's plain text differs from the unturned one's at glyph edges —
the class the reversal already reports and does not hold. Windows and
Linux are unchanged: their surfaces offer identity alone, and there a
suboptimal answer still remakes the swapchain.

The SkSL shaders compile to SPIR-V unchanged. `allowEs3` is still
needed: the SkSL 100 limit is the front end's, before any backend.

The example project's `nokreRaster=gpu` property passes `-Dgpu` to both
of its zig builds; the Zig checks the archive exists and is otherwise
the same either way. What CMake compiles — `nokre_skia_vk.cpp`, the
shim and shell.c with `NOKRE_GPU=1` against `deps/skia-android-gpu`
([skia-build.md](skia-build.md#android-built-from-source-freetype-from-memory))
— it reads from the packaging tree, as a consumer's does
([Consumers](#consumers)). The GPU build's `minSdk` is 30, Android 11,
the floor set for it; the CPU build's stays 26. `zig build check-targets` parses shell.c both
ways and the Vulkan half with the NDK's clang, when an NDK is found.

```
cd examples/kitchen_sink/android
./gradlew installDebug -PnokreRaster=gpu
```

`adb shell setprop debug.nokre.frame_log 1` before launch logs the
macOS shell's frame line to logcat (tag `nokre`), on either path, with
two Android fields: on the GPU `swapchains`, the count made so far
(`hsk_gpu_swapchains_made`), which a steady frame must not move; on the
CPU `lock`, the part of `raster` spent waiting in `ANativeWindow_lock`
for a buffer. `debug.nokre.gpu_sync 1` beside it is the shim's
`NOKRE_GPU_SYNC`, since adb can hand an app no environment variable
(`wrap.*` is refused on a user build). On the tablet it overstates the
GPU's time: the GPU idles between synced frames and its clock falls,
so a synced submit measured 11–14 ms of a frame that holds 90 Hz
unsynced, and leaving work out could lengthen it.

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

The emulator rotated cleanly and showed nothing of the defect a device
then did, so an emulator is not evidence for a presenter.

On a device — a Lenovo TB336FU (MediaTek, Mali-G57 MC2, Android 16,
1600×2560 at 90 Hz, natural orientation portrait), 2026-09-27 — the
swapchain as first built, at identity, drew portrait at 90 fps and
landscape at 30–45. On a turned display the present answered
suboptimal at every frame, and each answer remade the swapchain: one
swapchain per frame, 19 ms of every frame spent remaking it. Drawn
through at identity instead, the frame held 90 in eink, but the layer
left the display's overlay for a GPU composition pass (`CLIENT`, with
the compositor's rotation) — the same GPU lamp draws on. Pre-rotated,
it stays on the overlay (`DEVICE`, transform 0) in every orientation.
The kitchen sink, a 10 s scroll at a fixed 400 px/s, frame log (median
raster; median / p95 interval) and SurfaceFlinger (share of presents
over 1.5 refreshes apart):

| Window | Look | Before | After |
| --- | --- | --- | --- |
| portrait, 1600×2494 | eink | 2.9 ms; 11.1 / 11.4; 0.3% | 2.7 ms; 11.1 / 11.3; 0.4% |
| landscape, 2560×1534, both turns | eink | 21.9 ms; 24.7 / 27.2; 99–100% (a swapchain per frame) | 2.6 ms; 11.1 / 11.4; 0.4–0.5% |
| portrait | lamp | 3.9 ms; 11.1 / 11.5; 0.7% | 3.8 ms; 11.1 / 11.5; 0.7% |
| landscape, both turns | lamp | 22.9 ms; 27.6 / 30.1; 99–100% (a swapchain per frame) | 3.4 ms; 11.1 / 11.6; 0.9–1.0% |
| floating 2100×1184, landscape | eink | 18.0 ms; 20.2 / 22.8; 78% (a swapchain per frame) | 2.6 ms; 11.1 / 11.5; 1.0% |
| floating 1400×734, 700×1734, 1000×934, 600×434, 1000×1134 (both displays) | eink | — | 2.3–2.6 ms; 11.1 / 11.5; ≤1.3% (600×434: 5.5%, on the CPU raster too) |
| split screen, portrait and landscape | eink | — | 2.5 ms; 11.1 / 11.6; ≤1.4% |
| floating 1400×734, 700×1734, 1000×1134 | lamp | — | 2.9–3.2 ms; 11.1 / 11.5; ≤3.6% |

No steady frame made a swapchain in any of them. A change costs one
or two: a half turn one, when a present finds the new turn, 15–25 ms
of that frame; a quarter turn two, inside the system's own rotation
animation, since surfaceChanged's surface can still answer the old
turn; resizing a floating window one, at surfaceChanged, and a first
frame of 8–14 ms.

One case holds less than portrait, and not by orientation: a *large*
floating window in lamp (2100×1184 on the turned display, 1500×1634 on
the upright one, alike) runs at a median 13 ms with a fifth of its
presents late. Every layer of a floating window is composited by
SurfaceFlinger on the GPU (its rounded corners and shadow), so the
compositor and lamp share the GPU, and the present waits on it. Eink in
the same windows holds 90.

Where lamp's GPU time goes there (Vulkan timestamps between phases,
2026-09-28): the three nav frosts' snapshot, half frame and blurs were
1.1 ms of a 5.2 ms frame at 2100×1184, and everything else — the
ground, the page's text, rims, faces and shadows — the rest, no one
class of it dominant (leaving any one out moved the interval less than
leaving out the frosts). The blurs drew every sum over the whole
region, three wide radii past the plate on each side, where the plate
reads only its own span: each sum is now drawn over the span grown by
the radius once per sum still to come along its axis, and nothing else
changes (`blurs`). The frosts' phase fell to 0.8 ms and the frame to
4.2; the accuracy check, every take at all four turns (now
`check-gpu-sweep`), reads back the same bytes with the
working surfaces cleared to a colour first, so no pixel outside the
cones is read. The scroll in the two large windows, before and after,
two rounds each (median / p95 interval; late share):
13.2–13.8 / 16.7 ms and 22–25% late, then 12.0–12.6 / 16.6 and 13–16%.
Full screen stays at 90 either way. What remains is the compositor's
share of the same GPU; the rest of the frame repeats no work. The fallback on a device whose Vulkan
refuses is still unverified.

**A window of any size.** Frame rate must not depend on orientation,
window size or aspect ratio; a one-time cost at a change is fine,
staying slow is not (owner, 2026-09-27). Density rounds to an integer
scale and the frame is the ceiling of the window in logical pixels, so
a floating window 1273 px wide at scale 2 makes a 1274 px frame. The
view is now given the frame's size and the window crops the leftover
pixel ([platform-shells.md](platform-shells.md#android-specifics); the
owner's decision, 2026-09-28), so the window, and with it the
swapchain's extent (`ANativeWindow_getWidth`), is always the frame's
size on both rasters. Before, the GPU's extent was a pixel short and
the frame was drawn into it, its last column or row clipped: the same
pixels, at no cost, at every turn. The CPU raster was the one that
paid. The window buffer was a pixel short of the frame, so it could not
be drawn into directly; every frame was recorded a second time,
rasterised whole and copied. On the tablet, 1273 px wide ran a median
13.6 ms of raster against 6.9 ms at 1274, in either orientation, and
missed a third of its presents.

On the emulator (API 35, scale 3), a window 1000 or 1001 px wide shows
the same bytes as one 1002 px wide over every pixel of the narrower
window, at all four turns and in a floating window, CPU and GPU alike:
cropped at the edge, neither scaled nor shifted, and the columns past a
floating window's edge show what lies behind it. A 10 s scroll declined
no frame (`declined` in the frame log stays 0). Emulator frames, not a
device number: the CPU raster before, a median 17.4 and 14.9 ms at 1002
against 23.9 and 34.3 at 1000; after, 13.2 and 20.0 against 14.7 and
14.3.

On the tablet (scale 2, CPU raster, 2026-09-28), floating windows whose
odd side shares a frame with the even one beside it, the same 10 s
scroll at 400 px/s (median / p95 raster; median / p95 interval; share
of SurfaceFlinger's presents late):

| Window | Before | After |
| --- | --- | --- |
| 1001×1600 upright (frame 1002 wide) | 12.2 / 14.7; 14.7 / 17.4; 34.5% | 6.8 / 9.3; 11.1 / 11.9; 1.5% |
| 1002×1600 upright | 6.7 / 9.2; 11.1 / 11.9; 1.2% | 6.7 / 9.1; 11.1 / 11.8; 1.5% |
| 1002×1601 upright (frame 1536 high) | 12.2 / 15.1; 14.7 / 17.6; 35.1% | 6.7 / 9.1; 11.1 / 11.9; 1.6% |
| 1002×1602 upright | 6.8 / 9.4; 11.1 / 11.8; 1.2% | 6.8 / 9.4; 11.1 / 11.8; 1.7% |
| 1273×1570, quarter turn (frame 1274 wide) | 13.8 / 17.1; 15.8 / 18.7; 42.6% | 7.1 / 9.8; 11.1 / 12.2; 2.0% |
| 1274×1570, quarter turn | 6.8 / 9.4; 11.1 / 12.1; 1.9% | 6.8 / 9.5; 11.1 / 12.0; 1.0% |
| 1273×1570, three quarters (frame 1274 wide) | 13.7 / 16.7; 15.8 / 18.5; 42.6% | 6.7 / 9.2; 11.1 / 11.9; 1.4% |
| 1274×1570, three quarters | 6.8 / 9.4; 11.1 / 12.1; 1.8% | 6.8 / 9.5; 11.1 / 12.0; 1.9% |

`declined` stayed 0 through every run. A screenshot of each odd window
matches the even one that shares its frame over every pixel of the odd
window except the system's own: the window's border and caption, the
accessibility button and the gesture bar, which sit where the screen
puts them and so one pixel apart in the two windows.

The GPU raster after the change, the same scroll on the tablet
(median raster; median / p95 interval; share of presents late), no
steady frame making a swapchain: every row within noise of the
pre-rotation table's.

| Window | eink | lamp |
| --- | --- | --- |
| portrait, 1600×2494 | 2.7; 11.1 / 11.4; 0.4% | 3.8; 11.1 / 11.5; 0.7% |
| quarter turn, 2560×1534 | 2.6; 11.1 / 11.4; 0.5% | 3.4; 11.1 / 11.5; 1.1% |
| three quarters | 2.6; 11.1 / 11.4; 0.7% | 3.4; 11.1 / 11.5; 0.8% |
| half turn, 1600×2494 | 2.7; 11.1 / 11.4; 0.3% | 3.8; 11.1 / 11.5; 0.6% |
| floating 1001×1600 (frame 1002×1534) | 2.6; 11.1 / 11.4; 0.6% | 3.0; 11.1 / 11.5; 0.5% |
| floating 1500×1634 | 2.7; 11.1 / 11.4; 0.7% | 3.6; 12.3 / 16.6; 14% |
| floating 2100×1184, quarter turn | 2.6; 11.1 / 11.5; 0.9% | 3.4; 12.8 / 16.6; 17% |

The tablet turns upside down (`user_rotation 2`): the swapchain takes
the half turn and the layer stays on the display's overlay (`DEVICE`,
transform 0) while it scrolls. On the CPU raster a half turn costs what
a quarter does, 8.2 ms of eink raster against 7.5 upright, the display
hardware turning the buffer.

In Persian, a floating window 1001 px wide shows the bytes the 1002 px
one does over every pixel of the narrower window, CPU and GPU alike:
the frame's first column is the window's, and it is the far edge's
column that is cropped. Only the system's own pixels differ — the
window's border and bottom corner, and the ends of its handle, each
half a pixel off centre. A tap 39 px inside that window's right edge
and one 40 px above its bottom landed on the control under them.

Split screen is not measured since the change: on this tablet the
command that enters it locked the device once, so it is not driven by
command, and it stays for a person to try by hand.

One cost does depend on orientation, and it stays. On the CPU raster
the tablet in full-screen landscape rasterises in 9.0 ms against 7.5 in
portrait, because the display hardware rotates the buffer. Accepted
for the CPU raster (owner, 2026-09-28): an app that needs full rate in
every orientation declares lamp and takes the GPU raster, which
pre-rotates.

### Windows

Vulkan, one backend — no GL, no ANGLE, no Direct3D — and the CPU
presenter the only fallback. `-Dgpu` on the Windows target
(x86_64-windows-msvc, as every Windows `-Dskia` build is) compiles the
shim with `NOKRE_GPU` and `shim/nokre_skia_vk.cpp` against
`deps/skia-windows-gpu`, which `tools/build-skia-windows.sh` builds
([skia-build.md](skia-build.md#windows-and-linux-with-vulkan)), and
shell.c with `NOKRE_GPU`. The Vulkan half is Android's — the device, the
FIFO swapchain, the images wrapped as textures, acquire, replay, submit,
present, the stale swapchain remade — with three differences: the
loader is `vulkan-1.dll`, which every Vulkan driver installs, opened at
run time; the surface is `VK_KHR_win32_surface` over the module's
`HINSTANCE` and the window's `HWND` (`hsk_gpu_attach_hwnd`); and the
extent is the surface's `currentExtent`, which Win32 makes the client
area. The window attaches after creation and before it is shown,
attaches again at `WM_SIZE` (the swapchain remade at the new client
size) and draws inside the resize, and detaches at `WM_DESTROY`. Frames
come from the shell's frame clock, a `DwmFlush` thread, on either path
([platform-shells.md](platform-shells.md#windows-specifics)).

```
tools/build-skia-windows.sh     # once, in Git Bash, on Windows
zig build run-kitchen-sink -Dskia -Dgpu
```

`NOKRE_FRAME_LOG=1` writes the macOS shell's frame line to stderr; the
app is a GUI-subsystem executable, so redirect it (`2> frames.log`).
Without `deps/skia-windows-gpu` the build stops before compiling and
names the script.

**Unverified: no machine.** From a Mac, `check-targets` compiles
shell.c both ways and `nokre_skia_vk.cpp` and the shim's GPU mode for
x86_64-windows-gnu (mingw's headers, not Visual Studio's), and nothing
else here has happened: the script has never run, so neither has the
MSVC link against its archive (nor whether the zlib and codec stubs
still fit that archive); no frame has been drawn, on either presenter;
no driver has answered the loader, the format, the image usage the
frost needs (sampled and copyable swapchain images) or the fallback;
nothing has measured whether `DwmFlush` pacing and FIFO's own blocking
acquire hold the display's rate together; and the frame costs are
unknown.

### Linux

Wayland, Vulkan, the same one backend and the same fallback. `-Dgpu` on
an x86_64 Linux target compiles the shim with `NOKRE_GPU` and
`shim/nokre_skia_vk.cpp` against `deps/skia-linux-gpu`
(`tools/build-skia-linux.sh`), and shell.c with `NOKRE_GPU`. The
loader is `libvulkan.so.1`, the soname every distribution's loader
package installs (the unversioned name is the -dev package's), opened
at run time. The surface is `VK_KHR_wayland_surface` over the
connection's `wl_display` and the shell's `wl_surface`
(`hsk_gpu_attach_wayland`); Skia's copy of the Vulkan headers ships no
`vulkan_wayland.h`, so the shim declares that extension's one struct
and entry point as Khronos's header does. A Wayland surface has no
size until a buffer gives it one (`currentExtent` is 0xFFFFFFFF), so the
extent is the shell's — the logical size times the buffer scale — as
Android's is the window's. The first frame after the first configure
attaches, a new size or scale attaches again, and teardown detaches
before the connection closes; the shell still sets the buffer scale,
which the present's commit carries.

Frames are paced by the surface's frame callback, as on the CPU path.
Each GPU frame asks for one and commits it itself after the present,
so a frame the shim could not present still gets its callback and the
clock never stops for good. The present is FIFO, under that callback:
Mesa's FIFO present waits on a frame callback of its own, which comes
with the shell's, and a window the compositor shows nothing of gets
neither, so it is never presented to rather than blocking inside a
present. The owed frame is drawn before the loop's
`wl_display_prepare_read`, never between it and the read: the driver
reads the connection inside the present, and libwayland's read waits
for every prepared reader.

```
tools/build-skia-linux.sh
zig build run-kitchen-sink -Dskia -Dgpu
```

**Unverified: no machine.** `check-targets` compiles shell.c both ways
against declarations of the Wayland, xkbcommon and dbus calls it makes
(src/platform/linux/check_headers, since none of those headers exist on
a Mac), and `nokre_skia_vk.cpp` and the shim's GPU mode for
x86_64-linux-gnu; nothing else has happened. The script has never run,
nor the link against its libc++ archive; no frame has been drawn on
either path, including the CPU path's new frame callback; no driver
(Mesa's or NVIDIA's WSI) has answered the extent, the format, the image
usage or the fallback; the reasoning above about Mesa's FIFO wait and
the extra commit is reasoning, not a trace; and the frame costs are
unknown.

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
| Shadow | `ShadowMask.coverageAt`: the smoothstep of rounded-box distance, both passes, the chrome's contact shadow, and depth's drop shadow | `MaskField`: blur, radius, peak; the reach is the pieces' union, drawn as one rect |
| Frost | the frame drawn so far, snapshotted on the GPU beneath the plate; halved; three separable box-blur passes at both radii; sampled back and mixed per plate pixel | `FrostStyle`: radius, tint, gain |

The CPU's comptime tables are their formulas again: the specular's
falloff is `round(4096 · exp(−2.2 · i/64))`, and the face's
`darkened` search is the inequality it solves, `under · c > 255 ·
bytes − 128` (lamp_pixels.zig holds the two equal for every byte).

**No readback in a frame.** The frost copies from the destination on
the GPU, so a frame draws straight onto the drawable's texture — which
is why the layer is not framebuffer-only — and the offscreen-then-copy
path is gone. No op blends with the destination: Ganesh on Metal has no
framebuffer fetch, so such a blend copies what it reads once per draw,
and each copy ends the frame's render pass. The chrome's contact line
took one until it became a contact shadow (lamp.md, "Chrome edges are
lights"), and a secondary button's ring until it became a stroke
(lamp.md, "Buttons under the lamp"): plain composites both.

**The frost is the CPU's integers.** The snapshot is the plate out to
its reach; each pixel is read as the CPU's luminance, every channel
rounded to its byte and then `(77·r + 150·g + 29·b) / 256` in ints, not
a float dot product, so a gray pixel reads its own byte; the half frame
is each 2×2 sum times 64, 8.8 fixed point in
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
contact lines, which read the frame then, and three nav frosts) cost 3.85 / 4.76 ms of waiting, the
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

**Accuracy.** `zig build check-gpu -Dskia -Dgpu` builds the golden
suite's lamp-dark scenes with the GPU shim linked, draws each take on
an offscreen Metal surface, reads it back, and compares it with its
committed golden file (tests/gpu_accuracy.zig). It draws nothing on the
CPU and asserts nothing the `-Dgolden` gate asserts: the CPU's bytes are
the file on disk, and what the check builds on the CPU is only the
scene and its recorded ops, which say which effect drew each pixel.
A pixel's difference is its most distant channel of the three: a lamp
take is gray but for a `picture`, and `picture-under-glass-lamp-dark`
puts pictures under the nav plates, so the frost's read of a colored
frame (`frameByte` against the CPU's `luma`) is held there.
Only the tests whose names say "lamp dark" are compiled, and the
suite's last test fails naming any lamp-dark golden no take drew, so a
take in a test named otherwise is not skipped in silence. Then one take per
effect through each quarter turn a pre-rotated swapchain draws through
(`hsk_surface_turn_gpu`), read back unturned, against the same targets
([Android](#android)). `zig build check-gpu-sweep -Dskia -Dgpu` turns
every take instead, and is run before a release rather than with the
gates; both judge by the same targets and print the same table.

The turn is one matrix whatever is drawn, so what it does is proven
once, by unit tests of the shim's maps in the same file, with no
device: the base matrix at each turn, a pixel and a rect through it at
odd frame sizes, the extent a quarter turn swaps, the frame's corners
onto the image's, and every pixel back through the inverse — each held
to the turned readback, which reads the image pixel a display shows
(`shownAt`) on integers and not through that matrix. What only a
render shows is an effect surviving it: one that places itself by
device pixels, reads the frame drawn so far, or has a shader of its
own. So each route by which an op reaches the device is turned once,
by the take that draws it (`turned_takes`), and a turned take must
still draw every effect it is named for. The offscreen image starts
mid-gray on this surface alone, because lamp dark's void is 0x00, which
a new texture may already hold, and a ground placed off the turned
image passed for it.

| Effect | What it proves under the turn | Turned take |
| --- | --- | --- |
| ground | the void's tile, drawn in device space | sheet-over-scrolled |
| rim | `RimField` over device-space pieces | sheet-over-scrolled |
| face and sheen | `FaceField`'s three draws, matte and glass | sheet-over-scrolled |
| shadow | `MaskField`, both passes | sheet-over-scrolled |
| contact shadow | `MaskField`, chrome's edge | sheet-over-scrolled |
| frost | the snapshot through the turn, sampled back through its inverse | sheet-over-scrolled |
| lit glyphs | the glyph's shader under its own local matrix | sheet-over-scrolled |
| fills, stroke, line, text | Ganesh's own geometry through the matrix | sheet-over-scrolled |
| veil | a one-byte tile's shader | sheet-over-scrolled |
| clip | a scroll region's clip through the turn | sheet-over-scrolled |
| dither | a tiled pattern's shader | stage-touch |
| window | a window's CPU raster, put down whole at device pixels | stage-touch |

Each was broken once and restored: a wrong constant in the rim's
shader fails 30 unturned takes by name; a wrong translation in the
three-quarter turn's matrix fails every turn unit test but the
extent's, and both turned takes at 270°; and placing the frost's
snapshot, a window's raster, the ground, or the lamp's pieces without
the turn fails a turned take at 90° while every unturned take passes.

In the sweep, plates land at every turn exactly where the unturned
take does. Frost keeps the unturned take's maximum at every turn; its
mean is the unturned one's where it lies over plates alone, and drifts
by a few thousandths where it lies over scrolled text (page-scrolled
0.095 → 0.109, sheet-over-scrolled 0.043 → 0.046, notices-pane 0.008 →
0.013), because it blurs glyphs Ganesh rasterises differently under the
turn. Lit glyphs land within a byte of the unturned take (page-scrolled's
max 1 → 2, the target): a lit glyph's coverage is Ganesh's under the
turn. Text and anti-aliased edges, rasterised in the turned space, grow
to a max of up to 188 and a mean of up to 3.5 (frosted-chrome's, with
no glyph under a turn that moves, stays at 23 / 0.03). Dark only: lamp light is
depth light and draws no lamp op, so no shader has a light variant.
Pixels are sorted by what drew them: text and anti-aliased edges
(every glyph run's box but a lit one's, and each rounded fill, stroke
and frost's corner squares) are reported and not held, since Ganesh
rasterises glyphs and curves its own way; a lit glyph's box, less the
corner squares drawn through it (a focus ring's), is held to 2 bytes —
Ganesh's glyph coverage under the glyph's shader, which lands within
the tile's; what a frost covers is held to 4; the plates and the
ground — the void, rims, faces, shadows,
contact shadows over depth's fills — to 2.
Max / mean byte difference on an M4, unturned (every take's first
line in `check-gpu` and `check-gpu-sweep` alike); the turned figures
above are `check-gpu-sweep`'s:

| Take | Plates + ground | Frost | Lit glyphs | Text + AA (max) |
| --- | --- | --- | --- | --- |
| elements | 1 / 0.006 | — | — | 48 |
| button-forms | 1 / 0.000 | — | — | 27 |
| button-in-progress | 1 / 0.001 | — | — | 45 |
| meter | 1 / 0.001 | — | — | 26 |
| tiles | 1 / 0.024 | — | 1 / 0.354 | 36 |
| accessibility-toggles | 1 / 0.005 | — | — | 13 |
| dial | 1 / 0.000 | — | 1 / 0.006 | 8 |
| select-picker | 1 / 0.004 | 1 / 0.008 | 1 / 0.435 | 24 |
| nav-bottom | 1 / 0.000 | 1 / 0.013 | 1 / 0.031 | 7 |
| sheet | 0 / 0 | 1 / 0.008 | 1 / 0.029 | 49 |
| notice-banner | 0 / 0 | 1 / 0.007 | 1 / 0.022 | 1 |
| notices-pane | 1 / 0.000 | 1 / 0.008 | 1 / 0.019 | 4 |
| nav-with-indicator | 1 / 0.000 | 1 / 0.017 | 1 / 0.028 | 7 |
| frosted-chrome (2×) | 0 / 0 | 1 / 0.000 | — | 23 |
| header-action-two | 0 / 0 | — | 1 / 0.000 | 1 |
| page-scrolled | 1 / 0.008 | 1 / 0.095 | 1 / 0.037 | 43 |
| sheet-over-scrolled | 1 / 0.008 | 1 / 0.043 | 1 / 0.027 | 46 |

Every take meets all three targets.

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

## Consumers

A consumer's app takes the GPU the way it takes its look: from its
build.zig declaration, `AppOptions.raster` (`nokre.Raster`), resolved by
`addApp` against the GPU archives in the nokre checkout
(src/raster.zig holds the table and which script builds each archive):

| `raster` | GPU archive built | Not built | No GPU archive for the target |
| --- | --- | --- | --- |
| null, look `lamp` | GPU | CPU, and a build note naming the script | CPU, noted |
| null, `eink` or `depth` | CPU | CPU | CPU |
| `.gpu` | GPU | the build fails, naming the script | the build fails |
| `.cpu` | CPU | CPU | CPU |

The targets with an archive are macOS arm64, iOS, Android, and Windows
and Linux x86_64; every other native target is the last column, and the
web ignores the field (the browser draws, [dom-substrate.md](dom-substrate.md)).
The note is printed once per build, while the graph is made, however
many lamp apps the build holds.

**One declaration, every artifact.** The desktop executable links the
GPU shim, the archive and the shell compiled with `NOKRE_GPU`
(`addDesktopApp`). The iOS and Android libraries are the GPU shim and a
checked archive respectively, and the half each platform project
compiles itself is told by the packaging tree, resolved per platform
whatever this build's own target is — `zig build pkg` runs for the host:

- `pkg/ios/nokre_raster.h` defines `NOKRE_GPU` for the GPU, and the iOS
  shell includes it first and refuses to compile without it — a shell
  that silently compiled for the CPU would present a GPU shim's app on
  the CPU. `pkg/ios/raster-<sdk>.rsp` is a clang response file: the
  SDK's Skia archive by absolute path, and Metal for the GPU. The
  project names `$(SRCROOT)/build/zig-$(PLATFORM_NAME)/pkg/ios` in
  `HEADER_SEARCH_PATHS` and
  `@$(SRCROOT)/build/zig-$(PLATFORM_NAME)/pkg/ios/raster-$(PLATFORM_NAME).rsp`
  in `OTHER_LDFLAGS`, in place of `-lskia` and a Skia search path. Not
  an xcconfig: build settings are fixed before any phase runs, and
  these are written by the Zig phase, which runs before the app target
  compiles. A changed header recompiles the shell (it is a compile
  dependency), and the link reruns because the shim archive changed.
- `pkg/android/raster.cmake` sets the archive, the shim's Vulkan half,
  its defines and include directories for a CMakeLists to `include()`
  with `NOKRE_ROOT` and `ANDROID_ABI` set, and fails naming the script
  when the archive is missing; `package.properties` carries `min_sdk`,
  30 for the GPU and 26 otherwise, for Gradle's `minSdk`.

The example projects read the same files, so a copied project needs no
switch of its own. What stays on the CPU whatever the declaration says:
`addGoldenTests` and `linkSkia` (the golden oracle), the harness, and
`addDriver` and `addDevStoreDriver` — a driver presents no window (it
names the headless shell) and links the CPU shim through `linkSkia`.
`tests/declared_raster.zig` holds the link: a lamp app built through
`addApp` asks the shim it linked whether it draws on the GPU, against
what the build resolved.

## Presenters per shell

What each shell presents with today, and what the GPU path makes it:

| Shell | Today (CPU) | GPU |
| --- | --- | --- |
| macOS | the frame copied into an IOSurface on the view's layer, display-link paced | Metal: `CAMetalLayer`, the same display link, a resize presented in its transaction (`-Dgpu`, built) |
| iOS | the frame copied into an IOSurface on the view's layer, `CADisplayLink` paced — macOS's presenter | Metal: the view's layer a `CAMetalLayer` (`+layerClass`), the same display link, a layout's frame presented in its transaction (`-Dgpu`, built; simulator-verified, unverified on a device) |
| Android | `SurfaceView` + `ANativeWindow_lock`, Choreographer paced | Vulkan: a FIFO swapchain on the same `SurfaceView`'s window, pre-rotated to the display's turn, still Choreographer paced, remade when the window's size or the turn moves (`nokreRaster=gpu`, built; verified on a MediaTek tablet) |
| Windows | the frame swizzled into a DIB section and `BitBlt` to the window, paced by a `DwmFlush` frame clock (unverified: no machine) | Vulkan: a FIFO swapchain over the `HWND` (`VK_KHR_win32_surface`, `vulkan-1.dll` opened at run time), the same clock, remade at `WM_SIZE` (`-Dgpu`; written, compile-checked, unverified: no machine) |
| Linux | `wl_shm` double buffer, paced by the surface's frame callback (unverified: no machine) | Vulkan: a FIFO swapchain over the `wl_surface` (`VK_KHR_wayland_surface`, `libvulkan.so.1` opened at run time), sized by the shell, presented on the frame callback (`-Dgpu`; written, compile-checked, unverified: no machine) |

The web is not on this list: the DOM substrate has no Skia and no frame
of its own ([dom-substrate.md](dom-substrate.md)).
