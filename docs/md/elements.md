# Elements

The complete, closed set. Every element carries its semantics with it —
role, label, and state are intrinsic, which is why accessibility can be
derived rather than annotated. Layout metrics live in
[src/core/layout.zig](../src/core/layout.zig) (`metrics`).

There is no styling API. If an element doesn't do what you want, the answer
is a different composition of these elements, not a customization hook.

## Building with the cursor

Screens are written through the builder **cursor** — `app.root()`
hands one back, standing at the tree root. One method per element,
closed exactly as the element set is: a leaf method takes its element
struct (`b.button(.{ .label = … })`) or, for the content-only elements,
the content itself (`b.text(…)`, `b.heading(.h2, …)`,
`b.codeBlock(…)`; a styled or spanned paragraph is `b.styled(content,
style)` / `b.spanned(&.{…})`). A container method returns the child
cursor, so nesting is the return value:

```zig
const b = app.root();
try b.heading(.h2, "Unread");
const row = try b.stack(.{ .axis = .horizontal });
try row.button(.{ .label = "Refresh", .on_press = .bind(State.refresh, state) });
```

Every method **is** a `tree.append` call — same validation, same string
copy, same contrast gates; there is no second truth about the tree. The
raw `Tree` API stays public underneath, and is the form for what
the cursor does not carry: a spanned *heading*, and a leaf's `NodeId`
outside the four twins below (`tree.appendId(b.at, …)` — a container's
own id is `b.at`). A sheet builder starts from
`app.at(try app.presentSheet(title))`, the cursor standing on the node
the framework handed back.

### Patching one node instead of rebuilding

Most screens are rebuilt from state: `app.reload()` for a gesture the
user made, `app.refresh(.{})` for a reply that landed (see
[routing.md](routing.md)). Two things are wrong to rebuild for, because
they move *while* work is running and the screen underneath is being
read, scrolled, or typed into — a status line's words, and a control's
percentage. For those, hold the node and patch it:

```zig
// in the builder — the leaf methods that hand their node back:
state.status_id = try b.textId(state.statusCopy());
state.button_id = try b.buttonId(.{ .label = tr(.exportKeys), .on_press = … });

// in the callback, with the user mid-form:
app.patchText(state.status_id, state.statusCopy());
app.patchProgress(state.button_id, percent);
app.patchBusy(state.button_id, false); // …and when the work ends
```

`textId`, `styledId`, `buttonId` and `meterId` are the four leaves that
hand back a `NodeId` — the ones real screens address again, not one per
element. `patchText` replaces a text-bearing node's content;
`patchProgress` takes 0–100 and moves either a `button`'s
`progress_percent` (setting `in_progress` with it, since that pair is
one state) or a `meter`'s `value` as that fraction of its own `max`.
`patchBusy` is the verb for work that cannot say how far along it is:
a percentage has no way to spell *not running*, because 0 is where the
work starts rather than where it is absent. It answers on the three
elements that carry `in_progress` — `button`, `toggle`, `checkbox` —
and turning it off takes any `progress_percent` with it, since that
pair is one state. It refuses no button form: a percentage is refused
on the 24px glyph and the vendor sign-in pill because neither has room
for a track, and the hourglass needs none. All three mark the frame, so the
`invalidate()` that used to follow every one of these is gone.

**All three decline on a stale id, silently.** A recorded id outlives its
node by construction — every rebuild frees the tree it named — so a
reply arriving one frame late is the ordinary case, not a programmer
error, and the state it wanted on screen is already there: the rebuild
put it there. Nothing reports, for the same reason `refresh` reports
nothing. A patch also cannot get a value past a gate `append` would
have refused (a percentage on a glyph or vendor button, a number over
100); those decline too.

### The load gate

Screens over async values keep their phase in `nokre.LoadPhase` — `idle`,
`loading`, `ready`, `failed`. It is pure vocabulary: the app writes it,
the app's screens read it, nokre never does (there is no framework
fetch, no staleness, no `Remote(T)` — a deliberate stop). The one
composition every consumer wrote at every such screen — say we're
loading, or say it failed and offer a retry, else build the content —
is the cursor's `loadGate`:

```zig
if (!try b.loadGate(state.view.phase, .{
    .loading = tr(.loading),
    .failed = tr(.couldNotLoad),
    .retry = .{ .label = tr(.retry), .on_press = .bind(State.retry, state) },
})) return;
// … build the ready content …
```

It returns whether to continue: `true` on `.ready` (having appended
nothing), `false` otherwise (having rendered the phase). `.idle` and
`.loading` render identically — an app that requests on first build
shows `.idle` for at most one frame, and distinct words for it would
flash. Every option defaults to appending nothing, so each state keeps
only what the screen actually says: drop `.retry` where retrying can't
help (a revoked invite), drop `.failed` where the failure is silent,
drop both copies and the gate is a bare phase check. `.title` states
the screen's title over the loading and failed states alone, for
screens whose real one is the loaded value (a row's own name); null
leaves whatever is standing, so a routed screen keeps its route's title
while it loads. The retry renders as a secondary-form button — recovery
beside the failure copy, never the screen's primary act. All copy is
the app's: nokre ships no words it would then have to translate.
A phase switch whose states say more than this (styled copy, extra
controls) stays a hand-written `switch` — the gate is the common
scaffold, not a required door.

#### … and what it draws instead of a sentence: the screen itself

A bare "Loading…" tells the reader nothing about what is coming, and
the screen then jumps into place around it. `stand_in` is the other
answer: while the value is not ready the screen draws its **own
template** — for real.

**If the consumer knows what sits where, it draws the real thing.**
Headings, labels, prose, badges, tile words, button words: real text,
drawn by the screen's ordinary draw code and announced as text, because
that is what they are. The only thing that draws as a muted block is a
string handed as `nokre.pendingValue`, which is a value the screen does
not have yet and therefore has nothing to say.

That is the inversion of the rule this element shipped with, and it was
made because the first consumer's frames showed what the old one
produced: a stand-in missing half its screen, because the template had
been rewritten with fake strings that did not match, and a primary
button drawn as a dark pill with a light block punched in it. A screen
where every word is a grey bar reads as a rendering failure. A screen
that is itself, with three values still arriving, reads as a wait.

There is **no motion**. The shape is the whole of it — the web's
shimmer is an animation, and nokre has none.

```zig
if (!try b.loadGate(self.phase, .{
    .loading = tr(.loadingBalance),
    .stand_in = .bind(Screen.drawStandIn, self),
})) return;
try drawBalance(b, self.view);

// in Screen — one template, two callers, and the second one is now
// the ordinary draw function with pending values where data would be:
fn drawStandIn(self: *Screen, b: nokre.Cursor) !void {
    _ = self;
    try drawBalance(b, .{
        .heading = tr(.balance),                     // known: real
        .amount = nokre.pendingValue("1,234.56"),    // not known: a block
    });
}
```

#### What is pending, and what a block is worth

`nokre.pendingValue(example)` is a string, so it goes in any slot a
string goes in — `text`, `styled`, a heading, a field's value, a
button's label, a badge, a tile's label or detail, a quantity's value,
a QR's payload. It draws a muted block, says nothing to assistive tech,
and is **refused outside a stand-in** (`error.PendingOutsideStandIn`): a
block with no live status over it is content nobody can see and nobody
is told about.

`example` is a value the screen would plausibly show. Its **characters**
size the block — one reference advance each, the same `0` width CSS
calls `ch`, so both substrates draw the same width — and its *words* never
enter the tree, so neither substrate can leak them. `nokre.pendingChars(n)`
is the same thing for a screen with no example string to hand.

It is clamped at 120 characters. A run wider than its column breaks at
the edge on both substrates — the raster's `wrap.breakWord`, the DOM's
one cell per character — so a long one is several pending lines, each
still a block. A wait the shape of prose is still the consumer's call,
the same call as the one below: size it by a sentence's worth of
example, not a paragraph's.

**A list of unknown length is the consumer's call.** Draw a fixed few
rows and name each by the value it is waiting for:

```zig
for (0..5) |_| try tiles.tile(.{
    .label = nokre.pendingValue("Ada Lovelace"),
    .detail = tr(.lastSeen),
    .on_press = .bind(open, self),
});
```

Naming them by the pending value is what makes five of them legal. Five
rows all really called "Last purchase" are five controls sharing one
name, and the audit's `duplicate_interactive_label` says so — correctly,
because under the new rule they are real, announced and addressable. A
pending name is in no accessibility tree and no focus order, so five of
them collide with nothing.

#### The scope's controls are disabled

**Every control under the scope is disabled for the scope's life** —
real words, dimmed, no press, no keystroke, focus stop kept,
`aria-disabled` and no `aria-busy`.

**Disabled, not busy**, and the distinction is the whole of it: busy is
a control's *own* work running, which is what `Button.in_progress`
says. Here the work is the screen's and the control has none — the thing
it would act on has not arrived. So it is off, and it looks off. A
waiting screen that drew a fully live primary pill doing nothing is the
frame this rule was corrected on.

The presentation is the disabled one nokre already draws, and since
revision 107 that reaches **every kind that carries a `disabled`** —
all ten of them, through the one door
[`disabled`](#turning-a-control-off-disabled) describes. The filled pill
drops to `g6` under `g11` words, the outlined one gives up its carrier, a
field's label and outline take the two steps, a switch keeps its knob's
end and a chip its ground, both muted. The one kind that keeps its own
look is `copyable`, which carries no `disabled` because nothing about
copying a value is an app's to withhold.

None of it is stored: the tree keeps the screen's own answer, and it
comes back unchanged the moment the scope closes.

A control that must stay live sits **above** the scope. There is no
per-control escape hatch inside it.

On the web the same holds, with one thing said plainly. Two things a
browser acts on with **no runtime behind them** are taken away outright:
a navigating tile and a `link` lose their `href` (keeping their kind and
their stop through `role` and `tabindex`), and a field is `readonly`.
For the rest — a checkbox, a radio, a select — HTML has no attribute
that refuses the press while keeping the focus stop, so the refusal is
core's, at the runtime; a page carrying any of them has one by
construction ([internals/dom-substrate.md](internals/dom-substrate.md)).

A button drawn muted — an outline in the pending tone with the block
inside and no fill — is the one whose **own label** is pending. Every
other button under the scope keeps its real form. A filled pill with a
block in it paints `paper` on `ink` and reads as a live primary act with
a hole punched in it, which is the frame that started this.

#### What it says

`.loading` stops being body copy and becomes the scope's accessible
name: assistive tech hears "Loading your balance" as one polite status.
The real text under it is announced as **normal text**, because it is
real. The pending blocks are silent. The controls are announced,
disabled — deliberately, and this was argued: their names are
real, and hearing them is how a screen-reader user orients on a screen
that is arriving, exactly as a sighted reader does. A gate that sets
`.stand_in` without `.loading` is refused at append: a screen that is
working has to say so.

The test locators are the one place that still treats the template as
absent, and that is not an inconsistency. A locator is the front half of
a driver and every verb it feeds *acts*; a screen that is waiting takes
no press and no keystroke, so a locator answering with the template's
field would hand `clearField` a control the app refuses to edit at the
exact moment the honest answer is "not yet". The wait outlasts the scope
instead ([testing.md](testing.md#queries)).

`Cursor.standIn` is the primitive underneath, for a scope with no
natural template function:

```zig
const s = try b.standIn(.{ .label = tr(.loadingBalance) });
try s.heading(.h2, tr(.balance));
try s.text(nokre.pendingValue("1,234.56"));
```

A stand-in inside a stand-in is refused — one wait, one announcement,
and the inner scope's name could never be read.

#### … and the branch after it: ready, but nothing to show

`loadGate` answers `true` on `.ready` and says nothing about zero rows.
That branch is `emptyGate`, and it goes where the list would have gone:

```zig
if (!try b.loadGate(c.phase, .{ .loading = tr(.loading), .failed = tr(.eFailed) })) return;
try b.heading(.h2, tr(.invoices));
if (!try b.emptyGate(c.phase, c.invoices.len, tr(.noInvoicesYet))) return;
for (c.invoices.items()) |*row| try appendInvoice(b, row);
```

It answers "there are rows — go on", and on ready-and-zero appends the
one line the screen has for that and answers `false`.

It takes the phase **again**, deliberately. The empty line belongs
beside the rows, which is usually a heading and a tile group past the
`loadGate` that admitted the build; a count-only verb standing there
would print "No invoices yet" over a request still in flight. So a
not-ready phase gets `false` with nothing appended — this verb never
speaks before the phase is settled, and never speaks *about* the phase
either, which is the other gate's job.

The line is **plain body text**. An empty state is the whole of what
that region says, not a footnote under something else, so it is not
dimmed or shrunk. `null` copy is the section that vanishes silently
when it has nothing, the same floor `loadGate`'s optional copy has. A
screen that wants more than one line — a hint under it, a control that
fills the emptiness — appends those itself; this is the common floor,
not a required door.

### The in-flight latch

`LoadPhase` is display-only and `Button.in_progress` is a pixel: nothing in
the framework *produces* busy. `nokre.Latch` is that missing bit, in the
same slot as `LoadPhase` — pure data nokre never reads.

```zig
pub const Invites = struct {
    deleting: nokre.Latch = .{},

    pub fn deleteInvite(self: *Invites, id: []const u8) void {
        if (!self.deleting.begin()) return;         // the second press does nothing
        self.port.deleteInvite(id, nokre.bindAs(Port.DeleteCallback, onDeleted, self));
    }

    fn onDeleted(self: *Invites, result: Port.Result) void {
        self.deleting.end();                        // on every arm, failure included
        …
    }
};

// and the screen reads the one bit:
try b.button(.{ .label = tr(.delete), .in_progress = c.deleting.up, .on_press = … });
```

`begin` fuses the check and the set and answers whether to proceed;
`end` lowers and is idempotent, because the reply paths that call it
include ones that never raised it. `up` is the public field, because
reading it is the whole consumer story and a second spelling would be
two names for one fact — but write it through the two verbs: a bare
`= true` is exactly the race the type exists to close.

**Put `begin` last in a compound guard.** It mutates, so a screen's own
preconditions go in front of it, where `or` short-circuits past it
instead of leaving the latch up on a path that then returns:

```zig
if (!self.form.ready() or !self.creating.begin()) return;
```

There is **no `defer` helper**, and that is not an omission. The work
these latches cover is dispatched, not performed: `begin` runs on the
press and `end` runs in a callback landing frames later, on paths the
raising function cannot see. `defer` composes with the wrong lifetime.

A latch, not a machine — no phases, no staleness, no "which row", for
the reason `LoadPhase` is not a machine either. A flow with more words than
up and down keeps its own enum, and a phase that happens to feed
`in_progress` (`stage == .sealing`, `search_phase == .searching`) is a
richer fact that stays the app's.

### The confirm sheet

The other composition every consumer wrote identically: a sheet that
asks before it acts. Title, what is about to happen, what went wrong
last time, the act, the way out — `confirmSheet` is the four appends
after the title, on the sheet's own cursor:

```zig
const sheet = app.at(try app.presentSheet(tr(.removeMemberTitle)));
try sheet.confirmSheet(.{
    .body = tr(.removeMemberBody),
    .error_copy = if (self.failed) tr(.couldNotRemove) else null,
    .confirm = .{ .label = tr(.remove), .on_press = .bind(Members.confirmRemove, self) },
    .cancel = .{ .label = tr(.cancel), .on_press = .bind(nokre.App.closeSheet, app) },
    .busy = self.removing,
});
```

The question is the sheet's *title*, so it stays `presentSheet`'s
argument; `.body` and `.error_copy` are optional, and a confirmation
with more to show — a continuity warning, a checkbox that gates the
act — appends that itself first and then calls this for the tail.
`.busy` marks the primary `in_progress`; `.confirm.disabled` is the
sheet's own precondition (a box not ticked), which is a different fact
and stays a different field.

**Cancel stays enabled while the act is running.** nokre has no spinner
and no animation, so a busy confirmation shows a static hourglass on its primary and
nothing else moves: a user who cannot tell whether anything is
happening must keep the way out. It is reachable anyway — Esc, the
scrim, and the close control the framework pins are all live — so a
disabled Cancel would be a control lying about what the sheet permits.
What a cancelled act owes, a reply landing on a sheet that is gone,
belongs to the handler that started it.

### Holding what a callback borrowed

Every slice a service or a port hands a callback is borrowed **for that
callback**. A screen that draws it next frame has to own a copy, and
owning without an allocator means a fixed capacity. `nokre.Str(cap)`
and `nokre.Rows(T, cap)` are those two shapes, in the same slot as
`LoadPhase`: pure data the framework never reads.

```zig
const max_invoices = 24; // a ceiling, not a business rule

const InvoiceRow = struct {
    id: nokre.Str(64) = .{},
    amount_cents: i64 = 0,
};

pub const Billing = struct {
    app: *nokre.App = undefined,
    phase: nokre.LoadPhase = .idle,      // the phase stays beside the list
    name: nokre.Str(96) = .{},
    invoices: nokre.Rows(InvoiceRow, max_invoices) = .{},
};

// Bound into the port's own callback type — see "Binding callbacks
// nokre never sees" below; the port need not know nokre exists.
// port.dashboard(id, nokre.bindAs(Port.DashboardCallback, onDashboard, self));
fn onDashboard(self: *Billing, result: Port.DashboardResult) void {
    switch (result) {
        .ok => |dashboard| {
            self.name.set(dashboard.name);        // copied out of the reply
            self.invoices.clear();
            for (dashboard.invoices) |invoice| {
                const row = self.invoices.push() orelse break;
                row.id.set(invoice.id);
                row.amount_cents = invoice.amount_cents;
            }
            self.phase = .ready;
        },
        .err => {
            self.invoices.clear();
            self.phase = .failed;
        },
    }
    self.app.refresh(.{});
}
```

**`Str(cap)`** — `set` copies and replaces; `get` hands the bytes back;
`eql` compares against any slice (two `Str`s are `a.eql(b.get())`);
`trimmed` drops surrounding ASCII whitespace and `blank` is that trim
coming up empty. `len` is a public field, so `name.len != 0` is the
idiom for "there is one". Not a builder: no `append`, no `fmt` — build
a string in a stack buffer and `set` it once, or use `tree.fmt` for
strings the tree will own anyway.

`set` accepts a slice of the `Str`'s **own** bytes, so trimming,
re-parsing or normalizing in place is one line
(`field.set(field.trimmed())`) rather than a round trip through a
scratch buffer. `Rows.fill` takes the same guarantee —
`list.fill(list.items()[1..])` drops a head.

A `set` past the ceiling truncates, and **never splits a UTF-8
sequence**: the cut backs up to the start of the codepoint it landed
inside, so what comes back is always something you can hand straight to
`append` again.

**`Rows(T, cap)`** — `items()` to draw, `at(i)` for a screen holding an
index (`null` past the end, so a stale index is not a crash),
`itemsMut()` for `std.mem.sort` or an edit in place. Filling is
`clear()` then either `push()`, which hands back an empty slot to write
field by field (`null` at the ceiling), or `append(row)` for a row
already built; `fill(slice)` replaces the whole list at once. `removeAt`
closes the gap and keeps order, and `full()` says the next push would
refuse. Both types re-state their ceiling as a declaration
(`@TypeOf(list).capacity`), for the `meter` max or the copy that names
it where the constant is not in scope.

**The ceiling is disclosable.** Both types carry `truncated`: on a
`Str` it means the last `set` stored less than it was given, on a
`Rows` it means something was offered and did not fit. Each verb that
installs a whole value answers for that value — `set` and `fill`
overwrite the flag, `clear` clears it — while `push` and `append` raise
it on every refusal, so a `clear`-then-fill loop accumulates one honest
answer. A screen that wants to say "showing the first 24" reads it; one
that does not, ignores it. What neither type does is truncate in
silence, which is what every hand-rolled `@min(cap, reply.len)` did.

`Rows` carries no `LoadPhase`. The phase is the app's — one request may fill
two lists, and one list may be filled by two requests — so it stays a
field beside it, exactly as the example above has it.

## Static

### `text`
Body copy. Wraps greedily at word boundaries within the parent width.
Options: `style` (family `mono`/`prose`, scale, one of the thirteen grays).

Inline structure comes from `spans` — Markdown's inline vocabulary, not
a styling hook: each span is a run of the content with `strong` (bold),
`emphasis` (italic), `code` (the mono family, verbatim voice), `strike`
(struck through), and optionally its own gray, which faces the same
append-time contrast gate as the element's ink. Give either `content` or
`spans`, never both: with spans, `append` writes the concatenation into
`content`, so assistive tech announces one plain text node — span
boundaries are invisible to it by design. That places the same duty on
spans that grayscale places on color: a span may restate emphasis the
words carry, never be information's only carrier. **`strike` is where
that duty bites hardest**: a struck price is heard as a price, so the
words around it have to say which one applies ("Fees are ~~£20~~ £0"
reads correctly struck or not; a bare struck list of options does not).
Wrapping treats the spanned text as one flow — a word crossing a span
boundary never breaks there — and measures each run with its real face;
bold and italic are drawn faces bundled per family, never synthesized.
`strike` is not a face: no bundled family ships a struck variant and
synthesizing one would re-open the rasterizer variance the bundled fonts
exist to close, so it is a 1px rule drawn a quarter of the em above the
baseline — through the lowercase band — and it costs the measurement
nothing. Scale stays element-level: mixed sizes inside a line would
break the uniform line box.

A span with a destination is an **inline link**, and the one carve-out
from everything above. It is a control, not styling: underlined, its
own tab stop in document order, activated by tap/Enter/Space, and
announced to assistive tech as a link inside the paragraph — a link
nobody can hear is worse than no link at all, so the invisibility rule
stops exactly where behavior starts. A destination is exactly one of
two kinds, and the split is semantic, never visual: a `route` resolves
through the router like a `link` element's, so a bad one is refused
where every other bad route is and the audit names the node
([routing.md](routing.md), errors and refusals); an `external`
URL is handed to the system browser through the
[open_url](services.md) service, whose closed scheme allowlist
(https/http/mailto) is checked at `append` — nokre still renders no
external content. `append` holds both kinds to the rules every other
control obeys: never both destinations at once, and words that aren't
only whitespace. A span with **no** destination is simply prose, and
an empty `route` is how a span says so — every route-carrying field in
the set is a plain `[]const u8` defaulting to `""`, never an optional,
so "no route" has one spelling and every reader asks one question
(`route.len > 0`).

`lang` is the one thing a span carries that is neither vocabulary nor
destination: the BCP 47 tag of the language *these words* are in, where
it is not the document's — WCAG 2.2 **3.1.2 Language of Parts** (AA).
Empty, the default and nearly every run, means the page's own
(`App.locale()`, on `<html lang>`). A language chooser is the
criterion's textbook case and the one it was built for: `English`,
`فارسی`, `Türkçe` in a page of a fourth language, where without the tag
a screen reader says each of them with the wrong phonemes. `append`
holds the value to the tag grammar — two or three ASCII letters, then
`-`-joined subtags of one to eight letters or digits, so `zh-Hans` and
`pt-BR` pass while `Persian`, `pt_BR` and `tr-` are
`error.InvalidLangTag` — and stops there: it is a grammar, not a
registry, and the value in honest use is `L.tag(loc)` off your own
bundle rather than a string you typed. A catalog spelled `pt_BR` is
not the exception it looks like: `L.tag` publishes BCP 47 whichever
separator the `@@locale` used, so the chooser above builds against it
([localization.md](localization.md))
([static-sites.md](static-sites.md), "What the deletion cost"). There is
no `dir` beside it: a wholly-directional run is what the bidi algorithm
answers, and a direction that ever has to be written is derived from the
tag. Only the [DOM substrate](internals/dom-substrate.md) acts on it —
`lang` on the run's own element, the `<a>` where the run is a link and a
`<span>` where it is prose — as only it acts on `Heading.anchor`; no
native accessibility bridge here carries a per-node language, so on the
five drawing platforms it is inert rather than wrong. A whole passage in
another language is one span over the whole content, which is why
neither `text` nor `heading` has a field of its own.

A link that wraps — or that a bidi line splits into separate visual
runs — occupies several rectangles, and every one of them underlines,
rings when focused, and takes taps; the prose between them does none of
those. Drawing, hit testing, and the focus ring (drawn on
keyboard-origin focus only — [accessibility.md](accessibility.md#focus))
all read the same geometry walk, so what you see underlined is exactly
what you can tap.

### `heading`
`h2` through `h6`, mapped to fixed sizes on the type scale. Headings are
structure, not styling — the a11y audit fails if you skip levels.

`h1` is not a builder's to write (`error.HeadingAtTitleLevel`): the
page's top is what the screen is called, stated once and drawn by the
library — `RouteDef.title`, or `App.setTitle` where the two differ
([routing.md](routing.md)). So a screen's sections start at `h2`, which
is the level field's default.

| Level | px | Level | px |
| --- | --- | --- | --- |
| `h1` (the title) | 32 | `h4` | 18 |
| `h2` | 24 | `h5` | 16 (body) |
| `h3` | 20 | `h6` | 12 (small) |

Only three sizes sit above the 16px body, so size alone cannot carry six
levels. Every level draws **bold**, in the family's real bundled bold
face — never synthetic emboldening — which is what keeps `h5` and `h6`
reading as headings beside the prose they share a size with. Contrast is
unaffected: nokre holds all text to 4.5:1 regardless of size, declining
WCAG's large-text exemption, so the scale carries no palette consequences.
Takes `spans` like `text` (base face bold
prose, base ink `.ink`) for the `code` word inside a title; because the
base is already bold, a span's `strong` adds nothing to a heading and a
span without it does not drop back to regular — span variants compose
onto the element's face rather than replacing it.

`anchor` states the address a section is linked to by, for the rare
heading something outside the page names — an account-deletion section
an app store's policy points at, which has to answer at the same address
in every language the page is published in. Left empty (the default, and
every other heading) the [DOM substrate](internals/dom-substrate.md) derives
one from the words, which is a different address per language.
`b.anchored(.h2, "delete-account", title)` is the cursor form. The value
is an ASCII letter followed by ASCII letters, digits, `-`, `_` or `.` —
so it is an `id`, a URL fragment and a CSS selector at once — and
`append` refuses anything else, which is also what catches an anchor
accidentally run through the translation table. Uniqueness within a
document stays the library's: a stated address that collides fails the
build rather than being renamed around. The argument is
[static-sites.md](static-sites.md), "A heading id is a destination".

### `icon`
One named Lucide glyph, laid out as a square line-height box so it
aligns with same-scale text beside it. Options: `name` (the `IconName`
enum — its value is the icon-font codepoint), `scale` (the six text
scales), `ink` (the thirteen grays), `label`. `IconName` holds every
glyph in the bundled font, under Lucide's current name for it — the
retired aliases are absent (`square_activity`, never `activity_square`),
and so are the brand marks Lucide dropped from the font. An empty label means
decorative: hidden from assistive tech, any ink allowed. A non-empty
label makes it a meaningful image: it is announced by name and its ink
must clear the same contrast gate as text.

### `divider`
A 1px horizontal rule across the parent width.

### `badge`
A static inline status label: small-scale text inside a rounded 1px
`.g10` border, sized to its content. Where color-coded chips carry state
by hue elsewhere, here the words carry it — "Active", "Owner",
"3 pending". The border is grouping, not state, so it draws `.g10` like
`box`, not the `.g6` state carrier of selected chips. Never interactive
(an actionable chip is a `button`), and the label must be non-empty —
an empty badge is a floating border saying nothing. For status inside a
`tile` row, use the tile's `detail` line instead of nesting a badge.
Semantics: plain static text; assistive tech hears the words, which is
everything the badge *says*.

An optional `icon` (any [`IconName`](#icon)) leads the chip, on a
`tile`'s terms: decorative, a field rather than a child node, so the
mandatory `label` stays the accessible name and no glyph can enter the
tree to double it. It draws at the chip's own scale and ink (`small`,
`.ink`), so it opens no styling surface and reaches the contrast gate
exactly where the label already cleared it.

**It restates; it never states.** "The words carry it" was never about
whether a chip may hold a glyph — it was the refusal of *state conveyed
by ornament instead of language*, the same refusal that keeps hue out.
A mark that means something the words do not is that refusal broken: the
chip then says less to a reader than to a looker. The check is one
deletion — take every mark off the screen, and nothing on it has stopped
being true or knowable. What a glyph buys is recognition in a row that
gets scanned; a dimension chip's mark restates the dimension its label
names, a tag chip's restates the family its set is organised by. A chip
whose words are the whole story and whose glyph is the only clue that
something failed is the case this paragraph refuses.

Unlike a `tile`, chips carry **no all-or-nothing rule** and no fixed
band: a tile's mark reserves a `lineHeight` square so a *column* of rows
starts its words on one x, and chips are intrinsic-width and flow
inline, where there is no column to hold. So a chip is charged only the
glyph's own advance plus the icon gap — a flat **20px** at the small
scale, the same for every glyph in the bundled face (pinned by a test,
since the guidance below rests on the number).

Twenty pixels is 15% of a long chip and over a third of a short one, on
an element that is often several across in a row on a 320pt screen. That
row [wraps](#a-row-too-narrow-for-its-children) rather than clipping, so
the width a mark takes is spent in *lines* now rather than in pixels off
the edge — cheaper, and still spent. So: **a mark earns its width where chips are read as a
set** — a row of tags, a row of dimensions, where the glyphs are what
lets the eye sort them — and not on a lone chip beside prose, where it
is 20px spent on a picture of a word already visible next to it.

**A number with a name on it is a badge.** "3 credits", "12 active
keys", "2 pending" — a quantity and the thing it counts, formatted by
you (nokre does no number formatting; that is
[localization.md](localization.md)'s refusal) and handed over as one
label. That is what the element is: the chip whose *words* carry the
state, so a labelled scalar is its central case rather than an
afterthought. Reaching for `text` instead is the mistake this paragraph
exists to prevent — plain text puts the figure in the prose column at
prose weight, where nothing distinguishes a live count from a sentence
about one, and the border a badge draws is exactly what says "this is a
reading, and it changes".

The one to hand it to `meter` instead is a **fraction of a whole you
want seen as a fraction**: "5 of 10 uses", "12 of 30 days". Both
elements put the state in the words, and the split is whether there is a
whole to be part of and whether being three-quarters through it is worth
a glance. A count with no ceiling ("3 credits") has no bar to draw and
takes the chip; a count against a ceiling you are meant to feel takes
the bar and the full width it needs. Where the ceiling exists but the
fill would say nothing — "1 of 4 seats", in a row of other chips — the
badge is still the honest answer, and the words still say all of it.

### `meter`
How much of a whole is filled: a full-width bar under words that state
it, at `text_input`'s label scale. As with `badge`, the words carry the
state — `label` ("12 of 30 days") is mandatory, rendered above the bar,
and is what assistive tech hears; the `value`/`max` fill only restates
it visually. `append` rejects an empty label or a value outside
0...max. The track is the `segmented` pattern: dimmed `.g11` with a 1px
`.g6` border carrying WCAG 1.4.11, an `.ink` fill inside. Never
interactive, never animated — for indeterminate waiting, write
"Loading…" as `text`; a spinner is animation, which nokre refuses.
Semantics: plain static text, the words.

### `diverging_meter`
How a whole divides in two directions: two arms drawn from one centre,
each with its own words at its own end, under a row label at
`text_input`'s label scale. Where `meter` asks how far along one
quantity is, this asks how a pair stands against each other — the
per-dimension shape of a cycle, a budget split two ways, a vote. The
centre is the reading: either share is the distance from it, which is
what a pair of separate bars cannot say.

`label` names the row and is the accessible name. `start_label` and
`end_label` are what each side says — a magnitude and the thing it
counts, formatted by you, as a `badge`'s words are — and both are
**mandatory**, because they are the whole of what a reader who cannot
see an arm gets; they are announced together as the value, joined by
nokre. `start` and `end` are each drawn against `max`, which is the
ceiling of **one** side rather than the pair's total: two rows handed
the same `max` are two rows you can compare down a column, which is the
reason the field is yours to state and not derived per row. `append`
rejects an empty label of any of the three, a `max` of zero or less, and
a magnitude outside 0…max.

The track is `meter`'s — dimmed `.g11`, a 1px `.g6` border carrying WCAG
1.4.11, `.ink` arms inside it — plus one thing `meter` has no need of: a
1px `.ink` **centre tick**, standing 2px proud of the track top and
bottom. That overhang is not decoration. Two full arms fill the track
with ink and would swallow a tick drawn only inside it, and a centre you
cannot find is a row you cannot read. Nothing else distinguishes the two
arms — one ink, no hatch, no texture. They are told apart by which side
of the centre they stand on and by the words at their ends, and a
texture that meant something the words did not would be the refusal
behind "the words carry it", broken the same way a hue would break it.

Under RTL the whole row mirrors — the start side is the right one and
the arms mirror with it, because a magnitude drawn toward the start is
drawn toward where reading begins.

The words take their own line under the track when flanking it would
squeeze the track below `metrics.diverging_min_track`. Side labels are
unbounded consumer words on a 320pt screen; the alternative to that
fallback is an arm shrunk to nothing, or two words meeting in the
middle. That answer is the row's own only while the row stands alone —
in a column it is `diverging_group`'s. Never interactive, never
animated. Semantics: plain static text — the row's name and both
readings.

Reach for `meter` where there is one quantity and a whole it is part of,
and for two `badge`s where the two counts are worth reading but their
*balance* is not — the arms are the glance, and they are the only reason
to spend a full-width row on what two chips would also say.

### `diverging_group`
Diverging meters read against one scale. It holds `diverging_meter` rows
and nothing else (`error.DivergingGroupChildMustBeMeter`), takes no
fields, and makes the one decision none of its rows can make alone: the
widest words on each side decide a single flank width, so every track
starts and ends at the same x and the whole column flanks or stacks
together.

**Put a column of rows in one.** A shared `max` is what makes two rows
comparable; the group is what makes the comparison visible. Left to
themselves the rows each answer the narrow question separately, and a
row whose words happen to be short keeps flanking while its wider
neighbours stack — which is not a rounding difference. Six dimensions of
a cycle in German at 320pt, five unanswered ("0 Beobachtungen") and one
with something to say ("3 Beob."), stacked the five and left the sixth
flanking a floor-width track: a quarter of the track its empty
neighbours got, on the one row a reader came for.

Each row's own words still sit flush against their own outer edge inside
the shared flank, so a short row keeps the column's two edges rather
than hanging off the widest row's. A lone `diverging_meter` outside a
group is unchanged — it answers for its own flanks, which is what a
group of one would answer too.

The DOM substrate states the same guarantee a different way: the group is
a three-column grid every row subgrids onto, so no row sizes its own
sides or wraps on its own. Its narrow answer differs on purpose — CSS
cannot ask "would this fit?" the way a measurer can, so there the side
columns compress in place where the reference substrate moves the words
under the track. The floor is the track column's own in both, so neither
answer squeezes, overlaps or clips. Never interactive. Semantics: a
`group` that says nothing its rows don't — it decides a width, not a
reading.

### `qr`
A verbatim value restated as a scannable QR code — `copyable`'s visual
twin for the value that leaves through a camera instead of the
clipboard. `label` (mandatory, rendered above at `text_input`'s label
scale) is what assistive tech announces; `value` (mandatory, and
carried alongside the label) is the encoded text. Encoding happens once
at `append` — medium error correction, no knobs — via the vendored
reference implementation ([deps/qrcodegen](../deps/qrcodegen/),
Nayuki's C library: single file, no heap, deterministic); a value that
cannot encode is rejected there (`QrValueTooLong`, `QrValueNotText`).

The square renders at a whole number of pixels per module (fractional
modules blur and break scanning) with the spec's 4-module quiet zone,
capped at `metrics.qr_max_side`. It is the one surface that ignores the
appearance: scanners want dark modules on a light ground, so the code
draws ink-on-paper from the light palette in dark mode too — a
deliberately light tile. Never interactive; put a `copyable` beside it
carrying the same value for the clipboard path. Semantics: an image
named by the label, carrying the value.

### `quantity`
The one number a screen is about. `value` (mandatory) is the number as
the app already formatted it, `unit` is what it counts, and `caption`
says what it is. It is the figure itself, drawn large — where `meter` is
words with a bar restating them and `badge` is words with a border, here
the number *is* the content.

**nokre formats no number.** Grouping, decimal marks and digit shapes
are the locale's, the app owns its locale, and a library formatting here
would be guessing at both — so `value` arrives as bytes and this element
only ever places them. Pass `"1,284"`, `"1.284"` or `"۱٬۲۸۴"`; the
element will not turn one into another.

The value draws at the `h1` scale in the **mono** family, so that a
column of these lines up digit under digit — the one thing a
proportional face cannot do, and the reason the family is not a styling
choice. One exception falls out of the font set rather than this
element: an Arabic-script digit selects the companion face whatever
family was asked for (`arabic.ttf` is the only bundled face carrying
Arabic-Indic digits), so a Persian number is drawn in that face's
figures. It still reads left to right inside a right-to-left line, which
is the shim's `resolveFace` doing its job — `quantity-rtl.ppm` is the
picture that says so.

The unit sits on the value's baseline at the small scale, a
`quantity_unit_gap` after it — before it under RTL, because the number
leads and the unit trails. **When the pair will not fit the span the
unit takes a line of its own**, and the element owns that decision:
a consumer that had to state it would be measuring text, which is the
thing layout exists to do. Both substrates answer it the same way, layout
by `quantityRow` and the browser by the same gap and the same two
scales. The caption wraps as prose under both, in the small muted ink.

Never interactive, never animated. `append` rejects an empty `value` —
an element whose whole content is one number cannot have none — and a
`reading` written by a consumer, which is append's to derive.

Semantics: one static-text node. The value and the unit joined are its
**name** (`Quantity.reading`, built at append from the copies the tree
just made — `DivergingMeter.reading`'s mechanism and its reason: a
snapshot borrows from the tree and has nowhere to build a sentence), and
the caption is its **value**. The slots are the reverse of
`diverging_meter`'s, where the row's own label is the name and the two
sides joined are the value: there the label names the row and the
numbers are what it holds; here the number *is* the thing and the
caption says what it is. The DOM substrate puts both in real text and lets
the browser compute the same name.

Reach for `quantity` over `meter` when there is no whole to be a
fraction of, over `badge` when the number is the point of the screen
rather than a mark on something else, and over a `heading` when what is
large is a figure rather than a title.

## Containers

### `stack`
Vertical (default) or horizontal flow. `gap` (default 8), `padding`
(default 0). The tree root is a vertical stack with padding 16.

**The page has a maximum, and it is not yours to set.** Content flows in
a column capped at `metrics.page_max_w` (760) and centred in whatever is
left, because line length is a legibility rule and prose is what these
screens hold. Below the cap it changes nothing, so a phone's page is
what it always was; past it a window twice as wide reads the same as one
at the cap instead of growing a measure nobody can follow.

**The cap is the `page` shape's.** A route declaring `desk` takes the
window instead — and the same cap applies again inside each of its
regions, because a region is where the prose is on a desk. Which of the
two a screen is, is its route's declaration: `RouteDef.shape`, one word
per route, in [routing.md](routing.md).

It applies in **both** substrates, as one number stated twice — once in
core, once in the generated sheet, from the same constant — so what the
browser lays out is what core measured. A host page capping a second
time would overrule both.

There is no element field, no `App` call and no opt-out, for the reason
nothing else here has one: a knob would let two screens in one app
disagree about how wide reading is.

A borderless stack's padding is an advised margin, not a wall: children
are inset by it as usual, but an element that must reach an edge to
work — today only an overflowing `segmented` track — may decline the
advice and bleed through it, never past the nearest drawn edge. Which
element bleeds is the framework's decision, not a knob. Negative
`padding` and `gap` are rejected at `append`: the escape a negative
inset buys elsewhere is exactly what declining the advice provides,
bounded by an edge instead of a number.

#### A row too narrow for its children

A horizontal stack that runs out of line does one of exactly two things,
and **the row's own children pick which**. There is no field, no wrapper
and nothing to opt into, so there is no way to be handed the wrong one:

- **A row of actions folds.** Every child a `button` or a `link`, two or
  more of them: the tail collapses into a `More` control and the row
  stays one line. [The folded tail](#the-folded-tail-more) has the
  mechanics.
- **Every other row wraps.** Children flow along the line and break onto
  a new one when the next will not fit — greedy, first-fit, in document
  order, each line `gap` below the last and centered on its own tallest.

The split is what the row *is*. Actions have to stay reachable and a user
needs all of them, so one row plus a control that opens the rest is the
honest shape; folding three status chips behind `More` would hide state
behind a press, and clipping them would hide it outright. Wrapping is
also the answer for the one row of actions that cannot fold — a lone
action, which a control named `More` would hide twice. Where the row
stands changes nothing: a row of actions inside a sheet folds like a
screen's, its tail opening as a sheet stacked over the one it is in
(since 2026-09-09, when sheets began to stack).

Width is not an input to the choice. A row is a row of actions or it
isn't, at every viewport, so resizing the window can change where a line
breaks or how deep a tail folds, but never which of the two the reader is
looking at.

Wrapping bounds the problem the way shortening the words never could:
**a row can always fit, as long as each child fits a line on its own.**
One that does not — a chip whose label alone exceeds the span — gets a
line to itself and overflows it. Nothing ahead of it pushes it further
out and nothing behind it is dragged along, but nokre does not shrink it,
elide it or refuse it: an oversized chip is over-long *words*, and the
words are the whole element ([badge](#badge)). Prose does not behave
this way — a word too wide for its column breaks at the edge — and the
difference is the chip's single line, which has no next line to break
onto.

Wrapping changes where marks land and nothing else. No node is added,
removed or hidden, the focus order is document order either way, and the
accessibility snapshot of a row that wrapped is identical to the same
row's on a wider screen. A reader is never told a line broke — because
nothing about the app did.

### `box`
Grouping container: vertical flow, optional 1px border (default on),
`padding` (default 12), optional `fill` gray. Boxes group; they do not
decorate. A box's edge is a wall: the margin advice stops at it, so
nothing ever bleeds across a border.

In vertical flow a box takes the full width. Unstretched — as a child of
a horizontal `stack`, or inside a table cell — it hugs its widest child
plus its own padding, so a row of small boxes stays a row instead of
running off the edge after two.

### `stand_in`
A scope whose content has not arrived. Lays out exactly as the `stack`
it replaces (`axis`, `gap`, `padding`, same defaults), so the template
inside it stands where the real content will. `label` is required and
is what the whole scope announces.

Under it, everything draws **real** — the consumer's ordinary draw code
runs, and its words are its words. What blocks is a string handed as
`nokre.pendingValue`: a rounded `g10` block one reference advance per
character of the example it was sized by, silent to assistive tech, and
refused outside a scope. Every control is **disabled** for the scope's
life — real words, dimmed, no press,
no keystroke, focus stop kept, and no `aria-busy`, because the work
running is the screen's and not the control's — and the one drawn muted
is the one whose own label is pending. The full rule, the idioms and what was
argued the other way are under [`loadGate`](#-and-what-it-draws-instead-of-a-sentence-the-screen-itself)
above.

**A heading under the scope keeps its words**, which is the reversal at
the centre of this. It was decided the other way first, on the ground
that a screen where some words are real and some are grey bars reads as
a rendering failure — and the answer turned out to be the opposite one:
a screen where *no* word is real is what reads as a failure, and the
consumer already knows which words it has. Nothing is decided per
element by the framework any more. The consumer says what it knows by
drawing it, and says what it does not by handing a pending value.

Reach for the `loadGate` form (above) when the screen has a template
function already; reach for `Cursor.standIn` when it does not.

### `scroll_region`
A viewport over vertically flowing children. `height` fixes the viewport
height; leave it null to fill the space remaining below the region.
Content is clipped; a 2px indicator bar reflects the offset. Focusable:
arrow keys, page up/down, home/end scroll it. `content_height` is written
by layout.

The bar has two tones, switched by state, never by time: emphasized
while its surface is engaged — focused, held by a touch drag, or the
last thing scrolling input moved — and quiet at rest. The overlay
scrollbar's prominent-when-relevant behavior without its two failures:
"fade after the scroll stops" needs the wall-clock timer the
deterministic core refuses, and a bar that vanishes at rest takes the
only sign the content scrolls with it. So emphasis latches until the
next non-scroll input, and the resting bar stays readable. At rest the
primary "more is there" affordance is the content itself, cut
mid-element at the viewport edge; the audit fails a fixed-height region
whose offset-0 edge cuts nothing visible (see
[accessibility](accessibility.md)) — adjust the height a few px so the
edge crosses ink, not a gap or a text line's leading.

The window itself needs no wrapper: content taller than the viewport
scrolls implicitly — wheel outside any scroll region, scroll keys when no
widget consumes them — and Tab always scrolls the focused element into
view. The implicit window scroll is not a tab stop.

Wheel scrolling routes at the pointer, event by event: delta a region
cannot consume chains outward to enclosing regions and then the window.
A touch drag instead belongs to the scroller it starts in — momentum
included — even when the finger leaves it or its content runs out;
nothing else moves until the finger lifts.

### `region`
One place on a **desk**: the roster you pick from, the subject in hand,
the facts beside it, the strip you act from. A region is a direct child
of the root on a route that declared `.shape = .desk`, and nowhere else
— a page refuses one, and a desk's root refuses anything that is not one
([routing.md](routing.md), "A screen declares its shape").

`role` is the only thing you state about it. Placement, pinning, width
and what a window too narrow to hold them side by side does all follow:

| Role | What it is | Where it stands | How wide |
| --- | --- | --- | --- |
| `masthead` | the desk's own state — who is on shift, how deep the queue is | held against the top of the band, over the columns | the band |
| `roster` | the list of subjects, each row a way into one | the leading column (right, mirrored) | `metrics.desk_col_w` |
| `main` | the subject | between the columns | whatever they leave |
| `aside` | facts about the subject already on screen | the trailing column | `metrics.desk_col_w` |
| `composer` | where you act on the subject | held against the bottom of the band | the band |

**Every desk has a `main`.** It is what the roster's rows lead into,
what the band's remaining width goes to, and where a narrow desk opens;
a desk without one fails the audit ([accessibility.md](accessibility.md)).
The other four are each optional and each declared at most once.

**Every region is a viewport over its own children**, the two pinned
strips included — there is no "does this scroll" question to ask of a
role. On the reference substrate a strip stands as tall as its content
and no taller than a third of the band (`metrics.desk_pin_divisor`), so
a masthead that ran long scrolls itself rather than becoming the screen;
the DOM substrate has no such cap and gives a long strip the height it
asks for ([internals/dom-substrate.md](internals/dom-substrate.md)). The
band's regions each scroll independently, which is the whole reason a
page could not serve this family: a composer that scrolled away is a
composer you lose mid-sentence.

**No width, no height, no padding, no gap** — the four knobs a device
conditional would reach for. The inner margin and gap are the page's
own, and the inner column keeps the prose measure, so a block inside a
region sits exactly where the same block sits on a page.

`label` is required and non-empty, and it is one name doing two jobs: it
is what a screen reader announces the landmark by, and it is the words
on this region's chip when the desk folds. An unnamed landmark is one a
reader cannot choose between, which is the whole point of a desk's
landmarks; it is not derived from `role` (five English words nokre would
then owe every locale) and not from the route title (that names the
screen, this names a part of it).

**Append order is reading order**, and it is the role order above —
`error.RegionOutOfOrder` otherwise. Tab walks the tree in document
order, so a desk whose declaration disagreed with its layout would be a
screen where the keyboard moves one way and the eye moves the other.

**A window too narrow to stand the band shows one region at a time.**
The threshold is the desk's own — every side column it declared, plus
main's floor — and not a breakpoint, so a console with no aside stands
its band in a window a three-region one cannot. Below it the framework
adds a region switcher, a `segmented` named by `Chrome.regions` whose
chips are the regions' labels; the masthead stands on every one of those
screens, the composer travels with `main`, and the region not being
shown is **folded** — off the screen entirely, subtree included, absent
from the accessibility snapshot and unreachable by a test query. Back
does not undo a switch: a region is not a screen and has no reference of
its own. `App.setDeskView` is the same door the switcher uses.

The fold is all-or-one on purpose. A graded fold — the aside first, then
the roster — would make the switcher's chips mean "replace what is in
the middle" at one width and "reveal a hidden column" at another, and a
control that means two things is what this library deletes.

Each region draws a hairline on the edge it owns — under a masthead,
over a composer, down the inner side of each column — because grayscale
has nothing else to separate two places with, and a desk with no lines
reads as one wide page. `main` draws none: its neighbours already drew
both.

## Interactive

Every interactive element **requires a label**. That is not a convention
and not a lint: `tree.append` refuses to construct an interactive element
with an empty label — an inaccessible control cannot exist.

### Turning a control off: `disabled`

**Ten kinds carry a `disabled`, and it means one thing on all of them.**
`button`, `text_input`, `text_area`, `toggle`, `checkbox`, `segmented`,
`radio_group`, `select`, `tile`, `ranking`. The eleventh interactive kind, `copyable`,
has none: its activation is intrinsic — it copies its own value — so
there is nothing an app could be withholding.

Off is four statements together, and no kind keeps only some of them:

- **It leaves the focus order.** Tab runs past it, and on the web that is
  the platform's own `disabled` attribute rather than `aria-disabled`,
  because markup that only *said* disabled would leave a keyboard user
  Tabbing into a control core has no stop for. The one kind with nowhere
  to put the attribute is a navigating `tile`, an anchor, which drops its
  destination instead — and drops the stop with it.
- **It takes no press and no keystroke.** A `route` tile navigates
  nowhere; a `select` opens no picker; a field takes no caret.
- **Assistive tech is told**, and everything a reader needs is still
  announced: the name, and the value in whichever slot the kind carries
  it — a switch's position, a box's tick, a chosen option, a row's
  reading. Off is not gone.
- **It draws off**, in one vocabulary. There is no color to spend, so it
  is three steps: words and any ink a control fills with drop to `.g6`,
  whatever stands *on* that fill rises to `.g11`, and a state carrier
  gives up its `.g6` edge for the `.g10` grouping tone. Nothing else
  moves — same shape, same glyph, same size, nothing animated — so an off
  control is the same control, receded. WCAG 1.4.11 exempts an inactive
  component, which is what buys the last two steps.

**A boundary that groups rather than states does not move**: a tile
group's border and its hairlines, a radio group's card. They are `.g10`
already, and structure is never state.

**Two things keep full `ink`, and both are values rather than
affordances**: a field's text, because this state exists precisely while
that text is on the wire and dimming the one thing worth checking would
blur the pattern at the moment it matters; and a `select`'s chosen
option, for the same reason under the same chrome. A button's words *are*
the offer, so they dim with it.

**Off is not busy.** `in_progress` is a control's *own* work running: it
wins the pixels (an hourglass on a live pill, a busy mark in the switch's
slot), keeps the focus stop, and does not dim. `disabled` wins the stop.
An app deriving one from its form and the other from its work has no
reason to reconcile them, so both may be set at once.

**And off is not what a [stand-in](#stand_in) does**, though it looks the
same. A scope's control is off for the scope's life and **keeps its focus
stop**, because the thing it would act on has not arrived rather than
being withheld. The scope reaches all ten through the same door this
section describes — the field named `disabled`, read by reflection
(`Element.isOff`, `Element.turnOff`) — which is why a tenth kind that
declares one is announced, marked up and drawn off the day it is
declared, with nothing to wire.

### `button`
`label`, `on_press`, `disabled`, `in_progress`, `form`,
`accessible_name`. A filled pill —
ink fill, paper text — ringed on keyboard-origin focus
([accessibility.md](accessibility.md#focus)). Activated by tap, Enter,
or Space.

`form` says which button this is, as a tagged union with four faces:
`.filled` (the default), `.secondary`, `.glyph`, and `.provider`. One
field rather than four flags, because the flags' illegal combinations —
a glyph form without a glyph or with an emphasis, an icon beside a
vendor mark, a glyph-only sign-in, an outlined Google — used to be five
separate refusals at `append`; as a union they are not states the type
can spell, and what compiles, appends.

`.secondary` is the one emphasis: an outlined pill — ambient
background, 1px `.g6` border (the segmented/toggle WCAG 1.4.11
carrier), `.ink` text — beside the filled primary. Identical geometry,
so the pair aligns; identical semantics, so assistive tech hears no
difference. Because its text draws on the ambient, it passes the same
contrast gate as `text` — a secondary button on a dark box fill is
rejected at `append`. There is no tertiary and no danger variant: one
filled, one outlined, and the words carry the rest.

**The label wraps inside the pill, and the pill grows to hold it.** A
button asks for the width its words want and takes what it is offered;
when that is less, the column it wraps to is the box less its border,
its padding and its lead mark (`layout.buttonTextWidth`), and layout
measures the box against the same wrap the renderer draws. No caller
states a width or a line count, so no form of the pill can be handed a
label it will not contain — a price that fits in English and runs long
in German is the ordinary case, and a pill that could be overrun would
put that measurement in every call site. Until revision 96 the box was
one line whatever it was handed while its width was capped at what it
was offered, and the rest of the label was painted past the pill: on an
outlined one that reached a store screenshot with the price cut off, and
on a filled one it is paper on paper and the words simply disappear.

`in_progress` says the button has been pressed and the work it started
is still running — not "loading", because nothing is being loaded, and
not a spinner, because a spinner is animation this frame model does not
have. The words stand down for an hourglass — Lucide's, static, in the
icon face — centered in the pill at the size the label and icon already
bought it: the button does not resize when the press starts or when the
result lands, so nothing under the finger
moves. It does not dim. `disabled` is unavailable and dims; `in_progress`
is busy and stays at full strength, because the mark is the only sign the
work is happening. A leading icon or vendor mark stands down with the
words; the glyph form has no pill, so the hourglass takes the bare touch
target where the glyph was, at the 24px grid that glyph stood on.

Until revision 101 the mark was `…` — on the button, the switch and the
box alike — which is also the mark nokre elides text with and the mark a
"More" control carries: three meanings on one glyph, and a reader had to
be told which one a control meant. An hourglass means waiting without
being taught.

`accessible_name` is what assistive tech is told the button is called,
where the drawn words are not enough on their own. Empty — the default
and the ordinary case — means the words are the name.

It exists for one shape: a column of rows each ending in the same verb.
"Remove" beside every member is the right thing to *read* and an
ambiguous thing to *say*, so the audit's `duplicate_interactive_label`
rule refuses it. Before revision 101 the only way out was to put the
disambiguation on screen — "Remove — bob@…" in every row, a column of
noise restating what the row already says.

```zig
try row.button(.{
    .label = tr(.remove),
    .accessible_name = try app.tree.fmt("{s} \u{2014} {s}", .{ tr(.remove), member.address }),
    .on_press = .bind(remove, state),
});
```

It never *replaces* the words. It is an accessible name, so it must
contain them — WCAG 2.5.3, so a voice-control user can say what they can
see — and `append` refuses a name that does not
(`error.NameOmitsVisibleLabel`), as it refuses one on a button with no
words. The words are still what is drawn, measured and wrapped; nothing
about the pill changes.

Everything that asks an element what it is called gets this name:
`Element.label`, the a11y snapshot, both substrates' markup (`aria-label`
on the web), the audit's uniqueness rule, and the harness's locators.
`Element.visibleLabel` is the reader for the drawn words, and it is the
only place the two ever differ. What the locators do with the pair is
[testing.md](testing.md#queries).

The button stops activating — tap, Enter, and Space all pass over it, so
a second press cannot start the work twice — but unlike `disabled` it
**keeps its focus stop**. The user pressed this button, usually with the
keyboard; taking the stop out from under their own focus is the loss
WCAG 3.2.2 is about. Assistive tech is told what the pixels say: same
accessible name (the hourglass is a state, not a name — a voice-control
user keeps the phrase they were about to say), disabled *and* busy
(`aria-disabled` + `aria-busy`, AccessKit's `busy`), still reachable.

Setting both flags is allowed and is not a redundancy to reconcile: an
app deriving one from its form and the other from its work is doing the
normal thing. `in_progress` wins the pixels, `disabled` wins the focus
stop. In tests, `tap` on a button with work in progress fails with
`error.InProgress` rather than pressing nothing quietly.

```zig
// In the press handler: send the work, then say so.
app.tree.get(state.save_id).?.button.in_progress = true;

// In the reply handler, when it lands:
app.tree.get(state.save_id).?.button.in_progress = false;
```

Nothing clears it for you. nokre runs no timer and has no notion of what
your work is, so the state is yours to end — as ordinary a field as the
label beside it. Clear it on **every** path that ends the work, not just
the one that succeeds: a button cleared only by the success reply sits
at the hourglass forever the first time the work fails, times out, or is
cancelled, and it is the one control on screen that cannot be pressed
to recover.

`progress_percent` (0–100) is the same state with a number attached.
Set it and the hourglass gives way to a meter track in that same slot —
`meter`'s own geometry, centered, growing from the leading edge and
mirroring under RTL. The pill does not change size, fill, or tone: only
what stands in the middle changes, so a button at 0% is still visibly
the button, which is exactly what a pill that filled itself could not
manage. Leave it null when the work cannot say — the bare hourglass
means *no estimate*, and a bar moving on a guess is worse than no bar.

**The hourglass holds until the fill can be seen.** A track with
nothing in it reads as *disabled*, not as working, and at the low end
of a percentage that is exactly what a bar is: at 0% an empty pill, and
just above it a sliver. So below the point where the fill would be at
least the track's own corner radius wide the button keeps the mark it
would carry with no number at all, and the bar takes over the moment
there is a bar to read. The floor is the radius rather than a chosen
number because below it the fill cannot draw its own end cap — it is a
dot, not a bar. Which *fraction* that is falls out of the pill's width,
and should: a narrow pill needs a bigger number before a bar means
anything. Both substrates ask one function
(`layout.buttonProgressReads`), because the DOM one sizes its fill in
`%` and has no pixels of its own to check.

The two tone pairs are the palette's, not a choice: inside the filled
pill the track is `.g7` with a `.paper` fill, because `g7` is the only
step clearing WCAG 1.4.11 (3:1) against the `ink` ground *and* against
the fill inside it in both appearances; the outlined pill sits on the
ambient ground and so reuses a standalone `meter`'s proven `.g11` track,
`.g6` boundary, `.ink` fill. A **disabled** button keeps its hourglass even
with a number set: 1.4.11 exempts inactive components, which is the only
reason the pill may dim at all, and a dim pill is not a ground a meter
can be read on.

Rejected at `append`: a percentage without `in_progress` (it measures
nothing), past 100, on the glyph form (a bare glyph target has nowhere
to read a bar), or on a `provider` button (no vendor sanctions a bar
inside their artwork). Mutating into any of those afterwards is the
audit's `malformed_progress`.

The words and the accessible name do not change. Assistive tech gets the
number as the node's *value* — "Save changes, 60%" — rather than a
`progressbar` role the node cannot have while it is a button: the same
trade `meter` makes, where the state is in the words and the fill only
restates it.

```zig
// From a worker's progress reply:
const btn = &app.tree.get(state.save_id).?.button;
btn.progress_percent = pct;   // in_progress already true

// And when it lands — clear both; a number outliving the work is
// what `malformed_progress` catches.
btn.in_progress = false;
btn.progress_percent = null;
```

The pill forms carry an optional Lucide glyph as their payload —
`.form = .{ .filled = .alarm_clock_plus }` or
`.{ .secondary = .refresh }` — drawn inside the pill, leading the label;
both stay visible. An icon never hides the words by itself; the pill
just grows by one glyph advance. A pill with no icon says so with
`null`: `.{ .secondary = null }`.

`.glyph` drops the pill: only its glyph renders, quiet on the ambient
surface, centered on the standard 44px touch target — the exact
control framework chrome already uses for Back and the sheet close,
opened to consumers. The glyph *is* the payload
(`.form = .{ .glyph = .chevron_right }`), so a glyph form without one
cannot be written, and there is no pill for an emphasis to vary.
Nothing else changes — the label stays mandatory, is what assistive
tech announces, and is how tests reach it (`tapLabel("Next cycle")`);
disabled dims the glyph as the pill dims its text. Reach for it where
a compact repeated control sits beside the words that explain it — a
prev/next pager flanking a heading, a row's trailing action. A glyph
button whose meaning isn't obvious from its surroundings should have
kept its words — the labeled pill is the default, the bare glyph is
the exception.

`.provider` makes it a conforming vendor sign-in button: the vendor's
mark leads the label — occupying the glyph slot, which is why the type
offers no icon beside it and no glyph-only sign-in — and the label
stays yours to supply. `append` rejects an empty one
(`error.AuthButtonNeedsVendorLabel`), because nokre ships the mark and
no translation of the vendor's mandated string (see the localization
note below). This is the one place in nokre where the visual spec is
**not nokre's to choose** — every detail of these buttons is the
vendor's, which is exactly why the vendor style is the whole API.
There is no size, no ink, no corner radius: a knob here would be an
invitation to violate the guidelines the button exists to satisfy.

```zig
try b.button(.{
    .label = "Sign in with Apple", // the vendor's published wording, your locale
    .form = .{ .provider = .apple },
    .on_press = .bind(State.startSignIn, state),
});
```

Nothing else changes. Role is `button`, activation is a plain button's,
the label is what assistive tech announces and how tests reach it, and
the mark is decorative — it carries no accessible name of its own, so it
is hidden from assistive tech and exempt from the contrast gate, the same
rule an unlabeled `icon` follows. It does **not** mirror under RTL: a
logotype is not directional, the same reason a `qr` symbol never flips.
Its *position* does mirror, because leading is leading.

The vendor styles are spelled out per vendor instead of composed from
an emphasis flag. Apple sanctions three — black, white, and white with
a black outline: `.apple` is the filled pair (the black button in
light appearance and, because the endpoints flip, the white one in
dark) and `.apple_outlined` is the outlined third. Google sanctions
*themes* rather than emphases — a light button (white, hairline
border) and a dark one — so the appearance picks the theme and the
outlined Google button no guideline describes is simply not a member
the type has.

The Google button's G is drawn in the vendor's four colors — the one
colored thing nokre ever puts on screen, painted by the renderer from
its own table. Nothing about it is yours to configure, which is the
`provider` field's whole design: there is no color API here or anywhere
else, and your app remains grayscale-only. The decision record — this
was a refusal for a long time, and reversing it meant widening the
frame format itself — is in [internals/oauth.md](internals/oauth.md).

One thing this does not do for you. **Localization**: the vendors
require their mandated string translated to the app's language, and
nokre ships no translation of it — inventing one would be fabricating a
mandated string. A translated app sets `label` itself, to the vendor's
own published wording for that locale.

The marks themselves are not nokre's work and are not covered by its
license — see
[LICENSE-Brand.txt](../src/assets/fonts/LICENSE-Brand.txt).

#### The folded tail (`More`)

Put actions in a horizontal `stack` and nokre shows as many as fit. When
they don't all fit, the row **folds**: the last completely visible one
gives up its slot to a control labelled "More" (the framework's own word,
`App.Chrome.more` — see [localization.md](localization.md)), and pressing
that opens a sheet holding it and everything after it, in the row's own
order.

This is not opt-in and takes no setup — no flag on the stack, no wrapper,
no width to declare. Any row of actions you have already written folds
the moment it runs out of room.

```zig
const row = try b.stack(.{ .axis = .horizontal, .gap = 8 });
try row.button(.{ .label = "Publish", .on_press = ... });
try row.button(.{ .label = "Save draft", .on_press = ... });
try row.button(.{ .label = "Archive", .on_press = ... });
try row.link(.{ .label = "More details", .route = "details" });
// Narrow enough, this renders: Publish · More
```

There is no API for it — no `overflow` knob, no "collapse at" width, no
way to nominate which action folds first. How many actions a row can show
is the framework's decision, like the nav's shape: you declare them,
nokre draws as many as the viewport allows and reshapes as it changes.

**What counts as a row of actions:** every child is a `button` or a
`link`. Those are the two press-me leaves whose whole state is what they
call or where they go, so the sheet can restate one *whole* — same
action or route, same emphasis, same disabled and in-progress state — and
the press means the same thing in both places. A `toggle`, `checkbox`,
`select`, or field keeps its state in the node, and a restatement of one
would take the press and leave the original saying the old thing.

Anything else in the row and it doesn't fold: two arrows with a month
between them is a pager, not a menu, and folding "March" behind a control
named for having more would be nonsense. A row of one action doesn't fold
either — that hides the only action twice. Those rows
[wrap](#a-row-too-narrow-for-its-children) instead, which is the other
half of the same rule.

The fold is deliberately one action deeper than the overflow itself. The
one that was already half off the screen is not the one to replace:
put the control there and it stands at the very edge it exists to
rescue, and the row reads as two failures at once.

Details worth knowing:

- **Folded is gone, not dimmed.** A folded action draws nothing, takes no
  tap, keeps no focus stop, and is invisible to assistive tech. Tab goes
  from the last standing one to More.
- **Your nodes survive.** The actions stay in the tree with their ids and
  their state; a wider viewport puts them straight back. Mutating a
  folded button (`in_progress`, `disabled`) is fine and shows up when it
  returns.
- **Focus follows the shape.** If the action you were on folds away,
  focus lands on the control that now holds it; when the row grows back,
  focus moves off the departing control to the row's trailing end
  (WCAG 3.2.2).
- **Pressing an action in the sheet pops it first, then runs the
  action**, the way choosing a row closes a picker — unless the press
  did nothing (disabled, or work already running), in which case the
  sheet stays where it is. The order matters inside a sheet: the row's
  own sheet stands again before the action runs, so a Cancel found in
  the tail closes the sheet it was declared in, not the tail. On a
  screen the last sheet's departure rebuilds the screen, and that
  rebuild lands after the action, from the state the action wrote.
- **Inside a sheet too.** A row of actions inside a sheet folds like a
  screen's, and its tail is a sheet stacked over the one it is in
  ([the sheet stack](#sheet)). The covered sheet's node goes while the
  tail stands — the tail lists copies, restated whole as always — and
  is rebuilt from state when the tail goes. Esc from the tail returns
  to the sheet with the row, the keyboard on its `More` control once
  layout has folded the row again: the same place Esc from a screen's
  tail returns it to.
- **The sheet closes if what it lists stops being true.** The window
  grew and the actions are back on the row; it folded deeper and the
  open list no longer names everything hidden; or a folded original
  changed *state* — its words, `disabled`, `in_progress`, progress,
  form (emphasis, icon, or provider mark), a link's destination, or the action
  itself. The sheet restates each action whole, so on any of these it
  is dismissed rather than left saying something untrue. A screen's
  row can move under its tail this way; a sheet's row went with its
  sheet's node, so its tail goes on the first re-present instead — a
  `refresh` under it — and the sheet with the row answers the state.
- **In tests**, a folded action is not addressable by its words:
  `getByLabel` reports it as folded, and `tap` on a node id you kept
  fails with `error.Folded`. Reach it the way a user does — `tapLabel("More")`,
  then the action.

### `link`
`label` + exactly one destination: `route` or `external`. Underlined.
Links never carry arbitrary actions; if you want an action, use a
button. The `route` is a reference: a route name, optionally with
arguments (`note~42`, see [routing.md](routing.md)) — same for every
other `route` field below. `external` is a URL handed to the system
browser on activation, held to the [open_url](services.md) scheme
allowlist (https/http/mailto) at `append`; it draws identically to a
routed link, because where a link goes is semantics, not a visual
variant. Setting both, or neither, is rejected at `append`.

`lang` says which language the `label` is in, where it is not the
document's — `Span.lang` above has the whole argument, and this is the
element a site's footer language row is actually built from (a `stack`
of `link`s, [static-sites.md](static-sites.md)). Same tag, same grammar
at `append`, same DOM-only effect: it lands on this anchor's own `lang`.

### `toggle`
On/off state as an iOS-style pill switch: `label`, `on`, `on_toggle`,
`in_progress`. Flipped by tap/Enter/Space; the change applies
immediately — a toggle never needs a submit button beside it, and one
whose change has to reach a server before it is true says so with
`in_progress` rather than borrowing one. On: `.ink` track, `.paper` knob
at the trailing edge. Off: dimmed `.g11` track, knob at the leading
edge, both outlined `.g6` — as in `segmented`, the border is what
carries the WCAG 1.4.11 state. Semantics: a switch (announced on/off),
not a checkbox — a choice that waits for a submit control is a
`checkbox`. The row is `metrics.touch_target` (44px) deep — the switch
and its words centered in it — because the 20px track is the whole
affordance and a one-line row would leave it at the WCAG floor; it
matches the tile rows in `radio_group` and the select picker. Stack two
of these (or a toggle and a checkbox) and the flow gap between them
collapses: each already carries its own padding, and counting the
stack's gap on top would hold them three gaps apart. Anything else
beside one — a pill, a field — keeps the full gap.

`in_progress` is `button`'s state on a switch, and it differs from the
button's in exactly one place: what stands down is not the words but the
**switch**. A button's words say what the press will do; a track says
what the value *is*, and while the work is in flight neither is
knowable. So the track and its knob give way to the hourglass — the
button's mark, the same reason — in the slot they occupied, at the size
layout already gave
the row. Nothing else changes: the words stay where they were, the row
keeps its height and width, and the flip does not reflow the screen out
from under the finger that made it. It does not dim; busy is not
unavailable.

The switch stops flipping — tap, Enter, and Space all pass over it — but
**keeps its focus stop**, for the reason `button`'s does. Assistive tech
hears the same pair (disabled *and* busy, still named, still reachable)
and, unlike the button, still hears the **value**: the mark is a
rendering, and a reader who cannot see it is owed the state the app
still holds. In tests, `tap` fails with `error.InProgress` rather than
flipping nothing quietly.

```zig
// In the toggle handler: the flip is a request, not a fact — put the
// value back where the server still has it and say work is running.
const t = &app.tree.get(state.notify_id).?.toggle;
t.on = !wanted;
t.in_progress = true;

// In the reply handler: clear it on every path that ends the work, and
// move the value only on the one that succeeded.
t.in_progress = false;
if (ok) t.on = wanted;
```

Nothing clears it for you, and a switch left at the hourglass is worse than a
button left there: it is the one control on the row that cannot be
pressed to recover. Clear it on failure and cancellation too.

There is deliberately no `progress_percent` twin: a 20px track has
nowhere to read a bar, which is the same reason a glyph-form button is
refused one.

`disabled` arrived in revision 107, reversing "a switch that cannot be
flipped at all is a screen that should not be drawing one". The reason it
was wrong: a screen full of settings where one row is off *is* a screen,
and the alternative was hiding the row — which loses the fact that the
setting exists. **The knob keeps the end it is on**: a switch's position
is its value, and a value stays information after it stops being
changeable. The track and knob mute together
([`disabled`](#turning-a-control-off-disabled)) rather than emptying, which
is what `in_progress` does above and for the opposite reason — in flight
the value is not knowable, and here it is.

### `checkbox`
On/off state as a square check box: `label`, `checked`, `on_toggle`,
`in_progress`. The same interaction as `toggle` — flipped by
tap/Enter/Space — but the
opposite contract: checking commits nothing by itself; the choice waits
for a nearby control to gather it (consent-then-submit, picking members
from a list). If flipping it takes effect immediately, it should have
been a `toggle`. Checked: `.ink` box with a `.paper` check glyph.
Unchecked: dimmed `.g11` box outlined `.g6` — the toggle/segmented
WCAG 1.4.11 pattern. There is no indeterminate state; a "some of these"
summary is a screen problem, not a control problem. Semantics: a
checkbox (announced checked/unchecked). Its row is 44px deep for the
same reason `toggle`'s is.

`in_progress` is `toggle`'s, box for track: the box and its mark stand
down for the hourglass in the slot they had, with the same lockout, the same kept
focus stop, and the same busy announcement. It is the rarer of the two,
because checking commits nothing by itself — but a box whose row is
gathered the moment it is ticked has work in flight like any other, and
nothing else on the row can say so.

`disabled` is `toggle`'s too, and keeps the tick for the same reason the
switch keeps its knob's end
([`disabled`](#turning-a-control-off-disabled)).

### `radio_group`
The same exclusive-choice semantics as `segmented` in a different form:
a full-width tile group under a visible group label (small scale, like
`text_input`'s) — a rounded 1px `.g10` border around 44px option rows,
one hairline between them. Same fields — `label`, `options` (2+),
`selected`, `on_select`. One tab stop (focus takes the group's own
border, not the label); ↑/↓ (and ←/→) move the selection and commit
immediately; tapping a row selects it. Reach for it when every option
should stay visible at once — a choice made once and submitted — where
`segmented`'s scrolling track would hide some. The
group border is grouping, not state: the selected row's filled circle
with a paper dot (unselected rows show a `.g6` ring) carries the
selection.

`disabled` turns the whole group off — one flag, because the group is
one tab stop and one choice. The card's border and its hairlines stay
where they are, being grouping; what recedes is the label, the option
words and the rings
([`disabled`](#turning-a-control-off-disabled)).

### `ranking`
An order the user sets over a fixed set, with a divider plate above
which items count, inside a band the app sets. Fields: `label`;
`options` (2+), given *in their current order* — the app owns the order
the way it owns a `radio_group`'s `selected`; `viable`, how many of
them count, which is also where the divider plate sits: after that
many items; `viable_min` (default 0) and `viable_max`, the band the
divider may land in; `divider`, the plate's words; and `on_swap(a, b)`,
called with two slots. `viable_max` must be strictly below the option
count — passing the count or more is a construction error, by design:
a divider nothing can fall below is no divider, and an app that wants
one meant a plain ordered list. The divider's words are the app's
because the number they carry and the language they are in are both
the app's ("Up to 5 count. Items below this do not.").

The device is two columns under a small label: a column of plates on
the leading side, one per slot, and a column of equal 44px swap
buttons on the trailing side. The slots are every option plus the
divider, top to bottom, so a five-item ranking has six of them.

**Swap is the only verb.** The buttons are empty at rest — the
unchecked box's look, a `.g11` plate outlined `.g6`, which a reader
already knows takes a press; a glyph at rest was tried and read as
noise, or as a radio button. Pressing a slot's button arms it — the
button inverts under the swap glyph, and that is the whole of the
mark: a sign on the plate as well was tried and read as the same state
said twice; pressing
another slot's button swaps the two and fires
`on_swap`; pressing the armed one again disarms. The divider is a slot
like any other, so moving it is swapping it with an item. Rows never
move: the picture after a swap differs from the picture before in
exactly two rows, and nothing slides. That is why the app receives two
slots and not a new order, and why `Ranking.applySwap` exists — two
items swap, but an item and the divider *rotate*: the divider is not in
`options`, so the items between the two shift by one to make the
picture where only two rows changed. The app applies the pair to its
own copy of the state with `applySwap` rather than by its own
arithmetic; it is the same arithmetic the element has already run on
the tree's copy, so the two cannot disagree, and a stale pair from a
screen that has since rebuilt is a no-op rather than a corrupted order.

**The band.** The divider may only land where `viable_min <= viable <=
viable_max`. At rest nothing marks it — the divider's own words are
where an app says it. While the divider is armed the buttons of the
slots it may not take are **gone** — nothing drawn, the page showing
through — which is the cap made visible at the moment it applies; and
while an item is armed whose slot the divider may not take, it is the
divider's button that is gone, the same rule read from the other end.
A button that cannot be pressed is honest as absence where a dimmed
one read as a smudge, and this is where the device stops imitating
hardware: a real panel cannot lose a button, and a screen should not
lie about state to keep the resemblance. The rect stays: pressing
where the button was moves the keyboard cursor there and nothing
else.
`viable_min == viable_max` is legal — a fixed count — and pins the
divider's button disabled, so the items still reorder around a line
that stays put.

**Every plate is the height of the tallest.** The divider's sentence
wraps where an option's name does not, and a row that changed height
when swapped would move every row under it, so layout measures all the
plates and gives each the maximum. The band a plate reserves for its
ordinal is reserved on every plate for the same reason: a band that
came and went with the rank would rewrap the words.

Counted plates are lit — `.paper` under `.ink` words, outlined `.g6`,
the selected chip's pair — and uncounted plates are unpowered: the
`.g11` track fill under `.dark` words, the pair `segmented` already
proves legible. The divider plate is neither, `.paper` under `.dark`
words inside the `.g10` *grouping* edge, because it is the device's
own caption and not a state. Dimming is not the only carrier of
counted-ness: counted plates lead with their ordinal, in the app's
digits, and an uncounted item carries none — an item below the divider
has no rank, and that absence is the fact assistive tech hears, so no
plate ever spells "not counted" in words the library would have to own
in every language ([accessibility.md](accessibility.md#derivation)).

One tab stop. ↑/↓ move a cursor between slots without committing
anything; Space and Enter press the cursor's button; Esc disarms;
leaving by Tab disarms — an armed button whose partner press can no
longer come from the keyboard is a promise nothing on screen can keep.
Tapping a plate only moves the cursor there. A pinned divider is no
stop at all: the cursor steps over it, a tap on its empty button lands
on the slot above, and its words reach assistive tech as a caption
inside the group instead — the cut it marks is audible from the ranks
anyway, since the first item read without one is the first below the
line. `cursor` and `armed` are
the device's own state, written by input and read by both substrates,
and `append` refuses them set by hand (`error.InputOwnedField`), so an
app cannot build a screen that opens mid-swap. A `reload` inside
`on_swap` carries the cursor slot the way it carries a text field's
caret ([routing.md](routing.md)), vetted against the rebuilt device's
slot count.

`disabled` turns the whole device off — one flag for one tab stop,
like `radio_group`'s. It draws in the [shared off
vocabulary](#turning-a-control-off-disabled): the label, the ranks and
the words recede, the lit plates and the buttons give up their state
edge, an armed button stays armed under the muted pair. Plate fills
and the divider's grouping edge do not move: an order is a value, and
it stays legible after it stops being changeable.

The construction errors, by name: `error.RankingNeedsTwoOptions`,
`error.RankingEmptyOption`, `error.RankingNeedsDivider`,
`error.RankingMaxNotBelowCount`, `error.RankingBandInverted`
(`viable_min` above `viable_max`), `error.RankingViableOutsideBand`,
and `error.InputOwnedField` above.

```zig
const Order = struct {
    // Mutable: `applySwap` reorders it in place.
    items: [4][]const u8 = .{ "Alpha", "Bravo", "Charlie", "Delta" },
    viable: usize = 2,
};

fn reorder(order: *Order, a: usize, b: usize) void {
    nokre.element.Ranking.applySwap(&order.items, &order.viable, 0, 3, a, b);
}

try b.ranking(.{
    .label = "Ballot",
    .options = &order.items,
    .viable = order.viable,
    .viable_max = 3,
    .divider = "Up to three count. Items below this do not.",
    .on_swap = .bind(reorder, &order),
});
```

Reach for it when the answer is an order over things the app already
knows — a ballot, a priority list. A choice of one is `radio_group`;
reordering that needs a drag is not something nokre draws.
Hold-and-drag was considered and deliberately left out for now: it
costs a pointer stream the input model does not carry, and on touch it
competes with the scroll the page is already listening for. A swap
reaches every order a drag reaches, two rows at a time.

### `text_input`
Single-line. `label` is mandatory and rendered above the field (small
scale). `value`, `placeholder`, `cursor` (byte offset), `on_change`,
`on_submit` (Enter — and wiring it also *labels* the key on the three
platforms with an on-screen keyboard: Android's return key reads
"Search", iOS's takes the Search return type, and the web's field gets
`enterkeyhint="search"`. A field with nothing wired promises nothing,
which is why the label follows the action rather than a flag).
The field does not scroll sideways: a value or a
placeholder wider than it is cut at the outline, never painted past it.
`composition` holds in-progress IME text, rendered dark
with an underline, and `composition_cursor` is where the IME's own caret
sits *inside* it — during a CJK conversion the user moves back through
the reading to fix a syllable, so the caret is drawn there rather than
at the end of the run. Both are written by core from the shell's events;
a builder sets neither. IME is live on every platform, the web included
([internals/platform-shells.md](internals/platform-shells.md) has the
per-shell contract).

#### Editing, and what a selection is here

A field carries a `cursor` and an `anchor`, both byte offsets. The
anchor is `null` for a plain caret — a field that says where the caret
goes and nothing else holds a caret — and an offset when there is a
**selection**, which every operation is then written in terms of:
typing, a paste, an IME commit, Backspace and Delete all *replace* it.
Both are the app's to set (`.anchor = 0` with the cursor at the end
opens the field selected) and both are clamped to the value at every
door they arrive through, so a stale offset from a rebuild or a shell
can never split a character. Read the pair back with `selection()`,
which orders it.

Motion and deletion step by **grapheme cluster**, not by codepoint: `e`
plus a combining accent is one Backspace, and so are a flag, a keycap
and an emoji family. Words are the platform's word semantics — letters
of any script, digits (Persian ones included) and `_` are word
characters, and everything else is a break.

The keys, by name rather than by chord, because the chord is each
platform's and the shell maps it (`docs/internals/platform-shells.md`):
←/→ and Home/End move; Shift extends instead of collapsing; a plain
←/→ over a selection collapses it to that end without moving further;
`word_left`/`word_right` move a word; `delete_word_backward`/
`delete_word_forward` take a word, or the selection when there is one;
`select_all`, `copy`, `cut`, `undo`, `redo`; Escape ends an IME
composition, or — with none — collapses the selection.

**Undo is per field and bounded.** A run of ordinary typing folds into
one entry, so taking back a word is one press; a space, a deletion, a
paste and an IME commit each open the next. The stack is forgotten when
the keyboard leaves the field, because undo everywhere on a screen is a
verb nobody can predict.

On touch, a **long press** inside the field selects the word under it,
raises two grab handles under the ends of the range, and opens an edit
row — Cut, Copy, Paste, Select all, framework chrome in the app's
language, with Cut and Copy simply absent while nothing is selected. A
secondary click on a desktop opens the same row. Dragging a handle
moves that end; dragging from a press inside the field selects from
where it landed.

**Paste is the platform's verb, never a read.** The row's Paste asks
the shell to paste; the shell reads its own clipboard on that action
and delivers the bytes as ordinary text input. There is no call that
answers what is on the clipboard ([services.md](services.md)).

A selected run is drawn as a `.g6` band with its glyphs at `.g11` — the
same two tones a selected chip and an off control spend — and the web's
`::selection` uses them too.

While the field holds focus, a pointer release that lands on nothing
interactive clears it, and on-screen keyboards follow focus down. A
keyboard rising shortens the visible area rather than covering it, and
the field is revealed into what is left — through its own scroll region
first, then the window — so typing never happens under the keys. That
is dismissal without spending a pixel of chrome — no Done bar, no
tap-catching scrim — the least intrusive answer, the same restraint
that keeps content from scrolling itself.

`obscured` makes it a password field: every codepoint (composition
included) renders as a bullet at a fixed advance, and the value is
withheld from assistive tech (announced as a secure field) and from
test traces. Editing, placeholder, and caret behavior are unchanged —
it selects and deletes like any other field, because someone fixing a
mistyped password needs the same motions everyone else has. **Copy and
cut carry nothing off it** (silently, like every inert key): the whole
of the flag is that the value does not leave, and the clipboard is
where it would. The placeholder stays plain — it is a hint, not the
secret.

#### `problem`: what is wrong with the value

`problem` holds the reason the field's value was refused, in your own
words. Empty is the ordinary state; any words at all make the field
**invalid**. The message hangs under the field's outline at the same
gap the label stands above it — small scale, full ink, no mark — so
the label, the field and the reason read as one thing.

```zig
try b.textInput(.{
    .label = state.tr(.email),
    .value = form.email.get(),
    .problem = if (form.rejected) state.tr(.emailNotAnAddress) else "",
    .on_change = .bind(onEmail, state),
});
```

nokre validates nothing and has no opinion about what a valid value
is. What it owns is the *association*, and the association is the part
you cannot build from outside: a message appended beside a field is
prose that happens to sit nearby, and prose carries no relation — no
`aria-describedby`, no `aria-invalid`, nothing an assistive technology
can follow from the control to the reason. Both substrates state the
pair; how each backend spells it, and where the reason falls in the
announcement, is
[accessibility.md](accessibility.md#derivation).

A field with a problem is **not disabled and not busy**. It takes every
keystroke it took before — a control the user cannot edit is a control
that traps them in the value that was just refused. That is the whole
difference from `Button.in_progress`, which really is both.

Two things that are not this field. A failure that belongs to the
*form* rather than to one of its values — a rate limit, a server that
declined, a permission the account lacks — is not a field error; it is
either the screen's own prose or a [notice](#notice), and putting it on
an arbitrary field would point the user at a value that is fine. And
the framework never writes these words: an empty-looking problem (only
spaces) marks the field invalid with nothing to say, which the
[audit](testing.md) fails as `wordless_problem`.

#### `disabled`: not yours to type into right now

`disabled` is `Button.disabled` for the element that holds a value: the
field leaves the focus order, takes no keystroke and no tap, and every
backend announces it not operable. It is for the field that toggles
between editable and not **within one layout**, driven by state — the
submit-in-flight case, where the form has sent what the field holds and
the field must stop taking edits until the answer lands.

```zig
try b.textInput(.{
    .label = state.tr(.verificationCode),
    .value = form.code.get(),
    .disabled = form.phase == .verifying,
    .on_change = .bind(onCode, state),
});
try b.button(.{
    .label = state.tr(.verify),
    .in_progress = form.phase == .verifying,
    .on_press = .bind(onVerify, state),
});
```

Without it the only honest thing an app can do is leave the value fully
editable while it is already on the wire: the user goes on typing into
bytes the server has, and what they end up looking at is a value
nothing will ever act on.

It draws in the [shared off vocabulary](#turning-a-control-off-disabled),
which for a field is two of its three steps: the label at `.g6` and the
outline at `.g10`, applied to the two parts that are affordance — the box
that says "type here" and the label naming what would be typed. The
placeholder goes with them. The **value does not**: it stays at full ink,
because this state exists precisely while that text is on the wire, and
dimming the one thing worth checking would make the pattern hardest to
read at the moment it matters.

**Not for a value that is settled.** A value that is not editable and
never becomes editable in that layout is ordinary [text](#text) with an
Edit button opening a real editing flow. A permanently disabled input
offers an affordance it will never honor; this field's whole shape is
that it is temporary and it ends. There is deliberately no `readonly`.

`disabled` and `problem` never meet. The honest sequence is one frame
wide: the form disables on submit, the server refuses, and the field is
re-enabled *and* given its problem together. A field that says what is
wrong and refuses the correction is a dead end no keystroke leaves, and
the [audit](testing.md) fails the pair as `unfixable_problem`.

### `text_area`
Multi-line `text_input`: same fields minus `on_submit`, because Enter
inserts a newline — a field that swallows Enter to submit loses the one
key a multi-line editor cannot give up. Submission belongs to an
explicit `button` next to it.

The value wraps exactly like prose (greedy, word-boundary, hard `\n`
breaks, and a word wider than the line broken at the edge rather than
drawn past it) and the field grows with its content, never below three
rows. **By default it keeps growing and the page scrolls** — an inner
scrollbar fighting the page's own is what that default is protecting.
`max_rows` caps it, and a capped area scrolls inside; the cap wins over
the three-row floor, so a field asking for two rows gets two. Cap the
field whose value is not prose a person typed — a pasted key blob, a
log, an import — where growing to content pushes the form's own submit
button off the screen. The window follows the **caret**, not a bar
somebody drags: ↑/↓ is how a reader moves it and the wheel still
belongs to the page, so the default's reason survives the exception.
The indicator is the same quiet one a `scroll_region` draws. ↑/↓ move
the caret between visual lines preserving its horizontal position;
Home/End go to the bounds of the caret's line (the whole value is a ↑/↓
walk away), and Shift extends the selection across either, so a range
spans wrapped lines and is drawn as one band per line it crosses.
Everything else — the range model, cluster and word motion, undo, the
edit row and its handles, placeholder, IME composition — matches
`text_input`, `problem` and `disabled` included:
the words hang under the field the same way, the field is announced
invalid the same way, and a multi-line value goes on the wire the same
way. Semantics: a multiline text field carrying the value.

### `select`
An exclusive choice among many options, in `text_input`'s clothing: the
same labeled-field geometry, showing the current option with a chevron
affordance. Same fields as `radio_group` — `label`, `options` (2+),
`selected`, `on_select`. Reach for it when the options are too many to
lay out in place; for a handful, prefer `radio_group`, which shows
every choice at once, or `segmented` for a choice the user switches
repeatedly.

`disabled` takes the disabled *field*'s treatment rather than the pill's,
this being a labeled field: label and outline dim, and **the chosen
option keeps full ink**. What dims beside them is the chevron, which
promises a picker that no longer opens
([`disabled`](#turning-a-control-off-disabled)).

Activation (tap/Enter/Space) opens the framework's picker: a modal
bottom panel with the select's label as its title and one 44px tile row
per option — hairline-separated, like `radio_group`'s rows — scrolling
when they overflow. It uses the sheet's geometry and
scrim and may stack above an open sheet. The current option is
focused on open and rendered as a dimmed `.g11` chip with a 1px `.g6`
border (the `segmented` pattern); ↑/↓ move between rows without
wrapping, Enter/Space or a tap commits — closing the picker, updating
the field, and firing `on_select`. Esc or a tap on the scrim closes
without committing. Focus always returns to the field. Nothing is
committed until a row is chosen, unlike `radio_group`'s immediate
arrow-key commits — a closed dropdown is a promise, an open list is
a preview.

Long lists (8+ options) get a filter: a labeled `text_input` pinned
between the title and the rows, focused on open — a list that long
wants typing, not scanning. Typing narrows the rows to the options
containing the query (ASCII-case-insensitive substring); a query
matching nothing leaves the words "No matches" where the rows were.
The picker keeps the full list's height while the rows come and go, so
the field never moves under the typing. This is framework chrome, like
the picker itself — there is nothing to configure and no API. Short
lists stay bare: fewer than eight rows scan faster by eye than by
typing, and open with the current option focused as before.

Semantics: the field is a combo box carrying the current option as its
value; the picker is a modal dialog of option rows with selection
state, its filter a plain labeled text field. There is no multi-select;
if a choice needs more than one answer, the screen wants rethinking
more than the widget wants features.

### `copyable`
A verbatim value the user carries away — a recovery code, an invite
link — in `text_input`'s labeled-field clothing: `label` above, `value`
in mono inside the field, a copy glyph at the trailing edge. Both are
mandatory; `append` rejects an empty value — a control that copies
nothing cannot exist. One tab stop; activation (tap/Enter/Space) writes
the value to the platform clipboard through the shell — the behavior is
intrinsic, there is no action to wire.

So is the reaction: the copy glyph becomes a check, and stays one until
the next input. A copy leaves the screen identical, so without a mark
activation looks inert — and the screen cannot supply the mark either,
because clearing it after a moment needs the wall-clock timer the
deterministic core refuses. It latches instead, exactly as the scroll
indicator's emphasis does. Only one control in the app is ever marked:
copying somewhere else moves the mark there. Activating the marked
field copies again and returns the glyph — with no animation to replay,
the mark leaving is the only visible sign the second copy happened, and
a check that just sat there would read as a dead control. The glyph's
slot is reserved at the wider of the two marks, so nothing under it
moves when they swap. Assistive tech hears "Copied" from a polite live
region on the field, arriving and leaving with the mark.

**No `disabled`.** Copying is intrinsic — there is no action to wire,
so there is nothing an app could be withholding — which makes `copyable`
the one interactive kind the
[off rule](#turning-a-control-off-disabled) does not reach.

Not an editor — the value cannot be changed in place; a value that
needs editing is a `text_input`, and prose worth reading is `text`.
A value wider than the field elides in the middle (`ab…yz`, marker
dimmed): both ends survive because both ends are what a human checks a
pasted value against, and the display is only a receipt — activation
copies the whole value, semantics announce it whole. Semantics: a
button named by the label, carrying the value — assistive tech hears
both.

### `tile_group` / `tile`
A bordered vertical group of tappable rows — the list-row form of
`button` and `link`. `tile_group` children must be `tile`s; a tile
anywhere else is rejected at `append`. The group draws `radio_group`'s
geometry — a rounded 1px `.g10` border, 44px rows, one hairline between
them — but here the border is pure grouping: no selection, no state.
An optional `description` hangs below the border in dimmed small print,
wrapped at the group width: the group-level counterpart of a tile's
`detail`, for a caption that belongs to the set of rows rather than any
one of them. Assistive tech hears it as the group's value.

Each `tile` is its own tab stop carrying `label`, an optional dimmed
`detail` line beneath it, and
either a `route` or an `on_press`: a `route` tile renders a trailing
chevron and navigates like a `link`; an `on_press` tile acts like a
`button`. Its accessible role follows the same split. Exactly one of
the two, held at `append` the way a `link`'s destinations are: setting
both, or neither, is rejected — with both the route wins and the press
is never called, and with neither the row is a tab stop that answers
nothing. Focus is the picker's pattern — a heavier stroke hugging the
row — because an outset ring would collide with the separators.

`disabled` is per row, and off on whichever half the row wired: a
`route` tile navigates nowhere and an `on_press` one runs nothing. The
whole row recedes together — label, detail, leading mark, trailing chip
and chevron. **The chevron stays**: it says where the row would go,
which is still true of a row that is not going there now. The group's
border and its hairlines do not move
([`disabled`](#turning-a-control-off-disabled)).

**Both runs wrap, and the row grows to hold them.** The column is the
row less its padding, its mark's band and its chevron's
(`layout.tileTextWidth`), and layout measures the row against the same
wrap the renderer draws, so a tile is as tall as its words and its words
reach neither its border nor the glyph that says where it goes. No
caller states a width or a line count: a `detail` that fits in English
and runs long in German is the ordinary case, and a row that could be
overrun would put that measurement in every call site. Until revision 95
the row was one line of each scale whatever it was handed, and the
overflow was painted past the group border and cut by the frame edge;
until 97 the column ran on past the chevron, so a routed row's last
stretch of words was the glyph's. The DOM substrate never had that
second one — there the chevron is a `flex: none` sibling with the row's
gap in front of it — which is why the two substrates had to be measured
against each other rather than argued about.

Because exactly one of the two is set, the split is total, and it
reaches further than the chevron: **a routed tile is answered by the
browser, so a page made of them publishes as a file with nothing running
behind it** ([static-sites.md](static-sites.md), "Whether a page needs a
runtime is derived"). A hub or a section index built out of routed rows
costs its readers no module. One `on_press` row on the same page is a
control, and then the page needs an app.

An optional `icon` (any [`IconName`](#icon)) leads the row. It is
**decorative**: the `label` stays the accessible name, and the glyph
enters no accessibility tree at all — it is a field on the tile, not a
child node, the shape a `notice`'s icon has and for the same reason
(nothing there takes focus or answers a press). A row that announced
both would say its own name twice, and the second saying would be a
guess: no glyph means one thing, which is why naming a mark is
deliberate on the standalone `icon` element (its `label`) rather than
inferred anywhere. Ink and size are the row's — `.ink`, one body line —
so a mark adds no styling surface and nothing new for the contrast gate
to prove.

**All the rows of a group carry one or none**; a mixed group is rejected
at `append` (`TileGroupMixedIcons`), beside the destination rule. The
mark takes a fixed leading band — a `lineHeight` square plus the icon
gap, the same box whatever glyph it holds — so a group's words start on
one column, exactly as a `list`'s marker band makes its items do. Give
the band to some rows and not others and the column goes ragged, with
the rows that stepped in reading as subordinate to the ones that did
not. A `list` cannot have that bug because its markers are derived; a
tile group's are authored, so the check has to exist.

Reach for tiles where a screen is a list of destinations or row-shaped
actions (settings screens, detail screens). For an exclusive choice
among options, that is `radio_group`, not a tile group.


A row may carry a **`badge`**: a short status word — "Sent", "Draft",
"3 new" — drawn as the chip the `badge` element draws, on the row's
first line, inboard of the chevron, mirroring with everything else.
Unlike the leading mark it is **announced**: a glyph's meaning is a
guess and a word is not, so it reaches assistive tech as the row's
value after `detail`, joined with the library's own `, ` — "Write" is
the name, "Send anonymous feedback, Sent" the value. `""` is no chip
and nothing joined.

Its width comes off the row's **whole** text column, not off the first
line alone, which is the trade the chevron's band already makes: a
group reads as a column because every line of every row starts and ends
on one pair of x's, and letting a second line run under the chip to buy
back twenty pixels would cost that.

### `list` / `list_item`
An ordered or unordered sequence of peer items. `list` children must be
`list_item`s; a `list_item` outside a list is rejected at `append`.
Options: `ordered` (default false) and `start` (the first ordinal of an
ordered list, so a list resumed after a paragraph keeps counting).

**Markers are derived, never authored.** An unordered list takes the
bullet at every depth; an ordered one numbers from `start`. There is no
field to set one, so a list can never number itself wrongly, and no
marker ever contradicts the order assistive tech announces. The marker
sits in a leading band sized for the widest marker in the list and
right-aligned inside it, so every item's words start on the same column
even when the count crosses into double digits; a wrapped line hangs
under those words, never back under the marker. The band is leading, so
it mirrors under `App.setDirection(.rtl)`.

A `list_item` holds document blocks — `text` and nested lists — not
arbitrary content. A `heading` inside one would claim an outline
position the list cannot own, and a `table` reads as a mistake at list
depth; both are rejected at `append`. Nesting is capped at three levels,
also at `append`: past that the indent has eaten the line without saying
anything the words don't. Parsed Markdown flattens deeper levels onto
the third rather than failing, the way it rebases heading levels (see
[markdown.md](markdown.md)).

Items flow tighter than free-standing blocks — they are one run of prose
broken into pieces, not separate thoughts. A list draws no edge, so the
margin advice passes through it (see `stack`). Never interactive: a list
of destinations is a `tile_group`, not a list with links in it. The
audit fails a list with no items — `append` cannot catch that, since a
list is built before its items exist. Semantics: `list` / `listitem`;
assistive tech renders positions from the structure itself, so nokre's
derived marker stays out of the announced text.

### `blockquote`
An attributed quotation: words that belong to someone other than the
surrounding prose. Marked by a 1px `.g10` rule down the leading edge —
the grouping tone `box` and `tile_group` use, not the `.g6` state
carrier, because a quote is structure and never state — spanning the
full height of what it holds, plus an indent past it.

The attribution is words *inside* the quote, not a field on it: a quote
whose source only a border implies is a quote whose source nobody
hears. Children are the document block set — `text`, lists, code
blocks, and nested quotes — with headings and tables rejected at
`append`, exactly as in a `list_item`.

The rule is an edge it draws, so unlike `list` a blockquote **consumes**
the advised margin (see `stack`): an overflowing `code_block` inside one
clips at the rule, never across it. The rule and the indent both mirror
under `App.setDirection(.rtl)`. Semantics: `blockquote`.

### `code_block`
A verbatim block: whitespace preserved, never reflowed. `content` is
mandatory (`append` rejects an empty block). It renders in the mono
family, one line per newline, with **no word wrap** — a wrapped code
line lies about where the code breaks and re-indents the one after it.

It draws no fill and no border. A frame would be decoration, and would
move the text onto a surface the contrast gate then has to re-prove; a
block that wants one goes inside a `box`. What marks it is the mono
voice and the preserved whitespace.

A block wider than its parent scrolls horizontally — framework
behavior, no API — on the overflowing `segmented` track's terms: it
declines the advised margin and bleeds to the nearest drawn edge (the
screen at the root, a box's border otherwise), so lines clip mid-glyph
at that edge rather than mid-page, while resting lines keep the content
alignment. A 2px indicator in the `scroll_region` pattern rides the
bottom, quiet at rest and emphasized while the block is engaged.
Focusable, because it scrolls: ←/→ walk it four mono advances at a time
(a code indent), and every other key falls through to the page. A
horizontal wheel or drag over it scrolls it; vertical delta belongs to
the page — a code block scrolls one axis and the other is not its
business.

**The lines never mirror.** Verbatim content is defined by its own
bytes, like a `qr` symbol's modules: source is written left-to-right and
its leading whitespace *is* its structure, so right-anchoring lines
under `App.setDirection(.rtl)` would shred the indentation and put every
line's end on screen first. Offset 0 shows the start of the lines in
both directions. The indicator does mirror, hugging the trailing edge
like every other scroll bar.

There is deliberately no horizontal twin of the
`cleanly_clipped_scroll_region` audit rule: a scroll region's height is
the consumer's to nudge, but a code block's overflow comes from its longest
line — for parsed Markdown, bytes the app never chose — so the rule
would fire on content nobody can fix.

Semantics: `code`, announced whole as one node — a verbatim block is
read out, not navigated line by line.

### `table` / `row` / `cell`
`table` children must be `row`s; row children must be `cell`s — `append`
rejects anything else at construction. A row refuses more than 32 cells
at `append` (`error.TooManyColumns` on the cell that would open a 33rd
column) — the construction refusal every other malformed structure
gets. Column widths are per-column
intrinsic maxima; the grid is
drawn with 1px lines, and a table's rect reports its true width: one
wider than its parent overflows honestly rather than clamping silently.
Mark header rows with `.header = true`.

### `document`
Markdown source in, ordinary elements out — `append` expands it into
the elements above, so nothing after construction knows a document was
involved. The subset it parses, the rule that everything else degrades
to literal source text, and how links resolve are all
[markdown.md](markdown.md)'s — its one home.

`label` is the document's accessible name and is mandatory.
`base_level` is how deep the body hangs under the page's title: `.h2`,
the default, for a body appended to the screen; deeper for one that
belongs to a section rather than to the page. `.h1` is refused — a body
cannot be the page's top. The rebase that makes the field necessary,
and the audit rule that checks a base too deep, are
[markdown.md](markdown.md)'s too.

### `segmented`
An exclusive choice among 2+ fixed options — radiogroup semantics, not
tabs. `label` (the group's accessible name), `options`, `selected`,
`on_select`. One tab stop; ←/→ move the selection and commit immediately;
tapping a segment selects it. If activating a choice should navigate,
that is the nav's job, not this element's.

Reach for segmented when the user switches between the options
repeatedly in place — views, filters, content sections. A choice made
once and gathered by a form reads better as `radio_group` or `select`.

`disabled` turns the whole track off — one flag, for `radio_group`'s
reason. **The selected chip keeps its paper ground**, because the
selection is information and a chip sunk into the track would take it
away; both its words and the unselected ones land on `.g6`, so the chip
is what separates them, which is where this library carries a
distinction anyway ([`disabled`](#turning-a-control-off-disabled)).

A track wider than its parent scrolls horizontally. This is framework
behavior with no API.

- **The bleed.** Margins in nokre are advice, not walls (see `stack`),
  and an overflowing track is the element that must decline them: it
  bleeds through the surrounding padding to the nearest drawn edge —
  the screen at the root; a box's border stops it — squaring the
  track's corners where it reaches one. Resting chips keep the content
  alignment (the declined margin becomes a content inset), so the
  scroll positions are exactly the unbled track's; what changes is
  where chips clip: mid-chip at the screen edge, not mid-page — the
  static "more is there" affordance, nokre having no animation to hint
  with — scrolling through the margin band on their way there.
- **The indicator.** A 2px bar in the `scroll_region` pattern — both
  tones included, quiet at rest and emphasized while the track is
  engaged — rides the bottom of the track, within the content span. It
  stands in a strip the track grows for it rather than in the chips'
  own padding, so a scrolling track is deeper than the same track when
  it fits — deeper above the chips as well as below, or the band would
  read as chips pushed against its top edge.
- **Input.** The offset is scroll state like `scroll_region`'s —
  consumers never write it. Horizontal wheel/trackpad input over the
  track scrolls it freely without touching the selection; a selection
  change scrolls minimally to bring its chip fully into view: ←/→ walk
  it a chip at a time (committing each step, as radiogroup semantics
  say they must), and tapping a chip clipped at the edge selects it
  and reveals the next.
- **Assistive tech is unaffected** — every option is announced whether
  or not it is on screen.

There is deliberately no tablist element: nokre rebuilds subtrees
instantly, so co-existing tab panels never exist and tablist semantics
would be a lie to screen readers. Content-switching is a `segmented`
whose change action rebuilds, or it is navigation.

Visually, segmented is a track/chip pair: the track fills `.g11`
(dimmed), the selected option is an elevated `.paper` chip with `.ink`
text and a 1px `.g6` border. The border is what carries WCAG non-text
contrast (1.4.11) — paper on the track alone is ~1.3:1, but `.g6`
clears 3:1 against both the chip and the track in both appearances.
`nav` reuses the exact same pattern — see below.

## Navigation chrome

The stack these controls move — the route table, the four motions, and
the path that encodes it — is [routing.md](routing.md); what follows is
the chrome.

### `nav` / `nav_item`
App-level navigation — a set of places the app always has, declared in
one call and never placed in route builders:

```zig
try app.setNav(&.{
    .{ .route = "library", .icon = .library },
    .{ .route = "settings", .icon = .settings },
});
try app.navigate("library");

app.clearNav(); // and the bar is gone, roster and all
```

The nav survives every router rebuild and leads the focus order as the
navigation landmark. Placement and shape are both the framework's
decisions, not the consumer's, and there is no API for either.

**Two shapes, and the reader's window picks.** At a phone's width the
bar is the bottom band of the viewport, and whatever it holds — the row
of destinations, the collapsed chip, the minimized-notices square — is
measured at its own width and centered there. That is a thumb
affordance: reach is worst at the far edge, and the bar is the chrome a
hand goes to without looking. Anywhere wider it is a header instead —
the same destinations as words in the page's own margin, above the
page's own title, wrapping when there are more of them than fit a line.
A pointer needs no thumb band, and a window with room beside its text
column is a document.

The web is where a window resizes under a reader, so the web is where
this is decided: one rule in the DOM substrate's stylesheet, over one
markup, at the same width every other bottom-anchored surface there
stops being the whole screen
([internals/dom-substrate.md](internals/dom-substrate.md)). Nothing crosses
a consumer call, nothing is measured at build time, and a page that
boots carries exactly the markup its live frame rebuilds. The reference
substrate draws the band at every width — a native window is not a medium
that reflows under a reader, and what it draws is what its own layout
placed.

**The collapsed chip is an upgrade, not a floor.** Whether the roster
fits is only a question where a row *can* fail, and the header wraps —
so no window above that width collapses anything, on any medium that
reflows. In the band, which is one line by construction, a row that will
not fit scrolls instead: every destination is a link with an address of
its own, and a browser scrolls a focused one into view. A live driver
replaces that with the chip, which always fits. So a page nothing will
ever mount over gets the same band, the same markup and a reachable set
of destinations at every width, and nothing about who published a file
reaches the decision.

A generated page states its header through this same call
([static-sites.md](static-sites.md)) — the roster leads the page's own
title in document order — and it is where the library's one derived fact
about a page shows up: whether anything on it needs a runtime is read
off the tree rather than declared, so a document whose roster came out
collapsed is refused rather than published with a control nothing can
open.

**`clearNav` is the counterpart**, and an app needs one whenever its bar
belongs to a *session* rather than to the app: a rebuild preserves the
nav deliberately, so nothing short of this takes it down. It removes the
roster and the node — every destination unreachable, because there is
nothing left to press — along with whatever was pointing at the bar (an
open section menu is the collapsed chip's own; focus does not outlive
the node that held it). Infallible and idempotent: signing out twice
costs nothing, and neither does clearing a bar that was never
installed. A later `setNav` puts one back.

**Call both at the transition, not from a builder.** `setNav` installs
the node first among the root's children wherever the call lands — the
landmark leads by position, so neither half needs a bare tree, and the
sign-in and the sign-out can each say their piece. An install that
lives inside a screen builder runs again on every rebuild of that
screen, so a rebuild landing after the clear puts the bar back up;
nokre cannot tell that reinstall from a wanted one, and moving both
halves out to the transitions is what makes the order stop mattering.

A destination is a `route` — never an action — and optionally an `icon`
(any [`IconName`](#icon)), and nothing else. **It carries no label**:
what a screen is called is its route's [`title`](routing.md), declared
once at the route table, so the nav and the screen cannot disagree about
where you are. `setNav` refuses a route the table does not have or one
that takes arguments — a destination is a place the app always has, and
an argument would make it one particular screen.

**The glyph is uniform, not required.** A row where some destinations
have marks and others do not is worse than either uniform answer, so
both uniform answers are statable and the mixture is not: a roster
carrying some of each is `error.NavIconsMixed`, refused whole before
anything is drawn. A phone's tab bar wears marks; a generated site's
header usually wears none ([static-sites.md](static-sites.md)). Where there is a glyph it leads
the label at the label's own 16px, both always visible, and it is
decorative to assistive tech, which hears the words; where there is
none, there is no gap left where one would have been. The marker for a
screen that is none of the destinations follows the roster, because it
stands in that same row.

**The roster is 2 to `nav.max_nav_items`** (`error.NavItemCount`), and
the upper bound is derived rather than picked. Whether a row *fits* is
never a constant's question — it is asked of the reader's viewport every
time one changes, and the answer is the collapsed chip. What the bound
protects is that collapsed shape: the whole roster becomes the section
picker's list, and past the count where a list stops being scanned and
starts being typed into, the picker grows a filter field the section
list deliberately does not have. So the bound is that count, less the
one row an off-roster screen may add.

It still binds where the roster is a header. A header wraps and needs
no collapsed shape of its own, but a roster is declared **once** and
any window can be narrowed to a phone's — so the set has to be one both
shapes can carry, and the stricter shape is the one that sets the
bound. A site with more destinations than the bound restructures; that
is the price of one markup answering every width.

**The bar has no ground.** There is no track, no fill, no hairline —
the nav is its items and nothing else, each on a plate of its own, with
`metrics.nav_item_gap` (8px) of page showing between them. The plates
are three levels: the page, the destinations on `.g11` (the dim track
tone every other control uses), and the current route one step above
them on `.g10`, outlined in `mid` and lettered in `.ink` — `mid` rather
than the `.g6` other chips use, because `.g6` is 2.7:1 against `.g10`,
under the 1.4.11 floor, and `mid` is the lightest tone that clears it
on both of the chip's sides. The current item is exposed as
`aria-current`; consumers never manage selected state. Activating an
item **pushes** its destination, so crossing the nav leaves a way back
to the screen you crossed from ([routing.md](routing.md)); activating
the destination already showing does nothing.

**Each destination is as wide as its own words** — its glyph, the gap
after it, the label, and `metrics.nav_item_pad_h` (20px) on either
side: the button's 16 with 4 added back, because a pill's ends curve
away from the words. Equal slots would stretch each pill to a share of
the bar and set its words adrift in a strip of identical lozenges. The
row is measured, then centered on the viewport as one group, the
notices indicator — when there is one — riding at its trailing end. The
gap between plates is drawn, not laid out: each item's *rect* is its
pill grown half a gap on either side, so the targets meet end to end
and a thumb landing between two destinations still lands on one of
them.

Plates are **pills** — the corner is half the slot's height, derived
rather than fixed, so the shape follows the slot instead of drifting
back to a rounded rectangle the next time the row grows. Nothing else
in the library is a pill: the nav is the one place a control is *only*
a target, with nothing around it to square up against. The collapsed
chip takes the same corner, and the notices indicator beside them — a
pill as tall as it is wide — is a circle.

**As a header the same items are words.** No plate, no pill, no fill:
the destinations take the same `dark` step-back tone they wear on their
plates, and the one you are standing on takes `.ink` and the bold face.
Weight and tone are how a grayscale system says *this one* — a fill is
the weakest mark available in thirteen grays, and the band uses it only
because a band has plates to fill. There is no underline either, though
[`link`](#link) carries one: an underline says *this word is a
destination* among words that are not, and in a row where every word is
one it distinguishes nothing. The row sits in the page's own 16px
margin, wraps at the page's own gap, and stands above the page's first
block; the notices indicator, if there is one, keeps its plate, being a
glyph target rather than a word.

Because nothing hides what passes behind it, every screen whose bar is
in the **band** reserves `metrics.nav_content_gap` (24px) below its last
element, on top of the bar and the OS safe band. Scrolled to the end, a
page stands clear of the nav; mid-scroll, lines pass behind the items
and down into the safe band — that glimpse of a half-covered line is the
only thing left saying there is more below. A header reserves nothing:
it took its space where it stands, at the top, in flow.

A slot is 52px tall, the one control in the library that grows *past*
`touch_target` rather than up to it: it is the chrome a thumb reaches
for without looking, stacked against the bottom edge where reach is
worst. Below it the bar keeps `metrics.nav_bar_pad_b` (16px) of clear
space, the same inset the page's own margin takes from the frame —
except that the OS band counts toward it, so on a phone the items sit
just above the home-indicator strip rather than 16px above a strip that
is already empty.

Where the labels fit, the nav is that row. Where they do not, it
**collapses**: the bar shows the current section alone, as the same
chip wearing that section's glyph with a chevron-up at its trailing
edge, and the other destinations move behind a picker that opens above
it — carrying their glyphs into the list, so a mark means the same
thing in both shapes.

The threshold is measured, not a breakpoint — the one breakpoint above
is about *where the bar stands*, which is a fact about the reader's
window, and this is about whether a particular set of words makes a
line, which no width alone can answer:

- **What "fits" means.** The row fits when its pills, the gaps between
  them, the bar's insets, and the indicator's reserved square fit the
  **viewport** — a longer word costs the row that word and nothing
  more, and the reserve is counted whether or not an indicator is
  showing, so the nav never changes shape because a notice arrived.
- **The viewport, not the 560px pane.** That cap is a line-length
  argument, governing the bottom chrome that holds prose — the banner,
  the notices pane, the sheet, a select's picker — and nothing in the
  bar is prose, so the row grows past the cap to exactly the width its
  items need and no further.
- **What moves the answer.** Icons cost width, so they push rosters
  into the chip sooner; a set that fits in landscape and not in
  portrait reshapes as the device turns, one too wide for a laptop
  reopens the moment the window reaches the width it asked for, and
  translations change it too — the same app can be a row in English
  and a chip in German, which is the point of measuring.

The collapsed chip does not grow at all: it is one control, and a
control that widened to hold one word would be its own kind of wrong.
It is centered like the row, with the minimized-notices square counted
into the same group and riding at its trailing end, so the two read as
one bar. A lone square with no destinations beside it is that group by
itself, centered — the one piece of chrome that does not move under
[right-to-left](localization.md) mirroring, since a centered control
has no leading edge to swap. The section card the chip opens is
centered on the same group.

The chip is a `combo_box` to assistive tech, not a link: it opens a list
and takes a choice. Its accessible name is the framework's own word for
it ("Section" in English, `App.Chrome.section` in yours) and the
current section is its *value*, so the control a screen-reader user
looks for does not rename itself every time it is used. The list is the
select's picker in behavior and a card in shape *where the bar is in the
band*: it stands on the chip, as wide as its longest row rather than as
wide as the pane, with the current section marked. A select's picker is
bottom-anchored because its owner is somewhere in the page; this one's
owner is right below it, so the list is measured from the chip and
draws no title — "Sections" stays as the dialog's accessible name,
which is the only place it was ever needed. Where the bar is a header
the exception lapses with the reason for it: the chip is at the top,
and a card floated over the bottom edge would be a list at the far end
of the screen from the control that opened it, so the section list is a
bottom pane like every other picker. Choosing one navigates
exactly as tapping a row item does — a push — and choosing the screen
you are already on does nothing: the shape must not decide what a
choice costs.

**The chip is the one control that acts on the press.** Holding it opens
the list, so the same press can travel to a row and choose it by letting
go — the menu-bar gesture, without a menu bar. Three releases, three
outcomes: over a row it goes there, back on the chip it *leaves the menu
open* so a second press can choose by tap, and anywhere else it closes
having chosen nothing. Nothing is committed by the press itself.

That middle outcome is what makes the drag an addition rather than a
replacement: a plain click, the Tab/↑/↓/Enter path, and a screen
reader's own activation all reach every section without dragging
anything (WCAG 2.5.1), and moving off before letting go always aborts
(WCAG 2.5.2). The list opens clear of the chip rather than over it —
a menu covering its own control would put a row under the finger still
holding it, with nowhere to release that means "never mind". While the
menu is open, moving the pointer moves **focus** to the row under it:
the state ↑/↓ already move and assistive tech already announces — not
hover returning by another door, because hover is a state with no
keyboard equivalent and this is precisely the keyboard's.

### `nav_here`
**A screen that is none of the destinations names itself.** Most apps
have more routes than nav sections — a detail screen, a legal page, a
screen reached from a notice. On one of those, the roster matches
nothing, and both shapes have to answer "where am I" anyway.

They answer it with one extra entry, appended to the roster the chrome
draws from: the current route's [`title`](routing.md), wearing the shared
`file_text` mark. In the row it is a `nav_here` — a plate at the trailing
end, in the current destination's plating. Collapsed, it is what the chip
carries, so the answer does not depend on the shape. Consumers append
neither, and name neither: every line of the roster — the destinations
and this one alike — is labelled from the route table.

The mark is one glyph for every off-roster screen, not a per-route field.
A destination earns a recognizable mark by being somewhere you return to;
this is only ever *here*, and a mark of its own would make each of these
look like a destination the roster forgot.

**The marker is a label, not a destination.** It is `static_text` to
assistive tech — named "Current screen", with the title as its value,
the same split the chip makes — takes no focus, is not in the tab order,
and answers no press. A destination is a link that goes somewhere; this
one goes where you already are. In the picker, though, it *is* a row:
last, selected, so the chip's value is one of its own options rather
than a name the list does not contain. Choosing it is declined by the
rule that already declines the current destination.

**Nothing is inherited.** A screen pushed from Settings is not "in"
Settings, and the nav does not mark Settings while you are on it. nokre
never asked consumers to declare a hierarchy, so it has none to walk, and
guessing one from the stack would light a section on the strength of how
the visitor happened to arrive: two doors to the same screen would light
different sections, and a shared link opening it directly would light
none. What used to happen here was worse and simpler — the chip fell back
to the *first* destination, naming a section the visitor may never have
opened.

The extra entry is measured like any other, so the collapse threshold
needed no rule for it: a row with one more pill in it collapses at a
wider viewport, which is the threshold working, not an exception to it.
Crossing back onto a destination drops the entry and the row returns to
the roster alone.

### Back control
A pushed screen always has a way back, and the framework installs it:
whenever the route stack is deeper than one screen, the rebuild places
a back control ahead of anything the route's builder appends — a
chevron-left glyph on the sheet-close's 44px touch target, sharing the
first content element's line (a heading, by convention) with
that element indented past it. The target hangs into the page margin on
both axes so the *glyph* is what lines up: its leading edge sits on the
text column, and it centers on that first line's cap region rather than
its line box, which a heading without descenders reads low against.
Its accessible name is the framework's own word for it ("Back" in
English, `App.Chrome.back` in yours —
[localization.md](localization.md#the-frameworks-own-words)); activation
pops one screen
(`App.navigateBack`). There is nothing to configure and nothing to wire
— consumers never build their own back control, and a pushed screen
without one cannot exist. The stack root (depth 1) has nothing to go
back to and gets none — including the first section the app opens on,
until the nav is crossed; a screen that must not be returned to is a stack
problem — enter it with `replace` or `switchTo`, not `push`.

The one state it draws is **armed**: a back gesture is in progress and
past the point where releasing would commit
([routing.md](routing.md#the-back-gesture)). The chevron becomes an
**arrow** — the mark changes and nothing else does, the same move an
acknowledged `copyable` makes when its copy glyph becomes a check. A
chevron points the way navigation goes; an arrow is the going, so the
armed control states the outcome it is promising rather than looking
like a button being held. It is a latch, not an animation — one repaint
as the threshold is crossed, one as it is crossed back — and it is drawn
at all because a threshold that can only be felt is no threshold on a
device with haptics turned off.

### `header_action`
A screen may close its title's line with one or two glyph controls of its
own — a Refresh, a Filter — stated the way the title is:

```zig
try app.setHeaderActions(&.{
    .{ .icon = .refresh_cw, .label = tr(.refresh), .on_press = .bind(State.reload, state) },
});
```

They stand at the trailing end of the route header, whose other end is
the back control: same 44px target, same quiet glyph on the ambient
surface, same outward bleed into the page margin, and the same
cap-region offset, so the two ends and the title read as one line. A
pair stands **flush** — each glyph already sits in the middle of its own
target, so two are 20px apart, and a gap between two targets is a place
a thumb lands on neither. The title gives up whatever band they take and
wraps inside what is left. Mirrored chrome swaps the two ends and the
pair mirrors as a group: the first one stated stays nearest the title.

`label` is what assistive tech announces and is mandatory — nothing here
draws words, so it is the whole of the name, and there is deliberately no
`accessible_name` beside it: that field exists to say something the
*visible* words cannot, and a control with no visible words has nothing
to say it against. Each is a real button: a focus stop between the back
control and the screen, held to the audit's one-name-per-layer rule, and
activated by tap or Enter like any other.

**Two, and no more.** The header is one line and its middle is the
title; a third square is width taken off the words on the narrowest
phone, and a screen that needs three has actions that belong in its body.
The tree refuses a third.

**Content, not chrome.** They are the screen's, cleared by a navigation
with the rest of it — unlike the nav, the notice banner and the notices
indicator, which survive. That is also why they are not the chrome
`icon_button`: that element's glyph is a closed set core switches on to
decide what pressing it does, it carries no action to wire, and it is
the one root-level element the notices indicator is entitled to assume
it is alone as. Restating the same number of actions keeps their nodes,
so a screen that re-states its header after a load does not pull a node
out from under a reader's own keyboard focus.

## Layers

### `sheet`
The only modal surface, declared to the app as a *builder* — a fn the
framework calls to build the sheet, and calls again whenever it must be
built again — never appended directly to build content. Sheets
**stack** (since 2026-09-09): `App.sheets` holds one level per open
sheet, bottom first, and the tree holds the top one's node alone —
rendering, focus scope, hit testing, the scrim and the a11y snapshot
see the one dialog they always saw, and what stands underneath is kept
builders, not nodes.

```zig
const Sheet = enum(u32) { filter = 1, saved_views }; // this controller's sheets, named

fn buildDialog(c: *Filters, app: *nokre.App, which: Sheet) !void {
    switch (which) {
        .filter => {
            const sheet = app.at(try app.presentSheet("Filter results"));
            try sheet.toggle(.{ .label = "Only unread" });
        },
        .saved_views => try c.buildSavedViews(app),
    }
}

// at the point the user asks for it:
try app.openSheetAs(Sheet.filter, buildDialog, c);
```

`openSheetAs` runs the builder at once and keeps it — as data, for as
long as the sheet is up — with the sheet's name typed and the context
bound, exactly as `Routes(State)` does for a screen. The name arrives
at the builder because the framework knows it: the builder it is
running is the one it just installed, so the cast, the tag unwrap and
the `@enumFromInt` that used to open every one of these functions say
nothing the `openSheetAs` line did not already say.

A builder with nothing to tell apart drops the last parameter and is
`fn (c: *Filters, app: *nokre.App) !void` — a sheet builder is written
like a screen builder. Nothing chooses between the two forms but the
builder's own parameter list, and Zig refuses an unused parameter, so
the form that compiles is the honest one. Name the sheet either way:
that is what lets

```zig
if (app.sheetTagAs(Sheet, c)) |which| { … }   // is *mine* up, and which?
```

answer for **this** controller. The tag namespace is flat — every
controller in an app mints into the same `u32` — so the raw
`App.openSheetTag()` cannot say whether the number it hands back is
yours, and two controllers on one screen whose enums both start at 1
read each other's sheets as their own. The context disambiguates them,
and `sheetTagAs` is that question. (`0` is how a sheet says it has no
name at all, which is why an enum with a member at 0 is refused where
you write it.)

That one declaration is the whole lifecycle:

- **State changed under the open sheet?** Call `openSheetAs` again with
  the same name and builder — the sheet on top is rebuilt in place,
  never stacked. (`App.refresh` does it for you when a sheet owns the
  screen.) The builder always starts from a tree with no sheet in it
  (the framework takes the standing one down first), so building is
  always building from scratch, and a builder never calls
  `dismissSheet` itself. Focus rides the rebuild the way it rides a
  reload — re-found by name, the caret with it — so a field whose
  `on_change` re-presents the sheet keeps the on-screen keyboard up
  between two letters. *Its own* sheet is the one on top with the same
  name, the same controller and the same builder — the name alone
  would make two controllers' first sheets one sheet, and the name and
  controller alone would make a controller's two unnamed sheets one.
- **A sheet over the sheet?** The same door: `openSheetAs` with
  another name — or another controller's, or the untyped `openSheet`
  with another builder — while a sheet stands **stacks** the new one
  over it. There is one verb and no push (decided 2026-09-09, after a
  push pair was tried). The new sheet takes the tree, the covered one
  stays open underneath as its kept builder, and when the one on top
  goes the covered one is **built again from the state as it is
  then**, the keyboard returning to the stop it held there by name,
  caret and all. `refresh` re-runs the top builder only; a covered
  builder answers changed state when it returns to the top.
  `sheetTagAs` and `openSheetTag` answer for the top — a sheet of yours
  under someone else's is not the one the user is looking at.
- **Replace the sheet instead?** That is your act, not the door's:
  take the standing one down first — `App.dismissSheet()` (no rebuild
  of the screen) or `App.closeSheet()` (the screen rebuilt when the
  stack empties) — and then open. A controller that used to open its
  next dialog straight over its last one now finds the last one still
  underneath; dismiss first if that was a replacement.
- **The screen reloaded?** The top builder runs again over the rebuilt
  screen, unasked, and every level under it is kept: a sheet survives
  `reload` the way scroll does, because a reload is the same screen
  answering changed state. A real navigation is a different screen,
  and drops the whole stack.
- **Done with it?** `App.closeSheet()` — the sheet on top comes down,
  the one under it stands again, and when it was the last the screen
  behind is rebuilt from the state the sheets just changed. That pair
  is one verb because it was one pair at every close handler ever
  written; the rebuild is the deliberate `reload` (closing a sheet is
  the user's own gesture) and its error is unactionable, so it is
  swallowed there rather than at your call site. A Cancel button wires
  straight to it — `.on_press = .bind(nokre.App.closeSheet, app)`, the
  App being the only state the verb takes — so a controller declares no
  close of its own. The framework's own dismissals go through the same
  verb (Esc, the scrim, the ×, each popping one level), which is what
  lets `App.refresh` leave the content behind a live sheet alone:
  whatever the user writes under their own dialog is on screen the
  moment the last dialog goes. (`App.dismissSheet` is the pop without
  the rebuild, for a caller about to build the screen itself.)
- **The sheet closed?** However it happened — Esc, the close control, a
  tap outside, `closeSheet`, `dismissSheet`, a navigation — the builder
  is dropped (so `sheetTagAs` already answers null, or the sheet now on
  top) and its optional `on_dismiss` told, before the builder under it
  runs, so that one reads the state the closure wrote. A navigation
  tells every level's, top-down. That callback is for *work* a closure
  owes — free a held row, cancel a request the dialog was waiting on —
  not for recording that the sheet closed, which is now the framework's
  answer. A sheet that owes such work declares the `SheetBuilder`
  struct itself and hands it to `App.openSheet`, the untyped door
  underneath: `on_dismiss` is a second function over the same context,
  and binding fills a pair, not a struct.
- **A builder that presents nothing has declined** — its subject
  vanished — and its level is dropped quietly, with no `on_dismiss`:
  the state already knows. The level under it builds instead, and so
  on down; a stack that empties this way leaves the screen behind
  standing as it is, since no user gesture closed anything, except
  under `closeSheet` and `refresh`, which go on to rebuild the screen
  once nothing owns it.

Both doors answer a **declared** error set, `App.OpenSheetError`:
`OutOfMemory`, or `SheetBuildFailed` when the builder itself said no.
Two members because a caller acts on two things — a dialog that did not
open, and a process out of room; against `anyerror` every call site
wrote `catch {}` and a failed confirmation vanished with it.

Inside the builder, `presentSheet` is the verb that makes the node: it
returns the sheet to fill with content. A confirmation fills it with
[the confirm-sheet idiom](#the-confirm-sheet).

A bottom-anchored panel (top corners rounded, `.g6` outline), at most
`metrics.sheet_max_w` (560px) wide and never closer than
`metrics.sheet_min_top` (48px) to the top edge. The framework pins a
close control — a quiet Lucide square-x glyph with the accessible name "Close",
occupying the full 44px touch target — in the header corner and moves
focus to it; everything
behind the sheet is inert — unreachable by Tab, tap, and scroll — and is
dimmed by a 1px `.paper` checkerboard scrim, which keeps the pixels
inside the thirteen-gray palette. The close control, Esc and a tap on
the scrim all take the `App.closeSheet` road — one user gesture, one
outcome, the sheet underneath standing again or the screen behind
rebuilt — and focus returns to the element that had it. One sheet
*node* at a time: a second `presentSheet` inside one builder is
rejected at the call site, and a sheet over a sheet is `openSheet`'s
while one stands.

It appears in place, fully formed — no slide, no fade (WCAG 2.3.3, and
nokre has no animation to begin with).

### `notice`
A persistent notice, raised through the app:

```zig
app.notify(.{
    .title = "Sync failed",
    .description = "Changes are kept locally.",
    .route = "sync",
    .icon = .cloud_off,
    .important = true,
});
```

`notify` cannot fail: the pending list is a bounded ring whose slots
`App.init` reserves whole, so raising a notice is a copy, not an
allocation — there was never anything an app could do with the old
error but swallow it. The bound is generous (32 pending, and titles are
identity, so that is 32 *distinct* notices); past it the ring evicts
drop-oldest, quiet notices first — the banner's important front is the
last thing to go.

A notice is a title, an optional description, the route its open
control deep-links to (optional, and usually absent — a notice that
reports without sending anyone anywhere grows no open control at all),
an optional leading icon (decorative — the title stays the accessible
name), and an importance. The importance is
behavioral, not visual: an **important** notice interrupts as the
banner and re-surfaces minimized ones; a **quiet** one (the default)
joins the pending list behind the indicator without taking the screen.
Quiet is the default because interrupting is the thing a notice should
have to ask for. Pending notices surface in exactly one of three
states, all living in the bottom pane:

- **Banner** — the front notice as a row anchored to the viewport
  bottom, hiding the nav while it shows. It reserves its own band, so it
  can never obscure content. Leading control: *expand* (opens the
  notices pane) when more than one notice is pending; *open*
  (deep-links to the notice's route, minimizing first) when it is the
  only one *and* it carries a route; nothing at all when it is the only
  one and routeless, and the words take the room. Trailing controls:
  *minimize* and *dismiss*.
- **Notices pane** — a modal, sheet-like panel listing every pending
  notice with a per-row dismiss control (and an open control on the
  rows that carry a route), plus a dismiss-all control
  (the trash glyph) beside the minimize control in its header. Minimize
  keeps the trailing corner — the slot where a modal closes — so the
  reflex press parks the notices rather than destroying them.
  Important notices lead the list, and when both kinds are pending each
  group sits under a small label ("Important" / "Other") — plain text,
  not headings, so two words of chrome never enter a screen reader's
  heading navigation ahead of the page.
  Esc or a tap on the scrim minimizes it. It keeps the sheet's height cap
  (`metrics.sheet_min_top` clear of the top edge), and the rows sit in a
  scroll region inside it, so a list longer than the cap allows — which a
  landscape phone reaches after very few notices — scrolls by wheel,
  drag, or keyboard rather than being clipped at the pane's edge. The
  header stays put, dismiss-all with it: the control that empties the
  list should not scroll away as the list grows.
- **Minimized** — an indicator glyph that reopens the pane. It belongs to
  the bar rather than to the pane: it rides at the trailing end of
  whatever the bar is centering — the row of destinations, or the
  collapsed chip — and centers alone when there is no nav.

All controls are Lucide glyphs on 44px targets with accessible names.
Notices never steal focus and **never time out** (WCAG 2.2.1 — there is
no auto-dismiss API to misuse). Duplicates (by title) are dropped; a new
important notice re-surfaces minimized ones as the banner, and the
banner is always an important notice while any is pending — dismissing
the last important one collapses to the indicator rather than promoting
a quiet notice that never asked to interrupt. An open sheet takes the
bottom pane, parking notices behind the indicator until it closes.
Notices survive navigation. Screen readers announce the banner politely
as a status live region.

## Actions

Actions are context + function-pointer pairs (`Action`, `ToggleAction`,
`ChangeAction`, `SelectAction`) — nokre never allocates closures.
`bind` builds the pair from a typed method, so the handler is written
against your state type and the `?*anyopaque` plumbing never appears in
app code:

```zig
.on_press = .bind(State.save, state)

// in State:
pub fn save(self: *State) void { ... }
```

The payload-carrying actions hand their payload to the bound method —
`ToggleAction` a `bool`, `ChangeAction` the `[]const u8` value,
`SelectAction` the selected `usize`:

```zig
.on_toggle = .bind(State.setNotify, state)   // fn (self: *State, checked: bool)
.on_change = .bind(State.editName, state)    // fn (self: *State, value: []const u8)
.on_select = .bind(State.chooseScheme, state) // fn (self: *State, selected: usize)
```

### A row's action carries the row

Two forms do that, and choosing between them is the one decision this
part of the API asks you to make: **where the row was** or **which row
it is**.

```zig
.on_press = .bindAt(State.accept, state, i)          // fn (self, index: usize)
.on_press = .bindKey(State.remove, state, row.id.get()) // fn (self, key: []const u8)
```

Both put the datum on the element, so it is exactly as fresh as the
tree it rides in — rebuilt with the screen, never baked into code.
(`ToggleAction` has the indexed form only, and adds the index *before*
the checked state: `fn (self, index, checked)`. It has no keyed twin
until a real toggle row needs one; see `element.zig`.) An action names
one function: setting more than one of `call`, `call_indexed` and
`call_keyed` is refused at `append`.

Neither form is a claim about the present. A press is delivered against
the tree the user *saw*, and the list that tree was built from may have
moved by the time the handler runs — a reply landed, a row was removed,
the screen was not rebuilt because the user was holding it. What
differs is what a stale one can do:

- **`bindAt` hands back a position, and a position is always occupied
  by somebody.** A stale index that is still in range names a live row
  — the wrong one — so the contract is one sentence: **the receiver
  bounds-checks**, and a check that passes is not proof the row is the
  one that was pressed.
- **`bindKey` hands back an identity, and an identity that is gone
  matches nothing.** There is no index to index with, so the handler's
  only move is to look the key up; the lookup finds the row the user
  pressed or it finds nothing, and nothing is a no-op. There is no
  wrong row to land on.

```zig
pub fn remove(self: *State, key: []const u8) void {
    const row = self.findByKey(key) orelse return; // gone: decline
    ...
}
```

nokre does neither check for you — it knows the tree, not your data —
and it never interprets a key: whatever bytes you bind come back
verbatim. It does **copy** them at append, like every other string an
element carries, and that copy is what makes the guarantee hold: the
natural key is a field of the row it names, so a borrowed one would
still be pointing into that row when a reply refills the list, at which
moment the pressed row's key has quietly become its successor's.

Use `bindAt` where the row *is* the position — a fixed comptime list of
settings, a table of steps, options that cannot reorder. Use `bindKey`
where the rows came from a reply. An empty key is legal and means the
row had no identity to give; it matches nothing, so it declines.

### Binding callbacks nokre never sees

The four `bind` methods are one generator with four faces, and it is
exported: `nokre.bindAs(CallbackT, handler, state)` fills **any**
`{ ctx, call }` pair the same way.

```zig
port.loadRows(.{ .id = id }, nokre.bindAs(Port.RowsCallback, Screen.onRows, screen));

// in Screen — no cast, no null unwrap, no forwarding shim:
fn onRows(self: *Screen, result: Port.RowsResult) void { ... }
```

`CallbackT` is duck-typed at comptime: a struct with `ctx: ?*anyopaque`
and a `call` that is a (possibly optional) pointer to a function taking
`?*anyopaque` first. Everything past the context is forwarded by
position and by value — whatever it is, however many — and the return
value comes back the same way, so a callback that answers a `bool` or a
struct binds like one that answers nothing. Fields beside the pair keep
their declared defaults; a pair with a field that has none is not a pair,
and says so.

The point is what `CallbackT` may be. **A callback type does not have to
come from nokre**: a domain package that models its ports as
`{ ctx, call }` pairs stays framework-free, and the app — which does
import nokre — binds handlers into them. That asymmetry is why this is a
free function over a type rather than a method on one.

A handler whose signature does not fit fails *at the bind*, with the
signature it should have had and the one it has:

```
bind.zig: bindAs: this handler does not fit `Port.RowsCallback.call`.
  expected: fn (*app.Screen, port.RowsResult) void
  found:    fn (*app.Screen, u32) void
```

What `bindAs` is not is a way to reach a callback field riding on a
larger struct — an http `Request` carrying a URL and a tag, a
`SheetBuilder` carrying its tag and its `on_dismiss`. Binding fills a
whole value; a struct with more in it is built by the code that has the
rest, which for a sheet is `App.openSheetAs` (it has the tag).

## Proposing an element

The set is closed, but not frozen: a new element is argued in on
semantics — one sentence stating what it *means*, or it doesn't go in —
and lands via the maintainer checklist in
[internals/contributing.md](internals/contributing.md).
