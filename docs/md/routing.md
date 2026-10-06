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
this is sugar over the raw form, the way the builder cursor is sugar
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
| `App.refresh(opts)` | the *polite* one: the open sheet rebuilt if one owns the screen, else a reload — deferred, never dropped, if the user holds something a rebuild would take |

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

**The caret rides with the focus.** A field that is re-found by name
gets its byte offset back, vetted against the value the rebuild
produced (clamped, and never into the middle of a codepoint), because
focus alone would put the keyboard back in the field with the caret at
zero — worse than not rebuilding at all. The *value* needs no carry:
`on_change` fires on every keystroke and the builder writes the field
from state, which is what makes the rebuilt field the same field.

What no carry can save is a **live IME pre-edit** — those bytes are the
platform's, uncommitted, and no builder can put them back.
`app.reloadSafe()` is that question asked before the fact: false while
an overlay owns the screen (a sheet, a picker, the notices pane) or
while a composition is in flight, and **true for a field that is merely
focused**. `reload` itself never asks it: a deliberate gesture — retry,
pull-to-refresh, a locale change — must be honored even mid-edit. The
check belongs to the rebuilds nobody asked for, and those say
**`App.refresh`**, which composes it once:

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
a rebuild would take — and then it is **owed, not dropped**: the
request is held and re-tried at the tail of the next input, which is
where all three refusals end (focus leaving a field, an overlay
closing, an IME committing). Dropping it was a real defect and the
reason this is written down: "the next gesture rebuilds from the state"
is not a promise the framework can keep, because a submit-on-Enter
leaves focus in the field it was typed into and no later keystroke ever
lets go of it — the screen stood on state that had changed, forever.
`Refresh.route` scopes the whole thing to a
screen, at the request and at the drain alike: a reply that lands after
the user has walked away leaves the screen it no longer owns alone
(`""`, the default, means whatever is on
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

### A screen declares its shape

`RouteDef.shape` says how a screen is arranged, and what follows from it
is how wide it is, what may stand on it, and what a window too small for
it does:

```zig
.{ .name = "console",  .title = .{ .fixed = "Console" }, .shape = .desk, .build = buildConsole },
.{ .name = "settings", .title = .{ .fixed = "Settings" }, .build = buildSettings },
```

- `page` — the default. Content flows in a column capped at the prose
  measure and centred in what is left. Every screen this library drew
  before the field existed is one, which is why saying nothing says
  `page` and most tables never write the word.
- `desk` — an application shell: a console, a mail client, an IDE.
  Content takes the window, because a console is not prose and a measure
  argued from line length has nothing to say about one. A desk's root
  holds `region` children and nothing else — the roster, the subject,
  the aside, the strip you act from ([elements.md](elements.md)) — and a
  window too narrow to stand them side by side shows one at a time
  behind a control that names the rest.

**It is not a width knob**, and the difference is not a technicality. A
knob asks how wide you want this screen; this asks what the screen *is*,
which you already decided, and nokre derives the width from the answer.
So a desk and a settings page live in one table without either arguing
for a number, and two screens in one app cannot disagree about how wide
reading is. There is no `App` call, no element field and no build option.

**A shape is a set of answers, not a style.** A member joins only by
answering one of five questions differently — how wide the content is,
how many things scroll, whether any edge is pinned, what a shrinking
window does, and what order Tab walks it in. That test refused a
long-document `reader` and a `glance`, both of which answer all five
exactly as `page` does.

**A resize is not a rebuild.** `App.setViewport` lays out again, folds or
unfolds a desk's band, and never calls a builder — so the shape a route
declared is the shape it keeps while a window moves, and so is every
region's scroll position. It is also why a builder must not read
`app.viewport` to decide anything: that number changes under a screen
that will not be rebuilt, and width, wrap and fold are nokre's answers
anyway.

### The region a desk shows

A window too narrow for a desk's band shows one region at a time, and
**which one is the screen's reference's**. A desk route's reference
carries nokre's region segment first after the route name, before the
app's own arguments:

```
console~c6~history          main, the segment absent
console~aside~c6~history    the aside
```

The names are the band regions' — `roster`, `main`, `aside`; the
masthead and the composer stand on every region a narrow desk shows,
so neither is one a reference names. A page route carries none.

**The segment is nokre's.** The app declares nothing, writes nothing
and reads its arguments as before: `routeArg(0)` is `c6` in both
references above, and `routeRef` and `refTo` write the app's own
arguments only. nokre writes the segment, reads it on every rebuild
and navigation, and the shown region follows.

**The reference names the region the reader is working in.** Two
things write it, each by replacing the screen's reference with the
same one naming that region — a replace, so it never joins Back's
history, and nothing is rebuilt, since no builder reads it:

- **the switcher's touch**, naming the chosen region;
- **every input landing in a band region** — a press, a hold, a
  drag, a scroll where it starts, a key or a keystroke on the focused
  control — naming that region before the input does anything else; a
  reader's hand in a region is the reader working in it. A control in
  the composer names `main`, which it travels with; the masthead names
  nothing, and neither does the back gesture. This holds at every
  width: on a desktop standing every region side by side only the
  address moves, so a recording made wide carries the references a
  phone's run would.

A navigation — `navigate`, `replaceWith` or `switchTo` — whose
reference names no region opens on the region shown, so one an action
makes opens on the region that action was made in. The console's pane
picker stands in the aside and replaces `console~c6~billing` with
`console~c6~history`; the screen entered is
`console~aside~c6~history`, and the reader is still looking at the
pane they chose. Otherwise:

- **a tapped `tile`, `link` or span** enters its reference as the app
  wrote it: a destination the app named, opening on `main`, which is
  why a roster's row opens the conversation it names;
- **Back** shows the region the screen it returns to names, since its
  reference is what the stack kept; a reload keeps the region its
  reference names.

A desktop ignores the segment for what it shows, so a link made on a
desktop opens a phone where it was made. The address carries it as one
more segment in either form,
`/console/aside/c6/history` or `#console~aside~c6~history`, and an
address naming no region opens on `main`.

An expectation (`expectRoute`, `untilRoute`) written without the
segment holds in any region, because the region is nokre's; written
with one, it holds only there.

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

What a `link`, a route-carrying `tile` or `button`, a `nav_item`, a
`notice`, a Markdown `[label](destination)` span and `App.navigate` all carry is a
**reference**: a route name, optionally followed by positional arguments
— and, on a desk, nokre's region segment between the two
([The region a desk shows](#the-region-a-desk-shows)).

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
nothing. `[h.router.max_ref_bytes]u8` always fits — it is this app's own
declared cap ([The cap is declared](#the-cap-is-declared)) — so there is
no buffer size to guess and no separator literal to hold; a reference
this returns is one `navigate` will take.

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
building a screen with nothing to show, so `note` and `note~1~2` both
fail where a missing id would otherwise render as a blank.

#### An optional trailing argument is refused

Asked for by the first consumer, for a screen that opens as `ballot~<id>`
when the server holds a ballot's words and as `ballot~<id>~<content>`
when the link carries them. Refused, on three grounds that are all
already on this page:

- **One screen, one reference.** An optional argument gives one route
  two spellings, and the address bar's contract is one screen, one URL.
- **Nothing about a reference is truncatable.** A link cut back at a
  `~` — by a messenger, by a paste — is a missing argument and is
  refused. With the argument optional the cut-back link *resolves*, and
  opens the one screen that has nothing to show: a sealed ballot without
  its words. That is the blank the arity rule exists to prevent, moved
  to the one link long enough to be cut.
- **Dropping an argument is already a verb, at one door, and it
  reports.** `switchToNearest` answers `.trimmed` when it lands on fewer
  arguments than it was handed
  ([Handing off from the other app](#handing-off-from-the-other-app)).
  An optional argument makes the same bytes `.exact` at every door.

What the consumer wanted is already expressible, and says more: **a
screen that comes in two arities is two routes over one builder.**

```zig
.{ .name = "ballot", .title = title, .args = 1, .build = buildBallot },
.{ .name = "sealed_ballot", .title = title, .args = 2, .build = buildBallot },

// in buildBallot — null on the route that declares one:
const content = app.routeArg(1);
```

The name now states which kind of link it is, `sealed_ballot~<id>` is
refused at every door including the compiler's, and packing two values
into one argument behind a private separator — the workaround this
replaces — is no longer needed to stay inside a fixed arity.
`router_test.zig`'s "a screen that comes in two arities is two routes
over one builder, and the cut-back reference is refused" is the claim
against a real router.

The one argument that *may* be missing is a secret one, and it is
missing for a different reason: nokre took it out.

#### Secret arguments

Some arguments must not rest where an address is kept — the key that
opens a sealed ballot, an invitation's token. The address bar is read
over a shoulder, the browser's history is written to disk for session
restore, and a server logs every path it serves. A route says how many
of its arguments are secret, and they are always the **last** ones:

```zig
.{ .name = "ballot", .title = title, .args = 2, .secret_args = 1, .build = buildBallot },

// in buildBallot:
const key = app.routeArg(1) orelse return showMissingKey(app);
```

Trailing and counted, so an address is always its public part and then
its secret part, and there is no per-argument flag to get out of step. A
count past `args` is `error.RouteSecretArgCount` at `App.init`.

From there nokre keeps them out of every place an address is kept
([The address](#the-address)): the path form writes them into the
fragment, which no request carries; the bar and every history entry
drop them; an `href` in the page drops them; every reference nokre
prints or records has them redacted. The app still has them — a tapped
tile enters the reference the tree holds, secrets and all, and
`currentRef` and the route observer hand the app its own reference
whole.

So a screen with secrets can be **arrived at without them**, and that is
an arrival, not a refusal: a reload, a Back after a reload, a link a
messenger cut. `routeArg` answers null for each secret that did not
come, and the screen says what it needs. A reference carries all the
secrets or none of them — a partial set is a cut in the middle of one,
and is `arg_count`. The public arguments stay required, exactly as the
section above has it: a secret is not a second optional argument to
append to.

### The separator is `~`

Inside a reference, not `/`. A path puts the way you got here into the
name of the screen, and nothing about a reference is truncatable, so
`note~42` cut back to `note` is a missing argument rather than a parent.
That is the **no paths** refusal ([introduction.md](introduction.md)),
and it is about the *reference*: the address a URL shows may spell the
same screen `/note/42` ([The address](#the-address)), and the path there
is still a name and never a parent.

`~` is also one of the few characters `encodeURIComponent` leaves alone
(the whole set is `. ! ~ * ' ( ) - _` and alphanumerics), which is what
lets the fragment form carry a reference as the same bytes.

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
about, and free text is not a screen's name.

**`.` and `..` alone are out too**, as an argument and as a route name.
A URL's path reads them as "this segment" and "the one above", and a
browser removes them before anything can read the address, so the path
form could not carry one — and a reference that is legal in one form
and not the other would be two grammars. Nothing else in the charset
needs anything in a path: no byte in it is ever percent-encoded, and a
`%` is outside it, so an address arrives as the reference's own bytes or
is refused.

**A reference must stay safe to open.** Arguments identify, they never
command: `sum~10~5` is fine, `delete~42` is not. Anything in an address
bar gets opened by link previewers, history restores, and people pasting,
none of which intended to act.

### The cap is declared

A reference is bounded — `router.max_ref_bytes`, 256 by default — because
one can arrive from outside the app and an enormous argument would pass
the arity check with nothing else to stop it. The bound is on the *copy*:
each stack entry owns the reference it was entered with, and so do the
refusal record, an owed refresh, a held nav focus, every stored notice's
route and every scheduled notification's.

**256 is a fact about the shape of a reference, not a budget for your
links**, so it is stated per app rather than fixed by the library:

```zig
const app = nokre.addApp(nokre_dep, .{
    .name = "votes",
    .route_reference_max_bytes = 8192,
    // ...
});
```

A dev-store driver states it too. `addDevStoreDriver` mints its own
nokre module rather than being handed `app.nokre`, so the app's number
does not reach it, and a driver that says nothing compiles the app's
screens against 256 — its journey then meets `error.RouteRefTooLong` on
a link the shipped app opens. `DevStoreDriverOptions` carries the field
under the same name for that reason; hoist the number into a const the
way `pkg` is hoisted and hand the one const to both calls
([getting-started.md](getting-started.md#the-fourth-artifact-a-driver)).
A driver built by `addDriver` is handed `app.nokre` and has nothing to
state.

Within one module everything above derives from that one number, so
nothing can disagree with it — there is no second cap to move, and no door that admits a
reference another one would truncate. What it costs is the copies:
raising it raises the inline storage of every notice slot and every
scheduled notification too, which is why it is a declaration and not a
default. The ceiling is 65535, where the length beside those copies stops
fitting in a `u16`, and 0 is refused.

**The charset does not move with it.** An argument stays
`[a-zA-Z0-9_.-]` at any size, so what a larger cap admits is a longer
*identifier* — base64url is inside that set, which is what lets a link
carry a sealed document's own bytes — and never free text. The rule above
this one still holds: a reference identifies, it never commands.

### Which argument pushes

`App.navigate` and every activation that carries a reference — a tapped
`tile`, a `link`, an inline span — enter the reference the way the
reference itself says to. **A reference naming a different place pushes;
one naming a different view of the place you are standing in replaces.**

The place is the route name and the **first** argument, and nothing
past it. So `console~c1~billing` and `console~c1~notes` are two tabs of
one contact, and pressing the second replaces the first; `console~c1`
and `console~c2` are two contacts, and pressing the second pushes.
Re-entering the screen you are already on replaces it, which is why a
back stack does not grow a rung every time a reader flips between two
tabs of one record. A desk's region segment is no part of the place:
which region shows is a view of it.

The comparison lives in `Router.follow`, once, because a tapped tile is
three frames from the builder that wrote its reference and no app should
be writing this test. `router.push` and `router.replace` stay as the
verbs for a caller that knows better: the nav's crossing and a notice's
deep link are arrivals rather than refinements, and both keep `push`.

### Errors, and refusals

The table is validated once, in `App.init`, rather than leaving a bad
name to surface as a mystery at first navigation:

| | |
|---|---|
| `error.EmptyRouteName` | a route with no name |
| `error.RouteNameCharset` | a name outside `[a-zA-Z0-9_.-]` — including one carrying a `~`, which would make every reference to it ambiguous, and `.` or `..`, which no path can carry |
| `error.DuplicateRouteName` | two routes sharing a name — otherwise every reference would quietly resolve to the first |
| `error.RouteSecretArgCount` | a route declaring more secret arguments than arguments ([Secret arguments](#secret-arguments)) |
| `error.NoUnresolvedDestination` | a table with routes and no not-found screen among them — the next section |

A reference is validated at resolution, and who hears about a bad one
depends on who asked. `navigate`, `switchTo` and `replaceWith` **vet
first and return an error** — the reference is the caller's own, so the
caller is who can fix it, and a driver that asked for a screen that
does not exist finds out at the call instead of at the next audit. The
error names the same refusal `routeRef` names (`error.UnknownRoute`,
`RouteArgCount`, `RouteArgCharset`, `RouteRefTooLong`, and
`UnknownRegion` for a region segment nothing names); the stack does
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
reference (bounded to `max_ref_bytes`, with its secret arguments
redacted to `*`) and a reason —

| | |
|---|---|
| `unknown_route` | no route by that name |
| `arg_count` | not the number of arguments the route declares — or, for a route with secret ones, not that number and not its public part alone |
| `arg_charset` | an argument outside the charset, or empty (a trailing `~` is a *missing* argument, not an empty one) |
| `ref_too_long` | past `max_ref_bytes` — 256 unless this app declared otherwise (above) — because a reference can arrive from outside the app, and one enormous argument would pass the arity check |
| `unknown_region` | a desk reference one argument longer than its route declares, whose region segment names none of `roster`, `main`, `aside` |
| `reload_in_build` | a `reload` issued while the screen's builder was already running — honoring it would rebuild the screen over its own half-built output, duplicating it. The record carries the reference of the screen being built. (`refresh` never trips this: the polite verb declines the same call quietly.) |

Every one of these is a programmer error, and nothing at an
*activation* can do about one but drop it — so that path raises no
error. The record is how the mistake still surfaces there: the test
harness checks it after every action (and audits every route a `link`,
`tile`, `button`, span or `notice` carries — the `unresolvable_route` rule), so a
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

**Asked for, and declined: stop failing on a refusal that landed on the
declared destination.** It would read as the app's own answer rather
than a mistake, and it is not one the record can tell apart — a dead
reference an action computed lands there by exactly the same road as a
stale link. Declaring a destination is mandatory, so the exemption would
be every app's, and the whole control would be gone: the per-node route
rules hold the references *in the tree*, and nothing else watches an
imperative `navigate`.

What was true is that the one screen every app must have was the one
screen no test could stand on. `HarnessApp.expectNavigationRefused(ref,
reason)` is the door — it names the refusal, asserts both halves and
takes the record with it, so the not-found screen audits and
photographs like any other and **every refusal nobody names goes on
failing**. The navigation stays the app's own verb (`harness.app.navigate`,
`switchTo`), because it is the app being asked for something it cannot
give. A not-found screen that reads nothing off the record has a second
route in with no refusal at all: its own name resolves, since
`for_unresolved` forces `args = 0`.

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
tile pointing at it, an address naming it — and then nothing was
refused, so `router.refused` is null. A not-found screen reads it as an
optional, and says something without a reference to quote.

**Bytes from outside the program are different.** An address bar, a
deep link, a notification payload — a stranger's typo there is not a
programmer error, and it must not read as one. Ask first:

```zig
if (app.router.vet(route) == null) try app.navigate(route);
```

`vet` answers what a verb would refuse — same checks, same reasons —
and records nothing; it is also what `navigate` itself asks before it
enters, so the difference is only whether you want the reason or the
error. It never falls to the unresolved destination either, and an app
that wants a stranger's typo to land there says so itself, at the door
where it decided the bytes were worth honoring. An address — the bar,
a deep link — is vetted at nokre's own door and never reaches your code
at all ([The address](#the-address)).

## Handing off from the other app

One package may hold several apps, split on the dwell line — a sitting
app and a glance app sharing state, actions, services and every catalog
key, but not their route tables
([getting-started.md](getting-started.md), "Several apps in one
package"). A reference written by one of them can arrive at the other
in a notification payload the glance app scheduled.

Crossing that line is a **page load or a process launch, never a
function call**: two apps of a package are two artifacts, and no `App`
in this library ever calls another. So the whole of handoff is one verb
on the app that receives the bytes:

```zig
.opened => |p| _ = state.app.switchToNearest(p.route) catch {},
```

The correspondence between the two tables is the **route name**, never a
second mapping table to hold and get positionally wrong. If both apps
name a screen `contact`, `contact~42` transfers as it stands. From there
`switchToNearest` climbs down a ladder and reports which rung it landed
on:

| `Arrival` | What happened |
| --- | --- |
| `exact` | this app names that screen and takes those arguments |
| `trimmed` | it names the screen with fewer arguments, and that is where the reader now is |
| `unmoved` | it has no screen of that name at any arity — **nothing happened** |

Arguments drop from the **right**, one at a time, because arguments
narrow left to right: `console~contact42~billing` is a console, then a
contact in it, then a tab of that contact, so dropping from the right
drops detail rather than subject.

**The last rung is nothing, not home, and not the not-found screen.**
nokre has no home declaration and this does not add one; and a screen
this app was authored *without* is not a not-found, so landing on
`for_unresolved` would be the wrong answer twice over. The caller is
told which rung landed and is the one that can say something about it.

**It vets every rung and enters only one that resolved**, so it never
writes the refusal record — which is exactly why it exists rather than
being spelled at each call site. `switchTo` on a name this table does
not carry lands on the unresolved destination *and* records, and the
audit fails the test that trips one: right for a programmer's dead
reference, wrong here, where a screen the other dwell has and this one
does not is the design working.

The doors that keep their old verbs keep them for reasons that survive
this: the site manifest's boot route is nokre's own and a wrong one must
fail the boot loudly, and an address — the bar, and every link into the
app — is one screen, one URL, entered exactly or refused, so landing
silently on a trimmed screen would break it ([The address](#the-address)).

## The address

Where a URL names a screen — the web's address bar, a link shared into
a message, a Universal Link or an App Link — the reference is written as
an **address**, in one of two forms the app declares once, beside its
other build declarations:

```zig
const app = nokre.addApp(nokre_dep, .{
    .name = "votes",
    .address_form = .fragment,   // leave it out for .path, the default
    // ...
});
```

| | `ballot~b7~key`, whose last argument is secret | the first route, `home` |
|---|---|---|
| `.path` | `/ballot/b7#key` | `/` |
| `.fragment` | `#ballot~b7~key` | `#home` |

**The path form is the default** because it is the address a reader, a
crawler and a link preview all expect. Its public part is the path and
its secrets are the fragment, the one part of a URL no request carries.
The first route of the table, when it takes no arguments, is the front
door, `/`. When a page loads at `/`, though, the front is whatever
screen your build left standing: an app whose first route is a splash
that restores the session and moves on to `sign_in` at build stays on
`sign_in`, rather than being sent back to a splash with nothing left to
move it. Only the page load yields this way; `/` arriving later — Back
after a reload, a link — enters the first route, and `/boot` typed out
always does. **The fragment form** is the hash router: the whole reference
in the fragment, secrets last — for a host that cannot answer every
path with the app's page, and for an app served below the root of its
origin, which the path form does not support.

There is no third form, no per-route template and no hook. nokre writes
the address and nokre reads it, in both directions and on every
platform, so your code never holds a URL string: a link you need to
hand someone is `App.routeLink`, and an address that arrives is entered
before your code sees it.

### Reading an address

An address is parsed in one place (`core/address.zig`) and **nothing is
guessed**. In the path form the path must carry exactly the route's
public arguments and the fragment all of its secrets or none, so a
secret written into the path is one segment too many and is refused as
`arg_count` — never read as the secret it probably was. A trailing slash
is an empty argument; a query is not part of an address and is ignored,
because a messenger or a campaign may add one to any link. An address
that names no screen leaves the app where it is.

### The address bar

On the **web**, the bar names the screen the app is on, in both
directions and without configuration:

- navigating writes it — `/notes`, `/note/42`;
- typing one, opening a shared link, or pressing the browser's Back and
  Forward puts the app on it;
- an address that names no screen leaves the app where it is and puts
  the bar back, so the bar never describes a screen nobody is on.

**Secrets never rest in the bar or in history**, in either form. After
the driver reads an arriving address it replaces the entry with the
address minus its secrets; a screen pushed with secrets is pushed
without them; and the entry's `history.state` holds a key and nothing
else, because a browser writes state to disk too. Within one page's
life the driver keeps each entry's whole reference in memory, so Back
and Forward bring a screen back *with* its secrets. After a reload that
memory is gone, the entry is read as the address it shows, and the
screen is entered without them — the legal arrival
[Secret arguments](#secret-arguments) describes.

**The address is the current screen, never the stack.** A reference is
an identity for a screen: one screen, one URL, whoever is looking and
however they got there. Encoding the stack would break exactly that —
three trails to one note would be three strings, none of them a stable
link. The trail that led to a screen is the app's own memory, and the
browser already keeps a history of its own; nokre does not keep a
second one in the URL.

So arriving by address **resets the stack** to that one screen —
`switchTo`, not `push`. A visitor has nothing to go back to inside the
app, and the framework's Back control is correctly absent; the browser's
Back takes them where they actually came from.

The corollary, stated plainly: **depth does not survive a reload.**
Reloading two screens deep comes back one screen deep, without the Back
control. Within a page's life Back and Forward walk the entries the app
wrote, and each one is entered as the screen it was — also at depth one,
since history, not the stack, is what the browser is walking.

Browser Back and the in-app Back control are otherwise the same motion,
deliberately. A pushed screen adds a history entry and nothing else does
— a section switch and a `replace` are the router saying *this is the
same place*, so they replace the entry rather than stacking one. In-app
Back rewinds only history this app added: opening a link straight into a
pushed screen and pressing Back moves up a screen instead of leaving the
site.

### Hosting the path form

A path-form address is a screen, not a file, so the host owes the site
**one rewrite: every GET for a path that names no file in the site is
answered with the site's `index.html`**, status 200. That page is the
fallback page — there is no second file — and the build makes it work
at any depth: it names every file it loads from the site root
(`/style.css`, `/boot.js`), because a page served at `/ballot/b7` would
otherwise ask for `/ballot/style.css`, and a `<base>` is refused by the
page's own `base-uri 'none'`. nokre's own `serve` step applies the same
rewrite, so a developer's browser meets the site a reader's will.

What "names a file in the site" means is stated as data: the site's
`site.manifest` lists every file the build wrote, one path per line
([internals/dom-substrate.md](internals/dom-substrate.md#the-unit-is-the-site-and-there-is-one-assembler)
lists it). A host that decides by that list needs nothing more. A host
that decides by directory instead must pass through every directory
the manifest holds, not only `fonts/`: lamp's frost grain lives in
`lamp-grain/`, and a directory it does not know is answered with the
page, which is the one file the site must never hand back for an image.

The fragment form needs nothing: every address is the page itself, the
page names its files relative to itself, and the site works below the
root of its origin. That is also the one thing the path form cannot do
yet — nothing in the build knows a sub-path, so an app served under one
declares the fragment form.

### Links into the app

On every platform an inbound link — a Universal Link, an App Link, a
custom-scheme open — arrives as the whole URL, and the address in it is
read by the same parser the web's bar goes through and entered the same
way ([services.md](services.md), deep_link). There is no handler to
write: a link is an address, and addresses are nokre's. A link carrying
a route's secrets opens the screen whole; nothing on a native platform
keeps an address, so there is nothing to strip.

A link you want to hand someone is written the same way, never
concatenated:

```zig
const link = try app.routeLink(gpa, "ballot", &.{ id, key });
defer gpa.free(link);   // https://votes.example.com/ballot/b7#a2V5
```

The link starts at the origin the app already declared for its web
build — `.web_origin = "https://votes.example.com"` beside
`.address_form` — and the rest is the address in the app's declared
form, **secrets kept**, because this is the one link meant to carry
them. The origin is scheme and authority and nothing after, and one
with a path, a query, a fragment or a trailing slash fails the build
that declared it. An app that declared no origin has no address to hand
anyone, so `routeLink` does not compile in it. The reference is vetted
as `routeRef` vets it, with the same errors.

### Links into another app

Apps of one family link to each other's screens — a room offering "open
this in the other app". The link is written by the same writer, and
the app states only what that writer needs and cannot see: the other
app's route table is source in another build, so its builders and
titles never reach this one. Declare each app this one links into, and
each route of it this one links to:

```zig
.links_into = &.{.{
    .name = "votes",
    .web_origin = votes_origin,   // its own .web_origin
    .address_form = .path,        // its own .address_form
    .routes = &.{
        .{ .name = "ballot", .args = 2, .secret_args = 1 },
        .{ .name = "publications" },
    },
}},
```

```zig
const link = try app.routeLinkInto(gpa, .votes, "ballot", &.{ id, key });
defer gpa.free(link);   // https://votes.example.com/ballot/b7#a2V5
```

The origin and the form are the other app's own declarations. Where
both apps are built in one build graph, read them off its `AppOptions`
— `.web_origin = votes_decl.web_origin` — rather than typing them a
second time; each route's counts are its `RouteDef`'s. `.votes` is a
member of `nokre.declared.LinkedAppName` exactly when it is declared, so
a link into an app this one never named does not compile. The rest is
`routeLink`'s: the route and its arguments are vetted against what was
declared, with the same errors, and a secret argument rides the
fragment. A route link into another app's first route names it
(`/publications`, never `/`); every app reads that back as the screen
`/` is. The build refuses, by name, an origin of the wrong shape, an app
named twice or by something that is not an identifier, an app at this
app's own origin (that link is `routeLink`), a route named outside the
charset or twice, and more secret arguments than arguments.

The link to another app's **front door** is `App.frontDoorInto`, and it
names no route: it is the app's origin and `/`, in either form. In the
path form `/` is the front door; in the fragment form the empty
fragment names no screen, so a page loaded there opens on the front its
build left standing, while a running app handed it by a deep link stays
where it is. An entry declared with **no routes** is door-only: the
build accepts it, `frontDoorInto` is the one link into it, every route
named on it through `routeLinkInto` is `error.UnknownRoute` as any
undeclared route is, and it may still take the app's mark. A company's
site that links to each product's front door declares each of them so:

```zig
.links_into = &.{
    .{ .name = "votes", .web_origin = votes_origin, .address_form = .path, .routes = &.{} },
    .{ .name = "teams", .web_origin = teams_origin, .address_form = .fragment, .routes = &.{} },
},
```

```zig
const door = try app.frontDoorInto(gpa, .votes);
defer gpa.free(door);   // https://votes.example.com/
```

If this app draws the other app's mark, the entry also takes the mark
that app's package offers
([services.md](services.md#the-mark-is-declared)):
`.offered_mark = votes_dep.namedLazyPath("offered_mark")`. Then
`.votes` is a member of `nokre.declared.MarkedApp` as well, and
`app_mark` draws it ([elements.md](elements.md#app_mark)). An entry
without it links as before and names no mark; an app named `own` that
offers one is refused, since `.own` is this app's own mark.
A sibling built in the same repository is not a dependency of an app it
links back into, so its offer is made with `nokre.offerMark` from the
registry both builds read, and goes in the same field
([services.md](services.md#the-mark-is-declared)).

An app in a store offers its store badges the same way, with the
address, the files and their words:
`.offered_store_badges = votes_dep.namedLazyPath("offered_store_badges")`.
Then `.votes` is a member of `nokre.declared.BadgedApp`, and
`store_badge` shows votes' badge and goes to votes' page in that store
([elements.md](elements.md#a-linked-apps-badges)). An app named `own`
that offers badges is refused, for the mark's reason.

Every app this one links into, as one group of rows each opening that
app's front door, is `Cursor.linkedApps`
([elements.md](elements.md#the-family)).
