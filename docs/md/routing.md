# Routing

Screens are **named builder functions** and navigation is a **stack** of
them. The whole router is that: a table of `RouteDef`, a stack of entries
pointing into it, and a rebuild on every change. There are no path
patterns, no wildcards, and no transitions.

```zig
const routes = h.Routes(State).table(&.{
    .{ .name = "notes", .title = .{ .fixed = "Notes" }, .build = buildNotes },
    .{ .name = "note", .title = .{ .fixed = "Note" }, .args = 1, .build = buildNote },
    .{ .name = "settings", .title = .{ .fixed = "Settings" }, .build = buildSettings },
    // Required, once per table: where a reference that resolves to
    // nothing lands ("Where an unresolved reference lands", below).
    .{ .name = "not_found", .title = .{ .fixed = "Nothing here" }, .for_unresolved = true, .build = buildNotFound },
});

var app = try h.App.init(gpa, .{ .viewport = ..., .routes = &routes, .ctx = &state });
try app.navigate("notes");

// A screen is a function of your state and the app:
fn buildNotes(state: *State, app: *h.App) !void { ... }
```

### The state is typed once

`App.ctx` is one pointer for the whole table — the app's state, handed
back at every rebuild — so `Routes(State)` names the type once, at the
table, and every builder under it is written against that type instead of
against `?*anyopaque`. A screen that reads no state says `_: *State`,
which is more than an erased pointer ever said.

What `table` returns is an ordinary `[N]RouteDef`, and that is the point:
this is sugar over the substrate, the way the builder cursor is sugar
over `Tree.append`. The raw form stays public and stays correct — a
stateless screen written `fn build(_: ?*anyopaque, app: *App)` is a
legal entry in the same table — and `RouteDef` itself did not change to
make this possible.

An app that builds its table from something of its own — a catalog key
for a title, one entry per page from a page list — lowers builders one at
a time instead:

```zig
const R = h.Routes(State);
// `R.builder(f)` is a `RouteDef.build`: the trampoline, without the table.
defs[i] = .{ .name = e.name, .title = .{ .of_locale = titler(e.title) }, .build = R.builder(e.build) };
```

The same call types a test fixture's screen, which the harness takes at
`build` ([testing.md](testing.md)).

The one thing the types cannot check is that `App.init`'s `ctx` really is
a `*State` — no local type could, since the table and the pointer meet at
run time. What changed is that the assertion is made **once, at that
line**, instead of once at the top of every screen. `App` stays
non-generic on purpose: `*App` is in the signature of every element call,
every service, the renderer, the shells and the harness, and a
framework-wide type parameter to name a field no consumer reads past this
door is a bad trade.

A route builder is *not* a bindable `{ ctx, call }` pair
([elements.md](elements.md#binding-callbacks-nokre-never-sees)), which is
why `RouteDef` carries no context of its own: an action captures its
state when the element is appended, while a screen is handed the app's
state when the router calls it.

**Every route declares a `title`.** The field has no default, so a screen
that cannot be named is a compile error at the table rather than a blank
chip at run time. It is what chrome calls the screen: every line of the nav's roster is
labelled from it — the declared destinations, and the screen itself when
it is none of them ([elements.md](elements.md#navigation-chrome)). A nav
destination is therefore a route and a glyph, with no label of its own;
one screen has one name, wherever it is being named from.

The title is *declared*, and nothing derives it. Not from `name`, which
is an identifier and reads like one (`sign_in`). Not from the screen's
first heading, which is **content**: a builder may lead with anything,
may localize it, may not have a heading at all, and nothing obliges the
one it has to still be there after the next edit.

It names the *route*, not the screen: `note~42` and `note~43` are both
"Note". A `.of_locale` title is a function of the app's chosen locale
and of nothing else — never of the reference — so a per-instance title
stays refused: that would be a callback asking the router to find out
per screen what to draw.

### The page says what the screen is called

That refusal holds, and the arrow now runs the other way. The router
draws this title as the page's `h1`, above everything the builder
appends and below the back control that shares its line:

```zig
.{ .name = "notes", .title = .{ .fixed = "Notes" }, .build = buildNotes },
```

```zig
fn buildNotes(state: *State, app: *nokre.App) !void {
    const b = app.root();
    try b.text("Nothing yet.");   // the "Notes" heading is already there
}
```

Deriving a *declaration* from *content* was the mistake the paragraph
above refuses. Drawing content from a declaration is the opposite, and
it is what a declaration is for: the roster, the collapsed chip, the
off-roster marker and the top of the page now say one thing, and a
builder writing the same words again as an `h1` would be the second
copy of a fact the app already answered.

An `h1` is therefore not a builder's to write —
`error.HeadingAtTitleLevel`, [accessibility.md](accessibility.md) — and
a screen's sections start at `h2`.

Two screens want something else, and both say so:

```zig
try app.setTitle(note.name);   // "Note" to the chrome, its own name to the reader
try app.setTitle("");          // this screen draws no title
```

`App.setTitle` states a fact about the screen rather than appending an
element, so it may be called at any point in the build — including
after the load that produced the words — and the title still lands
where a page's title goes. A second call restates the words in the node
already standing. The chrome goes on naming the *route*, because a
roster of destinations whose builders have not run has nothing else to
name them by.

Like every other word a builder writes, the drawn title follows a
rebuild rather than `setLocale`.

A title is the words themselves or the words as a function of the
app's **chosen locale**: `.{ .fixed = "Notes" }` for an app in one
language, `.{ .of_locale = notesTitle }` for one in several. The
chosen locale is app state — `Options.locale` at boot, `App.setLocale`
after, "" until chosen, `App.locale()` to read — and choosing it
re-says every `.of_locale` title where it stands: one screen keeps one
name in every language, and the nav's row, chip and marker change
together. There is no second table to hand over.
[localization.md](localization.md#the-chrome-nokre-writes) has the
wiring, along with `App.Chrome` — the framework's own words, which are
nokre's rather than any route's.

Four motions move the stack, and every one of them rebuilds the current
screen's subtree from scratch:

| | |
|---|---|
| `App.navigate(ref)` / `router.push` | a screen deeper — gains a Back control |
| `App.navigateBack()` / `router.pop` | up one; a no-op at the root |
| `App.replaceWith(ref)` / `router.replace` | the same depth, a different screen |
| `App.switchTo(ref)` / `router.switchTo` | arriving with no trail: **the stack resets to depth 1** |
| `App.reload()` / `router.reload` | this screen, rebuilt from its own reference — the *deliberate* answer to changed state |
| `App.refresh(opts)` | the *polite* one: the open sheet rebuilt if one owns the screen, else a reload unless the user holds something a rebuild would take |

**Going back returns the screen, not just its name.** Each entry
remembers where its screen was scrolled to — the window and every
`scroll_region` in it — and `pop` puts that back before the first frame
of the rebuilt screen, so a list you were halfway down comes back halfway
down. `reload` does the same, since a screen redrawing one row should not
also move the viewport. `replace` and `switchTo` do not: neither is the
screen you left. The rebuild itself is unchanged — still from scratch,
still instant — and a screen that comes back a different shape restores
what lines up and clamps the rest; positions are matched by order, not by
identity. Focus is not restored by `pop`: the element it named is gone,
and guessing would move a screen reader's cursor somewhere nobody asked
for.

**An open sheet survives `reload` too, by the same argument.** A sheet
is declared to the app as a builder (`App.openSheetAs` —
docs/elements.md, "sheet"), and after a reload rebuilds the screen the
framework runs that builder again, so a dialog is never the reason
state cannot be answered. The other four motions drop it — each is a
different screen, and a sheet belongs to the state of the one that
opened it — and tell the builder's `on_dismiss` so.

**`reload` alone carries focus, and by name, not position.** The node
focus held goes with the rebuilt content, and an ordinal would land a
screen reader's cursor on whatever took that place — but the
accessible name survives, and the audit forbids two interactive
elements in one layer from sharing one
([accessibility.md](accessibility.md)), so within the active layer —
the rebuilt screen, or the re-presented sheet — the same name is the
same control. A control that kept its very node keeps focus outright
(chrome survives rebuilds). When nothing answers to the carried name,
focus starts over rather than guess, and a link inside prose starts
over always: its paragraph has no name of its own, and a span index is
exactly the ordinal the restore refuses to trust.

What no carry can save is an edit in flight: caret, composition, and
the unwritten value die with the field's node, and the on-screen
keyboard follows them down. `app.reloadSafe()` is that question asked
before the fact — false while an overlay owns the screen (a sheet, a
picker, the notices pane) or while an editable holds focus. `reload`
itself never asks it: a deliberate gesture — retry, pull-to-refresh, a
locale change — must be honored even mid-edit. The check belongs to
the rebuilds nobody asked for, and those say **`App.refresh`**, which
composes it once:

```zig
fn onSaved(state: *State, result: Result) void {
    state.apply(result);                      // the state is written either way
    state.app.refresh(.{ .route = "note" });  // the screen follows, politely
}
```

`refresh` is "this state changed; update whatever is showing,
politely." If an open sheet owns the screen its builder runs again — a
sheet is a tree node a reload would take with it, so the state change
re-presents it instead, and the content behind it waits for the close,
which always rebuilds it — Esc, the scrim, the × and `closeSheet`
alike, so state written under a sheet lands the moment the sheet goes.
Otherwise it reloads, unless `reloadSafe` says the user holds something
a rebuild would take — then it declines, and declining is fine by
construction: the state is already written, and the next navigation or
gesture rebuilds from it. `Refresh.route` scopes the whole thing to a
screen: a reply that lands after the user has walked away leaves the
screen it no longer owns alone (`""`, the default, means whatever is on
top; the comparison is by route *name*, so `"note"` covers `note~42`).
Called from inside a builder — a load the builder issued, answered
synchronously — it declines quietly too: the builder reads the answered
state the line after. Every consumer
used to compose all of this by hand, per controller; the survey found
22 copies.

The things that are wrong to rebuild for — a status line's words, a
control's percentage, and whether a control is working at all, each
moving while work runs — are patched onto their node instead, and
decline on a stale id in the same spirit (`App.patchText` /
`App.patchProgress` / `App.patchBusy`; [elements.md](elements.md),
"Patching one node instead of rebuilding").

`reload` from inside a route builder is different: the deliberate verb
has no polite decline, so tearing down the half-built screen to run its
builder again — which would duplicate the screen — is **refused and
recorded** (`reload_in_build` below), and the audit fails the first
test that trips it.

### The back gesture

On iOS a drag inward from the leading screen edge also goes back — the
left edge, or the right under RTL chrome, mirrored like the Back
chevron. It is the framework's, not the app's: nothing to enable,
nothing to configure, and it reaches nothing the Back control does not.

**Nothing slides.** The finger moves and the screen does not, because a
half-transitioned screen is an intermediate state nokre cannot describe
to assistive tech or render byte-exactly, and finishing the slide after
the finger lifts would need frames nobody asked for. Instead there is a
*threshold*, a quarter of the viewport's width and never less than
64px: crossing it fires a haptic knock
and turns the Back control's chevron into an arrow, crossing back knocks
again and gives it up, and releasing past it pops the stack exactly as
tapping Back does. Position decides and only position — a fast flick short of the
threshold is not a back, because velocity needs a clock. The gesture is
inert at depth 1 and under an open sheet or picker, and it never arms in
either case: a knock that promises a navigation nothing will perform is
worse than no feedback at all. The design record is
[internals/haptics.md](internals/haptics.md).

Android has the same command by a different road: gesture navigation
owns both screen edges there, so the system's own back — predictive
animation, haptics and all — arrives already decided and nokre routes
it, popping one screen or finishing the activity at the root. On the web
the browser's Back does the same through the address bar. The other
three shells have no equivalent gesture, and their Back control is the
whole story.

**Crossing the nav is a push**, like every other move: the destination
goes on top of the screen you were looking at, which therefore still has
a way back to it — the framework's Back control, the iOS edge drag, the
Android system back, the browser's Back. Reaching a section by mistake
costs one press to undo, and reaching one deliberately does not silently
discard where you were. Activating the destination you are already
standing on is the one no-op: a screen stacked on itself would grow a
Back control leading to a screen indistinguishable from the one showing.

There is still no *per-section* history — one stack, not one per
destination, and coming back to a section arrives at its root rather
than at whatever you last had open there. A bottom nav is a set of
places and the stack is the order you walked them in; nokre keeps one
of those, not both. That is also why the nav can collapse to the current
section without losing anything ([elements.md](elements.md#navigation-chrome)):
a set has no order to show, so showing one member and keeping the rest a
press away costs nothing. The nav chrome and the framework-installed
Back control are [elements.md](elements.md#navigation-chrome)'s;
[getting-started.md](getting-started.md) Part 3 walks the whole thing.

The stack itself is memory and stays memory: `router.current()` names the
screen on top, `router.currentRef()` gives its full reference, and
`router.depth()` counts the stack.

## References

What a `link`, a route-carrying `tile`, a `nav_item`, a `notice`, a
Markdown `[label](destination)` span and `App.navigate` all carry is a
**reference**: a route name, optionally followed by positional arguments.

```
notes              a screen
note~42            the same route, a specific note
sum~10~5           two arguments, in order
```

Every one of them resolves through the same table, so a reference that
does not name a route is refused the same way wherever it appears.
Resolution is the only place that parses — the Markdown parser, the
elements, and the input layer all pass the reference through untouched.

**The arguments belong to the stack entry**, not to app state. That is
the point of having them: push `note~41`, push `note~42`, pop, and the
screen you land on still knows it is note 41. With the selection in app
state the depth is remembered and the identity is not.

Read them back inside the builder:

```zig
fn buildNote(state: *State, app: *h.App) !void {
    const id = app.routeArg(0) orelse return;   // "42"
    // ...
}
```

`routeArg` borrows from the entry, and the tree copies everything it is
given, so a builder may format a reference into a stack buffer and append
it — the same rule labels already follow.

### Building a reference

Writing one is `routeArg`'s mirror — `App.routeRef` (`router.writeRef`
underneath) formats a name and its arguments into a buffer you hand it,
validated against the same table `navigate` resolves through:

```zig
var buf: [h.router.max_ref_bytes]u8 = undefined;
const ref = try app.routeRef(&buf, "note", &.{id});   // "note~42"
try list.link(.{ .label = title, .route = ref });
```

Everything resolution would refuse is refused here, at the site that
*builds* the reference rather than the one that later opens it: an
unknown name, the wrong arity, an argument outside the charset — a `~`
inside an argument included, so content can never read as a second
separator — or a result past `max_ref_bytes`. A failed call writes
nothing. `[h.router.max_ref_bytes]u8` always fits, so there is no
buffer size to guess and no separator literal to hold; a reference this
returns is one `navigate` will take.

### A literal is refused at the build

A reference the source spells out — `navigate("key_export")`, a `tile`
whose route is written a few lines from the table it names — is a
programmer error that never has to reach a running program, because the
table is comptime data. `ComptimeRefs` binds one table and refuses
everything `routeRef` refuses, at compile time:

```zig
const routes = R.table(&.{ ... });
const ref = nokre.ComptimeRefs(&routes);

try app.navigate(ref.to("key_export"));
try list.tile(.{ .label = title, .route = ref.to("note~42") });
```

`ref.to` hands back the reference it was given, so nothing downstream
changes shape: `navigate`, `switchTo`, `replaceWith`, a `tile`'s or a
`link`'s `route` and a driver's `openRoute` all take the same
`[]const u8` they always did, and a reference built from data goes on
reaching them through `routeRef` / `refTo`, checked when it is built.

It is the same parse at both moments — one function, one grammar, no
second copy to keep in step — so a name nothing answers to, the wrong
number of arguments, a byte an argument may not contain or a result past
`max_ref_bytes` is a build error naming the reference and, where there is
one, the declaration it disagrees with:

```
nokre: reference "key_exprt" names no route in this table — there is no route "key_exprt"
nokre: reference "note" carries 0 argument(s); route "note" declares 1
```

### Arity is declared

`RouteDef.args` says how many arguments a screen takes, defaulting to
none. A reference carrying the wrong number is refused rather than
building a screen with nothing to show, so `#note` and `#note~1~2` both
fail where a missing id would otherwise render as a blank.

### The separator is `~`

Not `/`. A path puts the way you got here into the name of the screen. A
stack in the URL does the same, just more of it. Neither is kept, and
both leave the same thing behind: one screen, one reference. That is the
**no paths** refusal ([introduction.md](introduction.md)), and `~`
carries none of the conventions a slash does — nothing about a reference
is truncatable, so `note~42` cut back to `note` is a missing argument
rather than a parent.

It is also one of the few characters `encodeURIComponent` leaves alone
(the whole set is `. ! ~ * ' ( ) - _` and alphanumerics), so a reference
and its rendering in an address bar are the same bytes, always.

### Names are flat

Names are flat and unique, so two sections cannot both have a
`settings`. Give them different names. `settings.billing` is a name, and
the router never reads the dot as a level.

### Arguments are identifiers, not payloads

Names and arguments may contain `[a-zA-Z0-9_.-]`. `.` and `-` are in
deliberately — that is why they are not the separator — so versions,
UUIDs and slugs are arguments with no escaping:
`ticket~1.2.3-rc1` is fine.

Everything else is out. An argument says *which* thing a screen is
about; free text and structure are a URL's business, which is
`deep_link`'s ([services.md](services.md)).

**A reference must stay safe to open.** Arguments identify, they never
command: `#sum~10~5` is fine, `#delete~42` is not. Anything in an address
bar gets opened by link previewers, history restores, and people pasting,
none of which intended to act.

### Errors, and refusals

The table is validated once, in `App.init`, rather than leaving a bad
name to surface as a mystery at first navigation:

| | |
|---|---|
| `error.EmptyRouteName` | a route with no name |
| `error.RouteNameCharset` | a name outside `[a-zA-Z0-9_.-]` — including one carrying a `~`, which would make every reference to it ambiguous |
| `error.DuplicateRouteName` | two routes sharing a name — otherwise every reference would quietly resolve to the first |
| `error.NoUnresolvedDestination` | a table with routes and no not-found screen among them — the next section |

A reference is validated at resolution, and who hears about a bad one
depends on who asked. `navigate`, `switchTo` and `replaceWith` **vet
first and return an error** — the reference is the caller's own, so the
caller is who can fix it, and a driver that asked for a screen that
does not exist finds out at the call instead of at the next audit. The
error names the same refusal `routeRef` names (`error.UnknownRoute`,
`RouteArgCount`, `RouteArgCharset`, `RouteRefTooLong`); the stack does
not move and nothing is written down. A reference written as a literal
never reaches this at all — the build refuses it first — and in a
shipped app the not-found destination takes it instead of the error;
both are below.

An **activation** is the other caller, and it gets a **refusal, not an
error**: a tapped `tile`, `link` or notice reaches the router directly,
because a tap is three frames from the builder that wrote the
reference and has nothing to do about it. So does `reload`, for the one
thing it can refuse. Those leave the stack exactly as it was, return
normally, and record what they refused in `router.refused`: the
reference (bounded to `max_ref_bytes`) and a reason —

| | |
|---|---|
| `unknown_route` | no route by that name |
| `arg_count` | not the number of arguments the route declares |
| `arg_charset` | an argument outside the charset, or empty (a trailing `~` is a *missing* argument, not an empty one) |
| `ref_too_long` | past 256 bytes — a reference can arrive from outside the app, and one enormous argument would pass the arity check |
| `reload_in_build` | a `reload` issued while the screen's builder was already running — honoring it would rebuild the screen over its own half-built output, duplicating it. The record carries the reference of the screen being built. (`refresh` never trips this: the polite verb declines the same call quietly.) |

Every one of these is a programmer error, and nothing at an
*activation* can do about one but drop it — so that path raises no
error. The record is how the mistake still surfaces there: the test
harness checks it after every action (and audits every route a `link`,
`tile`, span or `notice` carries — the `unresolvable_route` rule), so a
mistyped reference fails the first test that shows or presses it, with
the reference in the diagnostic.

The same taxonomy is an error set on `App.routeRef` for the same reason
it is one on `navigate`: the caller is the site holding the reference
and can act on it.

### Where an unresolved reference lands

Some references genuinely arrive from data — a channel id read from a
reply, a row from a list that has since changed — and there "nothing
happened" is the wrong answer at both ends: the reader is left on the
screen they pressed from with nothing said, and the caller's `catch` has
nothing to do about it.

**Every app says where those go, and nokre refuses one that does not.**
It is said once, at the route that is its own not-found screen:

```zig
.{ .name = "not_found", .title = .{ .of_locale = notFoundTitle }, .for_unresolved = true, .build = buildNotFound },
```

From then on a reference that does not resolve **enters that screen**
instead of going nowhere: on `navigate`, `switchTo` and `replaceWith`,
which stop raising because the app has now said what to do with one; and
on `router.push`, `replace` and `switchTo`, which is the tapped tile or
link a reader actually meets. It enters under the destination's own
name — a reference that resolves to nothing is not a screen and never
joins the stack — and each motion keeps its own shape: a `switchTo` that
falls still resets the stack, a `replace` that falls still stays at the
depth it found.

**It is recorded as well**, exactly as before, and that is the load-
bearing half. `router.refused` is what the harness audit reads after
every action, so a dead reference goes on failing the first test that
produces one; without it, declaring a destination would turn every dead
reference into a passing run. A place for the *reader* to land is not an
excuse for the program. The not-found screen reads that same record for
what was asked for.

#### The declaration is required

`App.init` refuses a table with routes and no not-found screen among
them — `error.NoUnresolvedDestination`. "This app has no not-found
screen" is not a decision anyone should reach by leaving a field out,
and before this it was the default: a tap on a dead reference did
nothing at all, silently, and the app had said nothing about it either
way.

It is checked at `App.init` because a table is only whole there. Most
apps write theirs out in source, but one builds it from a page list, so
no compile-time rule could reach every table without leaving the most
dynamic app outside it. What a comptime table can still do is ask the
same question earlier and fail the build:

```zig
comptime if (nokre.missingUnresolvedDestination(&routes))
    @compileError("no route declares for_unresolved");
```

`missingUnresolvedDestination` is the rule itself, public and pure — the
one `App.init` asks, so the two cannot disagree.

Two tables are not asked for one, and both are the rule rather than
holes in it:

- **A table with no routes at all.** An app that cannot route holds no
  reference anything could tap, and `navigate` refuses every one it is
  handed with `UnknownRoute` already. Headless drivers are this.
- **A `zig test` binary.** The rule is about apps and a test table is
  not one: fixtures stand two routes up to ask a question about a
  chevron, and a not-found screen on each would be ceremony teaching
  that the declaration is boilerplate. Nothing is lost by it — a shipped
  artifact is never a test binary, on any of the six targets, so there
  is no app this exempts. A suite that wants the rule anyway asks
  `missingUnresolvedDestination` itself.

Both are why the raise from `navigate`, `switchTo` and `replaceWith`
is still live code and not a leftover: those are the tables that reach
it.

Two things it deliberately does not catch, and requiring it moves
neither. A `reload` issued inside its own builder is about the *moment*
rather than the reference, so it stays a recorded no-op — replacing a
screen that exists and is fine with one saying it does not is worse than
the refusal, and it is no less worse for the destination being
guaranteed. And `routeRef` / `refTo` go on raising: those *build* a
reference, and falling back there would write the not-found name into a
tile's route at the one site that could still fix it.

The router owns which route and when. **It never draws the screen.** Not
a word of it, in any language, is nokre's — it is a route in your table
like any other, with your title, your words, your layout. Exactly one
route declares it: a second is `error.DuplicateUnresolvedRoute` and none
is `error.NoUnresolvedDestination`. It must take no arguments
(`error.UnresolvedRouteArgs`), since a reference is refused *for* its
arguments as often as for its name and there is nothing safe to hand
one.

Being a route like any other, it is also reachable by its own name — a
tile pointing at it, a fragment naming it — and then nothing was
refused, so `router.refused` is null. A not-found screen reads it as an
optional, and says something without a reference to quote.

**Bytes from outside the program are different.** An address bar, a
deep-link fragment, a notification payload — a stranger's typo there is
not a programmer error, and it must not read as one. Ask first:

```zig
if (app.router.vet(route) == null) try app.navigate(route);
```

`vet` answers what a verb would refuse — same checks, same reasons —
and records nothing; it is also what `navigate` itself asks before it
enters, so the difference is only whether you want the reason or the
error. It never falls to the unresolved destination either, and an app
that wants a stranger's typo to land there says so itself, at the door
where it decided the bytes were worth honoring. The web shell already
vets the fragment at its own door, which is what keeps the bar restored
and the app unmoved.

## The address bar

On the **web**, the URL fragment names the screen the app is on, in both
directions and without configuration:

- navigating writes it — `#notes`, `#note~42`;
- typing one, opening a shared link, or pressing the browser's Back and
  Forward puts the app on it;
- a fragment the router cannot honor — an unknown name, the wrong number
  of arguments, a byte an argument may not contain — leaves the app where
  it is and puts the bar back, so the bar never describes a screen nobody
  is on.

The fragment is a reference, unencoded: every byte a name or argument may
contain is one `encodeURIComponent` leaves alone, so what the app writes
is what a user copies and what comes back.

**The fragment is the current screen, never the stack.** A reference is
an identity for a screen: one screen, one URL, whoever is looking and
however they got there. Encoding the stack would break exactly that —
`note~42` would be reachable as `notes/note~42`, `settings/note~42`, or
`note~42`, three strings for one screen, none of them a stable link. The
trail that led to a screen is the app's own memory, and the browser
already keeps a history of its own; nokre does not keep a second one in
the URL.

So arriving by link **resets the stack** to that one screen — `switchTo`,
not `push`. A visitor has nothing to go back to inside the app, and the
framework's Back control is correctly absent; the browser's Back takes
them where they actually came from.

The corollary, stated plainly: **depth does not survive the URL.**
Reloading two screens deep comes back one screen deep, without the Back
control, and so does walking browser Back and then Forward — Forward is
an arrival like any other. That is the trade for a URL that means one
thing, and it is the same trade every web app makes.

Browser Back and the in-app Back control are otherwise the same motion,
deliberately. A pushed screen adds a history entry and nothing else does
— a section switch and a `replace` are the router saying *this is the
same place*, so they replace the entry rather than stacking one. In-app
Back rewinds only history this app added: opening a link straight into a
pushed screen and pressing Back moves up a screen instead of leaving the
site.

On **every other platform** nothing is rendered, because a native window
has no address bar — the router announces each change either way, and
those shells simply do not listen. Nothing to enable, nothing to turn
off, no platform branching in app code. The wiring is
[internals/platform-shells.md](internals/platform-shells.md).

**Not to be confused with `deep_link`** ([services.md](services.md)),
which delivers an inbound URL it deliberately does not interpret and
leaves routing to the app. The two answer different questions — *a URL
arrived* versus *which screen is showing*. A reference reaches as far as
identifiers reach; a link carrying free text, a query, a path, or a
claimed domain is a real URL, and that is `deep_link`'s. An app that both
links `deep_link` and routes on the fragment itself will see the fragment
twice, once through its handler and once through the mirror; route on one
or the other.
