# Skia: dependency strategy

nokre uses Skia as a rasterizer behind a ~15-function C shim
([shim/nokre_skia.h](../../shim/nokre_skia.h)). No PDF, no animation
modules — the shim is the entire contract, which is what makes swapping
or shrinking Skia later a contained problem. Every default build is CPU
raster only; the GPU backend for the `lamp` theme — Ganesh on Metal on
Apple, Ganesh on Vulkan on Android, one per platform — is in separate
archives built below and linked only for an app whose declaration
resolves to the GPU ([gpu.md](gpu.md) records why, and its
[Consumers](gpu.md#consumers) section the resolution); Ganesh on Vulkan
on Windows and Linux is scripted and unrun.

**What a consumer builds.** Every archive lives in the nokre checkout's
`deps/`, so the scripts run there, once per machine and per Skia pin,
and never in a consumer's tree. The CPU ones are the prerequisite of any
native build: `tools/fetch-deps.sh` for the desktops, and
`tools/build-skia-ios.sh` and `tools/build-skia-android.sh` for the two
mobile targets. The GPU ones are the prerequisite of a *fast* lamp app,
not of a working one: an app declaring `lamp` builds without them, on
the CPU, and the build names the missing script — `tools/build-skia-macos.sh`,
`tools/build-skia-ios.sh --gpu`, `tools/build-skia-android.sh --gpu`,
and `tools/build-skia-windows.sh` and `tools/build-skia-linux.sh`, each
of the last two on its own OS. Only an explicit `.raster = .gpu` makes
one a hard prerequisite.

## Today: prebuilts

`tools/fetch-deps.sh` downloads a pinned prebuilt
([aseprite/skia](https://github.com/aseprite/skia/releases), tag
`m124-08a5439a6b`) into `deps/skia/` (gitignored):

```
deps/skia/
  include/   modules/   src/      # headers
  lib/libskia.a                   # + bundled freetype, harfbuzz, etc.
```

Link requirements (wired in [build.zig](../../build.zig)): `libskia.a`,
libc++, system `zlib` (the bundled FreeType inflates gzipped tables), and
on macOS the CoreFoundation/CoreGraphics/CoreText/CoreServices frameworks.
The Windows prebuilt differs in shape, not idea: `skia.lib` is the same
everything-bundled archive, MSVC-ABI (so build.zig targets
`x86_64-windows-msvc` and links Visual Studio's static C++ runtime), its
zlib is Chromium-prefixed so FreeType's plain-named gzip references
resolve to a never-runs stub
([shim/nokre_skia_zlib_stub.c](../../shim/nokre_skia_zlib_stub.c)),
and text goes through FreeType with the memory-only font manager
rather than DirectWrite.

The shim compiles with `-std=c++17 -fno-exceptions -fno-rtti` and is the
only C++ in the project.

## iOS: built from source

No prebuilts exist for iOS, so `tools/build-skia-ios.sh` compiles the
same pinned tag from source into
`deps/skia-ios/{iphoneos,iphonesimulator}/libskia.a` — CPU raster only
(no GPU backends, codecs, or shaping modules; none need third-party
checkouts, so the build takes minutes). CoreText still supplies fonts,
matching the macOS prebuilt, and headers keep coming from `deps/skia`.
One consequence of compiling the codecs out: Skia's image-flattening
path still names the PNG encoder.
[shim/nokre_skia_nocodec_stub.cpp](../../shim/nokre_skia_nocodec_stub.cpp)
satisfies it (shared with Android's build);
[shim/nokre_skia_ios_stub.cpp](../../shim/nokre_skia_ios_stub.cpp)
adds the one other symbol Apple's static linker demands. Both are
definitions that must never run; the rationale for each is in the file.

`tools/build-skia-ios.sh --gpu` is the same script with the macOS GPU
build's one backend switched on — `skia_enable_ganesh=true`,
`skia_use_metal=true`, Dawn off, everything else as above — into
`deps/skia-ios-gpu/{iphoneos,iphonesimulator}/libskia.a` (about 20 MB
each against the CPU archive's 11), with its checkout's `include/` and
skcms's two public headers beside them, since `deps/skia`'s prebuilt
headers have no `gpu/ganesh/mtl`. The CPU archive and its default path
are untouched; an Xcode project links this one only when the app's
declaration resolves to the GPU ([gpu.md](gpu.md#consumers)). It takes about five minutes
on an M4.

## macOS with Metal: the GPU build

The reversed GPU refusal ([gpu.md](gpu.md)) needs a macOS archive with
Metal in it, and the aseprite prebuilt has Ganesh on OpenGL only.
`tools/build-skia-macos.sh` compiles the same pinned tag from the same
source checkout (`deps/skia-ios-src`, cloned at the tag if absent) into
`deps/skia-macos-gpu/lib/libskia.a`, with that checkout's `include/`
beside it in `deps/skia-macos-gpu/include/` — its own directory, so the
CPU prebuilt in `deps/skia` is untouched and every default build keeps
linking it. The gn args are the iOS profile with one backend switched
on: `target_os="mac"`, `target_cpu="arm64"`, `is_official_build=true`,
`skia_enable_ganesh=true` and `skia_use_metal=true`; Graphite, OpenGL,
Vulkan, ANGLE and Dawn off; no ICU, no expat, no codecs, no zlib, no
FreeType, no HarfBuzz or shaping modules, no PDF, SVG or Skottie.
CoreText supplies fonts, as it does for the prebuilt. Metal is a system
framework, so the build still needs no third-party checkouts; it takes
a few minutes on Apple Silicon and refuses an Intel Mac, whose shell
could not link an arm64 archive.

`tools/fetch-deps.sh` does not run it, the same as the iOS and Android
builds: fetch-deps fetches published archives, and this one is built
locally until the release artifacts below exist. A GPU raster links it
— the shim's GPU half (`shim/nokre_skia_mtl.mm`, compiled with the
archive's client defines `SK_GANESH` and `SK_METAL`), the GPU archive,
Metal, QuartzCore and IOSurface — for a lamp app, or any app under
`.raster = .gpu` or nokre's own `-Dgpu` ([gpu.md](gpu.md#consumers)). Every codec is off in
this archive as in iOS's, so the shim carries the same PNG encoder stub
(`shim/nokre_skia_nocodec_stub.cpp`), and the script ships skcms's two
public headers beside `include/`, since `SkColorSpace.h` includes them.

## The web builds no Skia at all

It used to: a from-source wasm build with FreeType and a memory-only
font manager, and a project-local emscripten SDK to link it. All of
that is gone. The web's substrate renders the tree as markup and the
browser rasterizes it ([dom-substrate.md](dom-substrate.md)), so there is
no Skia in that build to configure, pin, or carry — and one fewer
target on the list below.

What the web kept is the part that was never Skia's: layout comes from
core's integer math over HarfBuzz's advances, which is the half of
determinism that travels. What it gave up is the other half, knowingly.

## Android: built from source, FreeType from memory

`tools/build-skia-android.sh` compiles the same minimal profile with the
NDK's toolchain into `deps/skia-android/<abi>/libskia.a` (arm64-v8a by
default; `ABIS="arm64-v8a x86_64"` for Intel-host emulators). Android
*has* a platform fontmgr, but using it would mean expat plus whatever
fonts the device ships — so the build keeps the memory-only manager
(the shim selects it under `__ANDROID__`) and the same three pinned
externals. Two Android-only wrinkles, explained in the script: the
FreeType config Skia hands this target defines
`FT_CONFIG_OPTION_USE_PNG` (color bitmap glyphs), so libpng has to
really be in the archive — and `skia_use_system_libpng` defaults *on*
in an official build, which assumes a system libpng Android does not
ship, so it is set false and folds the bundled libpng and its zlib in.
The example's CMake
([examples/kitchen_sink/android](../../examples/kitchen_sink/android))
compiles the shim with the same NDK and links everything, reusing the
nocodec stub.

`tools/build-skia-android.sh --gpu` is the same script with one backend
switched on — `skia_enable_ganesh=true`, `skia_use_vulkan=true`; GL,
ANGLE, Metal, Dawn and Graphite off, everything else as above — into
`deps/skia-android-gpu/<abi>/libskia.a` (about 19 MB for arm64-v8a),
with its checkout's `include/` (which carries Skia's own Vulkan headers
under `include/third_party/vulkan`) and skcms's two public headers
beside it, `deps/skia-ios-gpu`'s layout. It clones one external the CPU
profile does not: the Vulkan Memory Allocator (`skia_use_vma`), Skia's
allocator for a context given none, at the revision `DEPS` pins. The
CPU archive is untouched; a Gradle project links this one only when the
app's declaration resolves to the GPU ([gpu.md](gpu.md#consumers)). It takes a few minutes
on an M4.

## Windows and Linux with Vulkan

The desktop prebuilts carry Ganesh on OpenGL only (Windows adds
Direct3D), and nokre's GPU path off Apple is Vulkan alone
([gpu.md](gpu.md#windows)). `tools/build-skia-windows.sh` and
`tools/build-skia-linux.sh` compile the pinned tag from the shared
source checkout with the Android `--gpu` profile retargeted:
`skia_enable_ganesh=true`, `skia_use_vulkan=true`, `skia_use_vma=true`;
GL, ANGLE, Direct3D, Metal, Dawn and Graphite off; every codec, shaping
module, ICU, PDF, SVG and Skottie off; no system libraries; FreeType,
libpng and zlib bundled and the memory-only font manager
(`skia_enable_fontmgr_custom_empty`, with Windows's DirectWrite and GDI
managers and Linux's fontconfig switched off), the shim's text stack on
both. Each clones the Android GPU profile's four externals at the
revisions `DEPS` pins, and lays its output out as
`deps/skia-android-gpu` is: the archive under `lib/`, the checkout's
`include/` (Skia's Vulkan headers among it) and skcms's two public
headers beside it.

- **Windows** (`deps/skia-windows-gpu/lib/skia.lib`): run in Git Bash
  on an x86_64 Windows host with git, Python 3, Visual Studio 2022 or
  its Build Tools (the C++ workload and a Windows SDK) and LLVM for
  Windows, whose `clang-cl` gn is pointed at (`clang_win`, `LLVM_DIR`).
  MSVC-ABI with the static runtime (`-MT`), as the prebuilt is, since a
  Windows app links as x86_64-windows-msvc against `libcpmt`.
- **Linux** (`deps/skia-linux-gpu/lib/libskia.a`): an x86_64 host with
  git, python3, clang and libc++ (with libc++abi); the archive is
  compiled against libc++, as the aseprite prebuilt is, because zig
  links the app with its own libc++.

Both are **unrun**: written on a Mac, which can build neither, so no gn
argument above has been through gn on its platform, and whether the
Windows archive still wants the zlib stub the prebuilt needs is
unknown. An explicit `.gpu` (or `-Dgpu`) without the archive stops the
build before compiling and names the script; a lamp app without it
builds on the CPU and prints a note naming the script. Every default build is untouched.

## Which scaler, and why it is not one scaler

These prebuilts use the platform font manager (CoreText on macOS,
FreeType on Linux/Windows). Glyph rasterization therefore matches across
runs and machines *per platform*, and differs across platforms — which is
where the pixel model's guarantee stops on purpose, not a gap it is
waiting to close ([pixel-model.md](pixel-model.md)). Text that looks like
the platform's text is text the platform's users can read; a build that
imposed one rasterizer everywhere would buy an identity nobody asked for
at the cost of the only thing the device knows better.

Text *shaping* is deliberately not Skia's problem: every build above
keeps `skia_use_harfbuzz=false`, `skia_enable_skshaper=false`, and
friends. HarfBuzz is fetched by `fetch-deps.sh` (pinned, hash-checked)
and compiled straight into the shim as one amalgamated translation unit
wherever `nokre_skia.cpp` is compiled — build.zig for desktop and iOS,
the kitchen sink's CMakeLists for the NDK. That keeps the pinned Skia archives untouched, gives shaping
one code path on every platform, and makes glyph choice and advances
(integer 26.6 math) platform-identical while rasterization stays each
scaler's own.

## Next: nokre-owned builds

A packaging errand ([../roadmap.md](../roadmap.md)): the desktop targets
depend on someone else's release cadence for an archive carrying far more
Skia than the shim asks for, while iOS and Android already compile the
minimal profile from source. The plan, in order:

1. Build the same minimal profile for the remaining targets — macOS and
   Windows — stripped to CPU raster, no GPU (`skia_use_gl=false` etc.),
   no image codecs, keeping each target's existing font backend.
2. Publish as GitHub release artifacts; point `fetch-deps.sh` at them.
3. Regenerate the golden set once, on macOS, if the new archive moves a
   byte.

The shim API does not change at any step, and neither does the scaler
question above: this is about what nokre ships, not about making every
platform draw the same picture.
