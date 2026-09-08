# The four axes

Four independent questions decide what a reader gets. One word used to
carry the first two, which is why they are named apart here. This page
owns the vocabulary; each axis's contract lives where its code does. An
axis is a fact about the surface or about the moment, never a name for a
device — why a named platform group is neither is
[introduction.md](../introduction.md).

| Axis | Answers | Values | Decided by | Read when |
| --- | --- | --- | --- | --- |
| **substrate** | how a tree becomes output | Skia · DOM | the build target | compile time |
| **medium** | what core must know about the surface | `clips` · `reflows` | the driver | at boot |
| **dwell** | which app runs | `glance` · `sitting` | `addApp` | build time |
| **shape** | how one screen is arranged | `page` · `desk` | the route | every rebuild |

The first two are independent, and the code proves it: the DOM substrate
serves a desktop browser and a phone browser, and Skia serves five
platforms. One substrate spans several mediums; one medium spans several
substrates.

## Substrate

A substrate is a renderer and everything under it: Skia over the five
native shells, the DOM in a browser. The build target decides it, it is
settled at compile time, and it defines **tech, never UI**. A port is
not an authored variant of the app — a panel or a headset is a way of
talking to hardware, and it gets no say in which screens exist or what
is on them.

So the line a substrate may not cross is the tree. It draws every
element it is handed, however it likes; it may not add one, remove one,
or decide a screen is not worth showing. Pagination is on the substrate's
side of that line: a panel showing a long document a page at a time is
choosing how it draws, not what the screen is.

What a substrate may decide, what it inherits whole, the four seams that
keep a second one possible, and what it owes the first:
[substrates.md](substrates.md). The one that exists besides Skia is
[dom-substrate.md](dom-substrate.md).

## Medium

`layout.Medium` is the one fact about the drawing surface that settles a
*tree* question rather than a drawing one: whether a row too wide for
its space is clipped or reflowed. Core has to know, because the two
answers are different nodes — `nav.syncNavChrome` builds a row of links
or a chip, and that is decided before either renderer sees the tree. The
driver declares it through `App.setMedium`, and the default is `clips`,
the cautious answer. The test anything wanting to join the enum has to
pass is stated on the enum itself.

Medium is not substrate. One substrate spans several: the DOM substrate
reflows in a browser, and the same renderer mounted into a fixed frame
would clip. A generator states it at the top of a file it is about to
write ([../static-sites.md](../static-sites.md)); the live driver states
it at boot ([dom-substrate.md](dom-substrate.md)).

## Dwell

Whether a device is glanced at or sat with — read *before* an app
exists, so that one package can offer more than one. It is a build
declaration (`AppOptions.dwell`) and it chooses nothing at run time:
nokre has no launcher, every shell boots one artifact, and which app
runs is which artifact was installed. Two apps of one package may not
name the same dwell, which is the line that separates them.

**Nothing crosses that line while an app runs.** Unfolding a foldable,
Stage Manager, DeX, a keyboard attached mid-session — each of those is a
medium change inside one `sitting` app and never a swap to the glance
one. It is also why `glance` is a dwell rather than a `Medium` member or
a `Shape`: it states no fact about the surface a tree is drawn on, and it
is not a distinct set of answers about how one screen is arranged. It
decides which screens exist at all.

What a consumer writes, and what the two apps share and do not:
[../getting-started.md](../getting-started.md), "Several apps in one
package". What the compiled app reads back: `nokre.declared.dwell`.

## Shape

Whether a screen is a page — capped to the prose measure, one scroll,
edges nokre's — or a desk, which takes the window and holds several
`region` children scrolling independently with app-owned edges. The
route declares it (`RouteDef.shape`), `Router.rebuild` writes it onto the
tree before the builder runs, and everything else derives: the width, the
append rules, and what a window too narrow for the band does.

There is no device in that sentence, which is the point — a phone shows
a desk's regions one at a time rather than a different app's screens.
What a shape is and how one is declared:
[../routing.md](../routing.md). What a `region` is:
[../elements.md](../elements.md).

## Who decides what

The direction of travel is **fewer consumer statements, not more**. A
device conditional written by a consumer is a bug waiting for the first
device unlike its group, so wherever an answer follows from an axis,
nokre derives it and offers no knob for it.

| Decision | Whose |
| --- | --- |
| Nav shape — a row of destinations or one chip | nokre's (`layout.navCollapses`) |
| Folding an overflowing row of actions | nokre's (`overflow.syncOverflowChrome`) |
| Where a row wraps | nokre's |
| Page width | nokre's, derived from the shape |
| Which screens exist at each dwell | yours |
| In what order things appear on a screen | yours |
| Which mediums an app serves | yours, declared once |

What stays with the consumer is what nothing else can supply: what the
app is about, and who it is for. Two consequences of that direction
hardened into refusals — **no device-conditional affordances** and **no
named platform groups** — and both are argued in
[introduction.md](../introduction.md).
