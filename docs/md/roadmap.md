# Roadmap

The foundation is done and tested: the core model, layout, events, focus,
router, renderer, a11y derivation and the audit over it, the testing
framework and the driver tier that runs an app outside `zig test`, the
localization toolchain (comptime catalogs, the host checker, the
formatter, the purge tool and the two drafting tools), packaging — icons,
the share card, store listings and store screenshots — the five platform
shells and the web's shell-less browser build, deep links, and IME on
every platform, the web included — the support matrix is in the
[README](../README.md), the per-shell contract in
[internals/platform-shells.md](internals/platform-shells.md), and the
service roster with its per-platform status in
[services.md](services.md). What follows is what remains, ordered by
leverage.

## 1. More substrates

An app is a semantic tree; what draws it is a *substrate*, and a substrate
is entitled to an opinion. The Skia substrate rasterizes a grayscale frame
that is the same bytes every run on the platform that produced it; the
DOM substrate hands the tree to the browser and lets it wrap where the
reader's text size says it wraps. Same app, same semantics, two
renderings, and neither is the other's fallback — the contract a third
one inherits is
[internals/substrates.md](internals/substrates.md).

Byte-identity *across* platforms is not on this list and is not coming.
It would mean deciding, from here, that an e-reader and a phone owe
their readers the same picture, which is the one judgement the device is
better placed to make than the library
([internals/pixel-model.md](internals/pixel-model.md) draws the line the
guarantee actually stops at). The tree travels; the drawing is local.
The substrates worth building are the ones whose native mode nokre already
describes:

- **E-ink.** No animation, no color, no ticker, no frame until state
  changes — the refusals read like an e-paper datasheet written from the
  other side. What such a substrate adds is what the panel wants back: a
  damage region per commit, so a screen that changed one row refreshes
  one row instead of flashing whole.
- **Terminals.** A cell grid is integer layout with a coarser pixel, the
  element set is already rows and text, and the interaction model is
  keyboard-first with nothing that a pointer alone can reach. Line and
  box drawing land on box-drawing characters; the accessibility snapshot
  is close to what the renderer would emit anyway.
- **Watches and monochrome heads-up displays.** A glance-sized viewport
  with one gesture and no room for chrome, where the closed element set
  and *waiting is written in words* stop being constraints and start
  being the only thing that fits. The nav's collapse is not the answer
  it looks like: forty settings rows are forty settings rows at 396px,
  and folding the chrome above them does not make the screen a glance.
  The substrate is the smaller half of that problem. The larger half is
  that a glance device wants screens authored for it — an app of its own
  out of the same package rather than a smaller copy of this one — which
  is [getting-started.md](getting-started.md), "Several apps in one
  package", and not this section's.

The bar is the one the DOM substrate set: the renderer's element switch
has no `else`, so a second substrate draws every element or fails to
compile, and the focus model, the validate/audit rules, and the a11y
tree hold unchanged because they live on the tree rather than on any
renderer.

## 2. Tooling

- Semantic-tree dump (debug print of any screen from a test)
- Golden diff visualizer (side-by-side PPM compare)

## 3. A status nobody hears on three platforms of five

A `status` node — a notice, a stand-in, the copy acknowledgement — is a
polite live region on the two backends that have the concept: the
browser's `role="status"` and AccessKit's. On iOS and Android it is
only a node a reader can walk onto. The iOS shell posts
`UIAccessibilityLayoutChangedNotification` with no string, and the
Android one a bare `TYPE_WINDOW_CONTENT_CHANGED` with no
content-change type and no live region set. So words that arrive on
their own are *read* on five platforms and *announced* on two.

The two calls that close it are
`UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, …)`
in the iOS shell and `setAccessibilityLiveRegion` on the host view in
`NokreView`. Both are a shell's own, neither touches core, and the
snapshot already carries the words they would speak.

**What holds it here is that no gate in this repository can see an
utterance.** A VoiceOver or TalkBack announcement is not a tree, a
frame or a snapshot: no `zig test`, no golden and no driver observes
one, so a lane that shipped both calls would be shipping the claim and
not the behavior. The gate is a device with a screen reader on it.
Until then, being read is the guarantee that holds everywhere, which
is why a notice's whole message rides in its name
(`Notice.reading`) and why a `status` node is never handed a headline
with the rest somewhere else.

## 4. Skia, smaller and published

The desktop builds link a pinned third-party prebuilt that carries far
more Skia than the ~15-function shim asks for; iOS and Android already
compile the minimal profile from source. Building that same profile for
every Skia target and publishing the archives as release artifacts —
plan in [internals/skia-build.md](internals/skia-build.md) — removes a
setup step and a dependency on someone else's release cadence. It is a
packaging errand, not a determinism one: each platform keeps the text
scaler it has.

## 5. More axis members

Four axes decide what a reader gets — substrate, medium, dwell and shape
([internals/axes.md](internals/axes.md)) — and three of them have a
member that has been named and never argued. None is proposed here. They
are written down so the surface that eventually needs one finds the
question already asked and the bar it has to clear already set.

- **A `layout.Medium` sibling.** The enum carries its own admission test:
  a member joins only by settling a question about the *tree* that core
  cannot answer without it, the way `clips` and `reflows` decide whether
  the nav is a row of destinations or a chip. A surface fact that only
  changes how something is drawn is the substrate's, and putting it here
  would move a drawing decision to where core can read it.
- **A text-entry fact on that same axis.** A surface that cannot accept
  typed text makes a `text_input` an unreachable control, and whether a
  control is reachable is a tree question rather than a drawing one,
  which is the argument that would put it on `Medium`. It has not been
  made.
- **A `distant` dwell.** TV and lean-back are a plausible third member
  beside `glance` and `sitting`. What would earn it is what earned
  `glance`: screens somebody authors for that distance rather than folds
  into it, shipped as a second app of the same package
  ([getting-started.md](getting-started.md), "Several apps in one
  package"). Noted, not proposed.

## 6. A build entry for a page generator

Every static-site generator assembles itself: `b.addExecutable`, the
nokre module, `webAssets`, the icon face, and the line naming
`nokre.headless_shell` ([static-sites.md](static-sites.md)). Two of them
do it, near enough identically, and each found the shell line by
failing to link rather than by being told.

An `addPageGenerator` beside `addApp` would state that shape once, the
way `addDriver` states a driver's. What stops it being obvious is what
`addApp` already carries: a generator's site options, its content
directories and its own faces are the consumer's, and a build entry that
took them would be a second `AppOptions` for a program that ships no
app. Not proposed — recorded so the next generator does not make the
case from scratch.
