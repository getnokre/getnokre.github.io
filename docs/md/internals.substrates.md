# Substrates

Why the door is open, which seams keep it open, and what a second
substrate owes the first — so a future change doesn't close the door by
accident.

This was a design note before it was anything else (a game-engine
substrate was the motivating thought experiment). One substrate has since
walked through the door: the **DOM substrate**
([dom-substrate.md](dom-substrate.md)), which interprets the tree as
markup. What follows is still the general contract; that document is the
particular one. A substrate is the axis [axes.md](axes.md) defines; this
page is what one is held to.

## The tree is the contract

An app expresses zero visual intent — the refusals in
[introduction.md](../introduction.md) (no styling hooks, no custom
widgets) mean no app can depend on presentation. That is what makes a
second renderer possible by construction: a renderer is an
*interpretation* of the semantic tree, the way a browser interprets HTML.
It may draw each element however it likes, with capabilities the Skia
substrate refuses, so long as the semantics — element set, behavior, focus
model, a11y tree — are conveyed faithfully.

Consequently the guarantees split:

- **Per-substrate:** grayscale, CPU raster, pixel determinism, byte-exact
  goldens. These belong to the Skia substrate, which remains the reference
  implementation ([pixel-model.md](pixel-model.md) is its contract). A
  substrate on a platform that will not be told what to do adds to this
  column rather than pretending — the DOM substrate moves *no fractional
  scaling* and *no system fonts* into it, and says so.
- **Cross-substrate:** the semantic tree, event behavior, focus traversal,
  the accessibility snapshot, and the validate/audit rules — all of which
  live on the tree, so they hold regardless of renderer.

## The seams, and the disciplines that keep them

- Elements ([element.zig](../../src/core/element.zig)) are pure data.
  [renderer.zig](../../src/render/renderer.zig)'s `drawNode` switch *is*
  the Skia substrate's interpretation. A second substrate is a sibling
  renderer walking the same tree — never draw methods on elements.
  **Renderer owns drawing; core never learns a backend exists.**
- Geometry stays in core. Layout rects feed hit testing, scroll, focus,
  and a11y bounds, so a new substrate's freedom is *within* each element's
  rect, not over the boxes themselves. Substrate-owned layout inverts the
  event flow — the backend resolves hits and delivers semantic events —
  which the DOM substrate needed and `App.deliverSemantic` now answers:
  a press, a focus move, a choice. The inversion is only about *which
  element was meant*. Everything else an input carries stays in core, and
  a substrate that restated any of it would be keeping a second copy of a
  rule with one home ([dom-substrate.md](dom-substrate.md) has the bug
  that taught this).
- Shells name no backend. A shell's job is events in and blit the buffer
  it is handed ([platform-shells.md](platform-shells.md)), so
  [c_shell.zig](../../src/platform/c_shell.zig) holds a
  `FrameSource` — one `render` call plus `deinit` — and the platform file
  names the installer its Runner runs before the loop starts.
  [skia_frame.zig](../../src/platform/skia_frame.zig) is the reference
  substrate's: surface lifecycle, the staleness check, `renderer.render`. A
  second substrate installs its own and touches no shell. This seam was
  added late — the surface used to live on the shell state, which would
  have meant forking five shells per substrate.
- A desk owes a second substrate five places at the edges, and the roles
  name them ([elements.md](../elements.md)): a strip pinned to the top,
  a leading column, the subject between them, a trailing column, and a
  strip pinned to the bottom. Each clips and scrolls independently — the
  two pinned strips included, which is what keeps a composer that ran
  long reachable — and a region layout marked folded is off the screen
  entirely, subtree and landmark with it. Each is exposed as the
  landmark its role names, named by its own `label`.
- The hairline between two of those places is **presentation**, and a
  substrate may draw it any way its medium draws a rule. What is not
  presentation is that the separation is there at all: grayscale has
  nothing else to tell two columns apart, and a desk drawn without it
  reads as one wide page.
- Pixel goldens cannot apply to a non-reference substrate. Its conformance
  test is a **renderer contract**: per element, what MUST be conveyed
  (disabled visible, focus always indicated, notice prominence ordering,
  …). The audit rules are the seed of that contract. Where a substrate's
  output is itself deterministic text, it gets the golden discipline
  back one layer out: the DOM substrate diffs *markup* byte for byte,
  which a human reads instead of a picture.

## The cost, named honestly

Every new element is one draw implementation *per substrate*. The
contributing checklist multiplies. This is the recurring tax of a second
renderer, and it is bearable only because the element set is closed —
which is one more reason it stays closed.
