# Introduction

nokre is a cross-platform app framework. You write one app in Zig; it
runs on macOS, Windows, Linux, iOS and Android, and in the browser.

What it offers is fewer decisions. Most of what a UI toolkit hands you
is a question — which widget, what color, which breakpoint, how this
reads to a screen reader, what a tablet gets, where this string lives,
what a store will accept — and every one of them is also a way to ship a
broken app: inaccessible, inconsistent across machines, untestable
without a screenshot farm, untranslated in the one language nobody
checked. nokre answers them once, in the framework, and each answer is a
guarantee rather than a default: an app built on nokre cannot have the
problem, because the framework cannot express it. You say what a screen
*is* and what is on it, and the accessibility tree, the focus order, the
navigation chrome, the layout and the pixels are derived from that; you
declare the app once, and the platform manifests, the web page and the
icon in each platform's format are written from that declaration. What
is left for you to decide is what the app says and does.

The limitation is the product. That is the mechanism and not modesty
about scope: every refusal below either holds up a promise or takes away
a question the framework never needed answered, and what the refusals
buy is the two things nokre is actually for — accessibility that is
derived rather than authored, and a toolchain that covers an app's whole
life rather than stopping at the window.

What the trade costs is expressiveness. The drawing is text, lines and
boxes, grayscale only, rasterized on the CPU by Skia, and about as
expressive as Markdown — literally: a `document` element takes a
Markdown source and expands it into ordinary elements
([markdown.md](markdown.md)) — plus actions and navigation. Think: apps
for a grayscale Kindle.

## Three promises

**Accessible by construction, and gated.** Every element is semantic — a
heading is structure, a button is a button, a label is mandatory. The
accessibility tree and the pixels are both projections of the same
semantic tree, so accessibility cannot be added and cannot be omitted.
Malformed structure is rejected at `append`, so an invalid screen never
exists. What construction cannot verify, an automatic audit catches —
and it is not something an app opts into or waives: the harness runs it
at init and after every driver action, and the entry point it calls
takes no skip options at all, so an app's own test suite cannot silence
a rule. Because the audit inspects the same tree that renders, a pass is
a guarantee rather than a lint heuristic. The full contract, rule by
rule, is [accessibility.md](accessibility.md).

**Deterministic to the pixel.** Same logical viewport ⇒ same bytes,
across runs and machines, on the platform that drew them. This one is the
*Skia substrate's* promise — the five native shells — and it stops at the
platform's edge on purpose (the section below). On the web the tree is
rendered as markup and the browser draws it, which trades these bytes for
an accessibility tree that is the page rather than a copy of it
([internals/dom-substrate.md](internals/dom-substrate.md)).
Layout is integer math; rendering has no GPU, no hinting, no subpixel
tricks. Screenshots are therefore *tests* — byte-exact, no tolerance, no
perceptual diffing. The normative rules are
[internals/pixel-model.md](internals/pixel-model.md).

**Tooled from the first string to the store page.** The framework does
not stop at the window. Catalogs are ARB files compiled at comptime,
which makes the Zig compiler the validator: a missing key, a placeholder
that changed type, a plural branch the language never selects, is a
build error rather than a blank on somebody's screen, and a host checker
your build attaches carries the six rules no `@import` can reach
([localization.md](localization.md)). Four tools work on those catalogs
— format a set, delete the keys no source names, draft a locale, draft a
Markdown document — and every draft is compiled against the template
before it is accepted, so a model's output is a proposal a human reads
and never a catalog nobody did. Tests are an e2e framework nokre ships
itself, driving the real `App` through the real event pipeline — no
browser driver, no window, no flakiness. Interactions go through the
user's pipeline; assertions read the screen reader's snapshot; end to
end means your whole app, because the harness stops at the platform
shell, which is the boundary that buys the determinism —
[testing.md](testing.md#where-the-harness-stops) names it exactly. And
shipping is in scope: packaging writes the icons and the share card, and
checks a store listing field by field against what Apple and Google
accept at upload. Your driver walks to the screen worth photographing;
nokre captures it at each family's published size and scans the pixel
buffer for a safe area it derives rather than asks for
([services.md](services.md)).

## The tree travels; the drawing is local

An app authors no pictures. It appends semantic elements — a heading is
structure, a button is a button — and what turns that tree into something
you can see is a *substrate*: the Skia one rasterizes grayscale frames,
the DOM one hands the tree to the browser and lets it wrap where the
reader's text size says
([internals/substrates.md](internals/substrates.md)).

So byte-identity *across* platforms is not a promise nokre is working
toward — it is one it declines. Making an e-reader and a phone produce
the same picture means overruling each device about its own screen, and
the device is better informed. The tree is what travels; the drawing is
local, and a golden set belongs to the platform that generated it. The
horizon is therefore more substrates rather than one rendering — e-ink
panels that refresh a row at a time, terminals, watches, monochrome
heads-up displays ([roadmap.md](roadmap.md)) — each free to be as
opinionated as its device deserves, and none of them free to drop a
label, a role, or a focus stop out of the tree it was handed. What is
*on* that tree is the app's decision and never the substrate's: a device
that should be shown less is shown less on purpose, and a package that
means it ships a second app authored for that device
([getting-started.md](getting-started.md), "Several apps in one
package").

What a substrate inherits instead of a look is a temperament. nokre's
visual decisions come from thinking of software as a calm, respectful
tool: it holds still, it says one thing at a time, it asks for attention
only when it has something to say, and it never performs. That is why the
refusals below read as a design rather than as a list of things not yet
built.

## What nokre refuses to do

Most are load-bearing for a promise above: remove one and it collapses.
The rest take away a question the framework never needed answered, which
is the product rather than a side effect of it. They are guarantees, not
gaps — an app built on nokre cannot have these problems, because the
framework cannot express them.

- **No hover states.** Interaction is press and release, key, focus, and
  one gesture — a drag in from the leading screen edge, which goes back.
  Nothing changes because a pointer floated over it: an affordance that
  only pointer users can discover is information withheld from touch and
  keyboard users, so the entire category is absent. The gesture is not
  an exception to that rule but an illustration of it — it is a shortcut
  for a control that is always on screen, focusable, and announced, and
  it reaches nothing the Back control does not.

  The pointer has a press and a release rather than a single tap because
  **activation belongs on the release**: moving off a control before
  letting go must abort it (WCAG 2.5.2), and a lone tap cannot say so.
  Two things use the gap between them, both on the same terms as the
  gesture. Holding the collapsed nav's chip opens its section list so
  the same press can choose a row by releasing on it — a shortcut for a
  list that a plain click, the keyboard, and a screen reader all reach
  anyway (WCAG 2.5.1). And while that list is open, moving the pointer
  moves *focus* to the row beneath it. That last one is the line worth
  watching: it looks like hover and is not, because hover is a state
  with no keyboard equivalent and this is the very state ↑/↓ move.
  The one drag on this list is the same bargain in a text field: a
  pointer moving inside the field it pressed moves that field's
  *selection*, which is the state Shift+arrow already moves, and
  nothing outside that field follows it.
  Nothing else on screen follows a pointer, and nothing else may.
- **No device-conditional affordances.** A control that exists on one
  kind of device and nowhere else is hover wearing a different input
  device: an affordance only some readers can discover, which is the
  category above with the discovery moved from a pointer to a piece of
  hardware. There is no call that asks what you are running on and none
  is coming. What survives is the rule the back gesture and the
  collapsed nav's chip already hold — **an accelerator may only
  accelerate a control that is on screen, focusable, and announced** —
  and it generalizes to every peripheral: a watch crown scrolls what a
  finger scrolls, a temple swipe on AR glasses reaches what Back
  reaches, a chord presses a button that exists. A device may change how
  a control is reached; it may not change whether one is there.
- **No transitions or animation.** State changes are instant. Motion is a
  vestibular hazard (WCAG 2.3.3), an untestable intermediate state, and a
  tax on determinism; nokre has none to configure or to disable. A
  spinner is animation too — waiting is written in words. The back
  gesture is where this gets tested hardest and holds: the finger moves
  and *the screen does not*, because a screen half-slid has no tree
  behind it to describe or to golden, and finishing the slide after the
  finger lifts would need frames nobody asked for. What replaces the
  motion is a threshold, marked as it is crossed —
  [routing.md](routing.md#the-back-gesture) has the mechanics.
- **No color.** Thirteen fixed steps of gray, five semantic aliases
  (`ink`, `dark`, `mid`, `light`, `paper`). Color as information excludes
  color-blind users, so information must survive grayscale anyway —
  nokre makes that the only mode, and proves the whole palette against
  WCAG contrast in unit tests, floor *and* ceiling: body text is 14.2:1,
  not the 21:1 of true black on true paper, because past a point more
  contrast stops buying legibility and starts costing comfort. Dark mode
  is a second ramp rather than an inversion of the first, so it can be
  gentler than light where light-on-dark reads heavier — a mirror moves
  every ratio together and cannot. A palette you can enumerate is a
  palette you can prove.

  One honest asterisk, framework-drawn: the Google sign-in button's
  multicolour G — a trademark whose owner refuses a gray variant. The
  framework paints it from its own renderer; there is no way for an app
  to color anything, no element that takes a color, and nothing else on
  any screen that is not gray. The refusal an app builds against is
  intact — *your* information still has to survive grayscale, because
  grayscale is still all you can author.
  [internals/oauth.md](internals/oauth.md) records why this one mark
  crossed the line and nothing else may follow it.
- **No system fonts.** Every face is bundled: one mono family, one
  proportional, one icon face, and an Arabic-script companion face
  every family falls back to for Persian and Arabic — every variant a
  real drawn face from the same upstream build (bold, italic, and
  bold-italic for the two text families; the companion has no italic,
  because the script has none), and app text can reach nothing else.
  The one family this list omits, `brand`, holds the sign-in marks
  above — reachable only from the renderer, never from app text.
  No synthetic
  emboldening or shearing either: faked variants are
  rasterizer-dependent, which is the variance the bundling exists to
  close. The moment the OS font stack participates, byte-identity
  across machines is gone. Shaping and bidirectional layout are built
  in the same spirit: HarfBuzz pinned in the shim, UAX #9 in core,
  direction derived from the text itself — never a knob.
- **No GPU.** CPU rasterization only. No driver variance, no flicker,
  no capability matrix — the same bytes everywhere is only promisable
  when no driver is involved.
- **No fractional scaling.** Layout is integer logical pixels; hidpi is
  an integer scale factor, so a 2× frame is exactly the 1× frame at
  double density. Fractional coordinates are where "looks slightly
  different on my machine" comes from.
- **No custom widgets, no styling system.** The element set is closed.
  Semantics can only be derived from elements whose meaning the framework
  knows, and contrast, target size, and labeling can only be enforced on
  elements the framework owns. A styling hook is an accessibility
  loophole. New capability means arguing a new *semantic* element into
  the set — see [elements.md](elements.md).
- **No paths.** A reference names a screen: `note~42`. It does not say
  where the screen sits, because screens do not sit anywhere. A note is
  reached from the list, from a search, from a tag, from what you
  starred. A path would have to call one of those the parent, and it
  would be wrong from the other three. The author picks one anyway,
  picks again whenever a new way in is added, and the pick goes in the
  URL, where it will not match how most people arrived. Where someone
  came from is what nav chrome, links, and the back stack already show,
  and they can differ from visit to visit because the app remembers the
  trail. A reference is only a name, so one screen has one reference,
  whoever is looking. URLs stay short as a side effect —
  [routing.md](routing.md).
- **No named platform groups.** There is no "phones", no "tablets" and
  no "wearables" to test against, and no call that hands one to an app.
  A group goes stale the first time a device is unlike its group — a
  foldable, a tablet with a keyboard, a car head unit — and it is the
  failure *no paths* already names: you pick one parent and you are
  wrong from the other three. What nokre reads instead is a fact about
  the surface in front of it, declared by whoever is drawing on it: how
  big it is, and whether it clips or reflows. A fact cannot go stale
  about the device that just reported it. The one list of device names
  in the framework is not an exception to this: `shots.DeviceFamily` is
  store geometry — the logical sizes Apple and Google publish for a
  screenshot — and nothing asks it what a device can do, only what size
  a store wants a picture ([services.md](services.md#the-families)).

What a screen *is* is the one decision of this kind nokre hands back,
and a route makes it once: `page` for prose, capped at a reading measure
and centred; `desk` for an application shell, taking the window and
holding the places you work in side by side ([routing.md](routing.md),
[elements.md](elements.md)). It is per route and never per device — no
call asks what you are running on — and it is not a width knob: you say
what the screen is, which you had already decided, and nokre derives the
width, the pinning, the scrolling and what a shrinking window does from
the answer. A member joins that set
only by answering all five of those differently, which is why there are
two of them and not a family.

The refusals also buy something quieter: a nokre app at rest costs zero
CPU. No ticker, no vsync loop, no animation frames — a frame renders when
state changes, and otherwise nothing runs.

## The vocabulary

What a consumer actually touches is small:

- **Elements** — the closed set: static text and icons, containers,
  interactive controls, navigation chrome, and layers. Every one is
  specified in [elements.md](elements.md), semantics first.
- **The tree** — a retained tree you append elements to. Malformed
  structure is rejected at `append`; an invalid screen never exists.
- **Routes and actions** — screens are named builder functions; behavior
  is plain context + function-pointer pairs. No closures are allocated,
  ever.
- **Grays and scales** — thirteen grays (you will mostly use the five
  aliases) and six type scales. Exact bytes and metrics live in the
  [pixel model](internals/pixel-model.md); you pick names, the framework
  guarantees they are legible where you put them.

## Is nokre for you?

nokre suits tools, dashboards, settings-heavy utilities, readers,
forms — apps whose value is *what they say and do*, and which would
rather inherit accessibility, pixel-exact repeatability, real e2e tests
and a tooled path to the store than decide each of them themselves.

If the product needs color, motion, media, custom visual identity, or
free-form canvases, nokre is the wrong framework — and will not grow the
features to become the right one.

## Where next

[README.md](README.md) is the full map. The usual path:

- [getting-started.md](getting-started.md) — the course: one app, every
  feature, tested and shipped to six platforms
- [elements.md](elements.md) — every element, its semantics, when to use it
- [accessibility.md](accessibility.md) — how a11y is derived and enforced
- [localization.md](localization.md) — catalogs, ICU messages, right-to-left
- [static-sites.md](static-sites.md) — what a generator states and what
  the library writes
- [testing.md](testing.md) — the harness, queries, golden screenshots
- [services.md](services.md) — OS capabilities beyond the window
- [roadmap.md](roadmap.md) — what's coming next
- [internals/](internals/README.md) — how it works inside, for
  contributors
