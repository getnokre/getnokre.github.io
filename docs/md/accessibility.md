# Accessibility

nokre inverts the usual model: you cannot add accessibility, because you
cannot omit it. The semantic tree *is* the UI; the pixels and the
accessibility tree are both projections of it.

## Derivation

[src/a11y/semantics.zig](../src/a11y/semantics.zig) walks the element tree
and produces a flat, parent-linked `Snapshot` in document order. Roles map
1:1:

| Element | A11y role | Carried state |
| --- | --- | --- |
| root stack | `document` | — |
| `text` | `static_text` | content as label; styling spans are invisible — one node announcing the concatenation |
| span with a destination (`route` or `external`) | `link` | a link child of its paragraph, named by its own words, focusable |
| `heading` | `heading` | level 1–6; spans invisible as on `text` |
| `icon` (labeled) | `image` | label as name; decorative icons are omitted |
| `badge`, `meter` | `static_text` | the words carry all state; a badge's leading mark is decorative and is never announced |
| `diverging_meter` | `static_text` | row label as name, both sides' words joined as the value — an arm nobody can see is otherwise a magnitude only a looker gets |
| `qr` | `image` | label as name, encoded value carried |
| `quantity` | `static_text` | value and unit joined as the name, caption as the value — the reverse of `diverging_meter`'s slots, and for the reason its row gives |
| `stack`, `box` | `group` | — |
| `diverging_group` | `group` | nameless: it decides a track width, not a reading |
| `tile_group` | `group` | description as value |
| `divider` | `separator` | — |
| `stand_in` | `status` | label as name, polite; its subtree is announced as itself, every control there disabled and not busy, focus stops kept (below) |
| `button` | `button` | focused, disabled, busy (`in_progress`: disabled *and* busy, and still a focus stop); `progress_percent` as the value; `accessible_name` as the name where it is stated, the words otherwise |
| `button` / `link` (folded) | — | absent: the row folded it away and its `more` speaks for it |
| `sheet_close`, `back`, `icon_button`, `more` | `button` | focused |
| `link` | `link` | focused |
| `tile` | `link` (route) / `button` (action) | detail and `badge` joined as the value, focused, `disabled`; its leading mark is decorative and its chip is not — a glyph's meaning is a guess and a word is not, so the label is the name and the chip is announced |
| `toggle` | `switch` | on (carried as checked), focused, `disabled`; `in_progress`: disabled *and* busy, the value still carried, still a focus stop |
| `checkbox` | `checkbox` | checked, focused, `disabled`; `in_progress` as `toggle` |
| `copyable` | `button` | copied value carried, focused; a `status` child while acknowledged |
| `text_input` | `text_field` | value, composition, focused; the selection while the reader is in it, the caret being its collapsed case (below); `problem` as the description, with `invalid` set; `disabled` alone, never with `busy` |
| `text_input` (obscured) | `password_field` | value withheld — and the selection's offsets with it; the `problem` is not |
| `text_area` | `multiline_text_field` | value, composition, selection, focused; `problem` and `disabled` as `text_input`'s |
| `list` / `list_item` | `list` / `listitem` | —; the derived marker is presentation and is never announced |
| `code_block` | `code` | content announced whole, focused |
| `blockquote` | `blockquote` | —; the attribution is words inside it |
| `table` / `row` / `cell` | `table` / `row` / `cell` | header rows |
| `scroll_region` | `scroll_area` | focused |
| `region` (`masthead`) | `banner` | its `label` as the name, focused. Deliberately not `status`: a polite live region re-announcing a queue count is what `notice` and `stand_in` exist to keep rare |
| `region` (`roster`) | `navigation` | the same role a `nav` takes. Two navigation landmarks in one document is the ordinary shape and they are told apart by name — which is why a region's label is required |
| `region` (`main`) | `main` | its own role because every screen reader offers "jump to main" and no other landmark answers it |
| `region` (`aside`) | `complementary` | — |
| `region` (`composer`) | `form` | a landmark grouping the controls that combine to do one thing, which is what a composer is and what a reader jumps to |
| `region` (folded) | — | absent, subtree included: a narrow desk is not showing it and the switcher speaks for it |
| `segmented` | `radio_group` | selected option as value, focused, `disabled` |
| `radio_group` | `radio_group` | selected option as value, focused, `disabled` |
| `ranking` | `group` | the cursor slot's words as value and its rank as description — where the one stop is standing; selected while that slot is the armed one; focused; `disabled`. Every slot of the device is a child of its own (below) |
| `ranking` slot | `button` | the plate's words as name, its rank as value — a rank only a counted slot has, so an item below the divider is heard with none; selected while it is the armed slot; `disabled` where the band rules it out; activatable, never a focus stop. A pinned divider's slot is `static_text` at its plate instead: it is a caption, and there is no button to press |
| `dial` | `spin_button` | the reading its plate draws as value — the number in the app's own digits, written by layout — and the same figures as a `range` (min, max, now, step); focused; `disabled`. The adjustable role, with the increment and decrement actions behind it on every backend. Both step buttons are children of their own (below) |
| `dial` step (framework) | `button` | named by the framework ("Increase" / "Decrease" in English — [localization.md](localization.md#the-frameworks-own-words)), activatable, never a focus stop; `disabled` at the end of the range, where the plate beside it is empty |
| `select` | `combo_box` | selected option as value, focused, `disabled` |
| picker (framework) | `dialog` | modal; `picker_item` → `option`, selected |
| `nav` | `navigation` | — |
| `nav_item` | `link` | selected (aria-current), focused; its icon is decorative — the label is the name |
| `nav_current` (framework) | `combo_box` | named by the framework ("Section" in English — [localization.md](localization.md#the-frameworks-own-words)), current section as value, focused |
| `nav_here` (framework) | `static_text` | named by the framework ("Current screen"), the route's title as value; no focus stop — it names where you are, it does not go there |
| `sheet` | `dialog` | modal |
| `notice` | `status` | title **and description** as the label, joined (`Notice.reading`) — a live region is announced by its name, so prose in any other slot is drawn and not heard (below) |
| `notices_pane` | `dialog` | modal |

Each node carries its layout rect, so screen readers get correct hit
geometry for free.

The five landmark roles need no row in the iOS or Android bridge, and
that is the correct answer rather than an omission: both of those tables
are partial by construction — iOS names the roles that carry a
`UIAccessibilityTrait`, Android the ones that map to a widget class —
and a role neither names falls through to a container default, which is
what a landmark is on both platforms.

A `stand_in` ([elements.md](elements.md#stand_in)) is a screen that is
still arriving, and it is derived from like any other. Its scope is one
polite live region saying the app's own "loading" words; the real text
under it is announced as ordinary text, because it is real; and its
controls are announced **disabled and not busy** — the thing they act
on has not arrived, so they are off, where the pair below is a control's
*own* work running. Their names are real,
and hearing them is how a screen-reader user orients on a screen that
is arriving, exactly as a sighted reader does.

The one thing silent under the scope is a **pending value**
(`nokre.pendingValue`): a value that has not arrived has no name to
announce, so its node is left out rather than read as an empty one. A
control named by one is a placeholder rather than a control — out of
the snapshot, out of the focus order, and out of the uniqueness rule,
which is what makes five rows waiting on five names legal.

This inverts what the element shipped with, where the whole subtree was
silent. That rule settled the reading order and the tab order before
the content arrived, which the new one gives up for the controls whose
own names are still pending: they become stops when their words land.
It is the smaller cost — under the new rule most controls are real from
the first frame, so most of the order is settled anyway, and what was
bought is a screen a reader can actually orient on while it waits.

A control an app has turned off ([elements.md](elements.md#turning-a-control-off-disabled))
is announced `disabled` and **never busy**: nothing of its own is
running. Ten kinds carry that flag, and the announcement is derived by
reflection over the one field that means it — so a kind that grows one
is announced off the day it is declared, with nothing here to update.
Everything a reader needs stays: the name, and the value in whichever
slot the kind carries it — a switch's position, a box's tick, a chosen
option, a row's reading. Off is not gone. What it does lose is the focus
stop, which is exactly what the scope's controls above keep, and exactly
what the pair below keeps too.

A button with work in progress ([elements.md](elements.md#button)) is
the one state that rides as a pair: **disabled and busy**, never one
without the other. Not operable — a second press must not start the
action twice — but present, named, and still a focus stop, which is the
combination the ARIA practices prescribe and the reason the state is not
simply `disabled`: the user who pressed it keeps their place, and hears
what the button is doing rather than finding it gone. Each backend says
it in its own words — `aria-busy` beside `aria-disabled` on the web,
AccessKit's `busy` on macOS/Windows/Linux, a state description on
Android (API 30+), and, because UIKit has no busy trait at all, the
value slot on iOS, where the shell already spells `on`/`off` out. What
the pixels show is an hourglass; what assistive tech gets is the state
itself.

When that button also carries a `progress_percent`, the number rides in
the node's **value** — "Save changes, 60%" — and the role stays
`button`. A `progressbar` role would be the ARIA-shaped answer and is
the wrong one here: it is a different role, and this node is a control
that was pressed, not a bar. Putting the number in the value is the
trade `meter` already makes, and it needs nothing new on the wire, so
every backend carries it today. It is also why the bar being absent on a
disabled button costs a screen reader nothing: the pixels drop the
track, the value keeps the number.

A refused field ([elements.md](elements.md#problem-what-is-wrong-with-the-value))
is the one state that rides as a **description plus `invalid`**, and it
is deliberately *not* the disabled/busy pair above: the field takes
every keystroke it took before, because a control the user cannot edit
traps them in the value that was just refused. `invalid` is derived
from the words rather than stored beside them, so a control can never
be announced refused with no reason given. It is read after the name
and the value — what the control is, what it holds, then why that is
not accepted — and each backend spells it its own way: `aria-invalid`
plus an `aria-describedby` reference to the words on the web,
AccessKit's `invalid` and `description` on macOS/Windows/Linux,
`setContentInvalid` with `setError` on Android, and, because UIKit has
no invalid trait, the hint slot on iOS, where the app's own words are
the statement. That last one needs no invented English, unlike busy:
the reason is the app's to write, always.

Where the words *live* is the one place the two substrates had to be
argued apart. Natively the description is a property of the node. On
the web the message is a real element the browser is already drawing,
and it stands **outside** the field's `<label>`: an implicit label's
subtree text is the field's accessible *name*, so words left inside it
would be read as part of the name rather than as a reason. It is
reached by `aria-describedby` — not `aria-errormessage`, which is the
tighter-fitting attribute and the one screen readers support least
evenly — and that relation computes to the same accessible description
the native snapshot carries. One property, two spellings.

**A ranking carries no `problem`, and that is a refusal**
([elements.md](elements.md#ranking)). The description slot on a ranking
holds the cursor slot's rank and nothing else.

A field the reader is **standing in** carries where their selection is:
byte offsets into the value, on cluster boundaries, the caret being the
case where the two ends meet. Standing in is the field holding focus,
or — while the edit row stands on it
([elements.md](elements.md#text_input)) — the field that row was opened
on, because a menu about a field is not leaving it. Every other field
states nothing: a range on a field nobody is in is state, not a place.
An **obscured** field states nothing either, and the length of what is
selected goes nowhere rather than travelling in a range's clothes — the
slot's whole contract is offsets *into the value*, and that value is
withheld, so the only pairs inside it are dishonest ones. It is the
same line the `problem` draws from the other side: the secret is what
was typed, and offsets index exactly that.

**Which backend carries it is the shortest list on this page, and the
absences are decisions.**

- **The AccessKit bridge — macOS, Windows, Linux — cannot express it
  against this tree, and carries nothing in its place.** AccessKit
  states a selection as two positions, each naming a node whose role is
  a *text run* and indexing that run's own character table; nokre gives
  a field no text-run children, so a position stated against the field
  node would index a table that does not exist. The alternative was to
  spell the fact into the node's description — "3 characters selected"
  — and it is worse: an announcement no platform makes and no app
  wrote, in the slot that holds the app's own words, doubled by any
  screen reader already tracking a caret of its own. A fabricated
  announcement is worse than silence.
- **On the web there is nothing to carry.** A field is a real
  `<input>`, so its selection is the browser's own — like the wrapping
  around it — and core's copy is kept in step with it rather than
  announced beside it ([internals/dom-substrate.md](internals/dom-substrate.md)).
- **iOS and Android reach a caret through the text document, not
  through this node.** `UITextInput` and an `InputConnection` *are* the
  field while it is being edited, and both are answered from
  `App.editableSnapshot` — a different door with a different audience,
  which is why it carries an obscured field's offsets where this one
  will not.

The fact is not left unasserted by any of that: it is pinned in nokre's
own snapshot tests, read by the harness's `expectSelection` and
`expectSelectedText` ([testing.md](testing.md#assertions)), and held to
cluster boundaries by the audit's `malformed_selection`.

**A `ranking` is one element and many controls, so its slots are
derived nodes.** The device is a single focus stop whose value is the
slot the cursor stands on ([elements](elements.md#ranking)); that is
what a keyboard reader hears change under ↑/↓, and on its own it was
the whole of what any reader got — not the other plates, not the ranks
they draw, not the divider's words while it can move, and no control
that moves anything. Each slot is now a child node: a **button** named
by its plate's words, valued by its rank, `selected` while it is the
armed one, `disabled` where the band rules it out, sitting on the swap
button's own rect so a bridge that activates a node by pressing its
rect presses *that* slot. This is the shape the DOM substrate already
shipped — real buttons carrying the same two facts in a visually
hidden run — so the two substrates say one thing.

Three things it deliberately is not:

- **Not a focus stop.** The device is one tab stop and the cursor walks
  it; a slot that took focus would put every plate in the tab order and
  leave the ↑/↓ contract with nothing to move. A slot is activatable
  instead, which is the press a finger makes.
- **Not a custom action.** "Move this up" is not a verb this device
  has — swap is, and it is a pair of presses, so an action named for a
  direction would be a second arithmetic beside `applySwap` and words
  in every language the library would have to own. The one verb is
  already a control; announcing that control is the whole fix.
- **Not a position announcement.** A rank is the app's digits, from the
  same `layout.rankingOrdinal` the plate draws with, and only a counted
  slot has one — which is the fact a reader is told about counted-ness.
  "3 of 9" would be a sentence nokre does not own, and the two bridges
  that flatten their trees (iOS, Android) announce no structural
  position anyway.

What a rank can be is bounded, because a borrowing snapshot points at
comptime strings and the bridge keys each slot's id off its element's:
`Ranking.max_options` is a construction rule
(`error.RankingTooManyOptions`), and a device mutated past it fails the
audit's `unannounced_ranking_slot` rather than being drawn whole and
read short.

**A `dial` is the one adjustable node, and it says where it stands in
two languages.** The device is one focus stop named by its label and
valued by the reading on its plate ([elements](elements.md#dial)),
carrying that same figure — with the range it moves in and the step one
increment takes — as numbers beside it. The words are what a backend
announces and the numbers are what it compares, and no backend can
derive either from the other: a reading is in the app's own digits.

The role is `spin_button` and **not `slider`**, which every backend
would also have taken. A slider is a thumb on a track; what this device
draws is a column of figures moved one detent at a time by two named
controls, which is the stepper ARIA calls a spin button and the widget
iOS and Android both name after a picker. The pixels decide the role,
because a reader told "slider" and finding no track has been told the
wrong thing about the screen.

Behind the role are the two actions that make it worth having —
increment and decrement — and every backend that takes the role takes
them: AccessKit's `Increment`/`Decrement`, VoiceOver's swipe up and
down on the adjustable trait, TalkBack's on a node carrying a
`RangeInfo`, the browser's arrow keys on a `spinbutton`. All four land
on `App.Semantic.dial_step`, which is the door ↑ and ↓ already use, so
the bound and the clamp are answered once.

**The step buttons stay.** A reader on an adjustable node does not need
them, and two extra stops beside a device that can be swiped is noise —
but they are *drawn*, and the DOM substrate cannot hide a real button
from assistive tech without lying about what is on the screen. One
thing said on every substrate is worth more than the two stops it
costs. A button at the end of the range is `disabled` and not
activatable, which is the empty plate beside it said to the reader who
cannot see it.

The value it carries is the reading layout wrote, so what is announced
is the number that was drawn, and the audit's `unannounced_dial`
compares the two by shaping the number a third time rather than by
trusting either; the range is compared against the device the same way.

**Where a dial's value goes when it moves.** On the web the figure is
on the focused element itself — `aria-valuenow` with an
`aria-valuetext` carrying the app's digits — so a browser announces it
as it moves; the reading was an `<output>` while focus stood on a
button beside it, and a live region there would now be the same number
said twice. On iOS and Android the platform re-reads an adjustable
node's value after its own increment gesture, which is what closes the
second case of the gap below.

**A cell is announced with the name of its column.** A table's header
row is drawn once, at the top; three of the five bridges flatten the
tree into a list with no table in it, so a reader below that row used
to meet figures with nothing attached to them. The snapshot spends the
name/value pair on it — the column's words are the cell's *name*, its
own words its *value* — and a cell holding one run of words is that
one node, its text folded in rather than read again beside it
([elements.md](elements.md#table--row--cell) has the shape and what a
cell holding a control does instead). Two slices rather than a joined
sentence: a join would hand both runs the direction of whichever came
first, and a name and a value are two utterances on every backend
regardless. The browser is told the structure instead — `<th scope>` —
and repeats nothing. `unnamed_table_column` states the property over
the derivation.

**A notice is announced by its name, so its name is the whole message.**
The element draws a title and a description ([elements.md](elements.md#notice));
the snapshot joins them into one label (`Notice.reading`, built at
append from the copies the tree just made — `DivergingMeter.reading`'s
mechanism and its reason). The obvious alternative — title as the name,
description in the description slot — was measured against the bridges
and fails on two of five: **Android carries a node's description only
where `invalid` is set** (it is `setError`, the refused field's slot),
and iOS puts it in the hint, which VoiceOver reads late and a reader may
have switched off. What a live region announces on every platform is its
accessible name. On the web nothing changes: the description is a real
`<p>` inside the `role="status"` element, so the browser already
announced both — and because the join is the name and not a second copy,
the message is heard **once** on every substrate. The audit's
`unannounced_notice_description` states the property over the snapshot.

The title's cap stops being a consumer's problem with it. A title
longer than the notice ring's slot is not dropped and not refused:
`notify` keeps the headline that fits — cut where a word ends — and
**rolls the rest into the description**, which is drawn as prose and
read on as part of the name. An app hands `notify` whole sentences and
never splits one against a number of nokre's, which is why that number
is not published.

One further node is derived rather than mirrored from an element: an
acknowledged `copyable` (see [elements](elements.md#copyable)) gains a
`status` child labeled `Copied`, the same polite live region a notice
gets, arriving and leaving with the check in the field. A mark with no
words needs a voice, and it cannot be the element's own: the label and
value stay untouched, because they are what a screen-reader user reads
back to check the value they just copied. The words are the framework's
own — English until an app translates them, like `Close` and `Back`
([localization.md](localization.md#the-frameworks-own-words)).

**Layout is not in the snapshot.** A horizontal row too narrow for its
children [wraps](elements.md#a-row-too-narrow-for-its-children), and a
wrapped row's snapshot is identical to the same row's on a screen wide
enough — same nodes, same order, same names, same states, only the rects
moved. Where a line broke is not a fact about the app, so nobody is told
one. Its counterpart is the exception that proves it: a row of actions
that *folds* does change what is announced, because a folded action is
not on the screen at all (see [elements](elements.md#the-folded-tail-more)),
and that is exactly why folding is reserved for the rows where a control
stands in for what it hid.

## Focus

Focus is a first-class core concept, not a platform afterthought: Tab and
Shift-Tab traverse focus stops in document order with wraparound
([src/core/focus.zig](../src/core/focus.zig)). A stop is usually a whole
element; the exception is a paragraph carrying inline links, which is
not focusable itself but contributes one stop per link, in span order —
so a link inside prose is reached by Tab like any other control, and a
focus target is a node plus an optional span index rather than a bare
node. Traversal is scoped to the
active layer: normally the whole window, but while a sheet or the notices
pane is open, only that layer — the background is inert, so there is
nothing outside the
scope to reach. This is not a focus trap in the WCAG 2.1.2 sense: Esc
always dismisses the sheet on top (or minimizes the pane), and focus
returns to the element that opened it — into the sheet it covered, by
name, when sheets are stacked. The focus indicator — one 2px `ink`
stroke, either standing 2px
clear of the element or taking over the outline the element already
draws, never both at once — comes from the renderer, identically on
every platform. The focus *position* always exists and is always
announced; the drawn indicator is keyboard-origin only — it appears
when focus last moved by keyboard and not when a pointer or touch took
it, because a pointer user knows where they pressed, and a ring there
is redundant noise. Two carve-outs, and only these: a text field
(`text_input`, `text_area`) shows its thickened edge and caret however
focus arrived — keyboard input is about to land there, the same
carve-out every browser's `:focus-visible` ships — and a picker's row
highlight follows focus whichever input moved it, because it marks the
row about to be chosen, not how focus got there. The DOM substrate gets
the rule from
`:focus-visible`; the Skia substrate tracks the origin in core, so the
two agree by construction. There is exactly one focus model to test.

**No gesture is ever the only way to anything.** nokre has one gesture
at all — the edge pan that goes back ([routing.md](routing.md)) — and
what it activates is the Back control the framework already installed on
that screen: a real focus stop, named by the framework, reachable by Tab and by
every screen reader's own navigation. A pushed screen without that
control cannot exist, so there is no state a user reaches the gesture's
destination *only* by dragging. Its threshold is drawn as well as felt,
because a device with haptics off would otherwise leave a sighted user
committing blind, and screen-reader users never need it: VoiceOver and
TalkBack have their own back conventions, and the control is there for
both.

## Enforcement

nokre's position is that a consumer should never face an accessibility
decision at all — the framework already made it. Enforcement therefore
happens in two tiers, and neither is opt-in.

### Invalid trees cannot be built

`Tree.append` rejects malformed structure at the call site — detection
after the fact would mean the bad state existed:

- interactive elements (button/link/toggle/input/segmented/nav item)
  with an empty label — `error.UnlabeledInteractive`
- non-row children of tables, non-cell children of rows, rows outside
  tables, cells outside rows, a row past 32 cells
- a nav off the root, a second nav, non-item children of a nav, nav items
  outside a nav, or a nav mixing its two shapes — the row of destinations
  and the collapsed chip cannot both stand, or the same section would be
  in the focus order twice
- a sheet or notice off the root, a second one of either, an untitled
  sheet, an empty notice
- a `more` control anywhere but on a horizontal stack, or a second one on
  the same row — the folded tail of a row of actions is the framework's
  to install (`error.MoreOutsideButtonRow`, `error.MultipleMoreControls`)
- a heading at level 1, or a `document` whose `base_level` is `.h1` —
  the page's top is the screen's title, stated once and drawn by the
  library (`error.HeadingAtTitleLevel`, below)
- choice controls (segmented, radio group, select) with fewer than two
  options, empty option labels, or a selection out of range
- a malformed ranking: fewer than two options, an empty option, no
  divider words, a band reaching the option count, an inverted band, a
  count outside the band, or an input-owned field (`cursor`, `armed`)
  set by hand — a screen cannot open mid-swap
- a malformed dial: a floor below zero, an inverted range, a range
  holding one value — that is a reading, not a device — a value outside
  it, a range past `Dial.max_digits`, or a `reading_buf` set by hand,
  which is layout's to write
- empty badges, valueless copyables, wordless or out-of-range meters of
  either kind — a diverging meter needs all three sets of words —
  unlabeled/valueless/unencodable QR codes
- a `link` or a span stating a language that is not a language tag —
  `error.InvalidLangTag`. A run in a language other than the page's says
  so with `lang` (WCAG 2.2 **3.1.2 Language of Parts**, AA — a language
  chooser is that criterion's textbook case), and a malformed tag is an
  attribute a browser drops without saying so, which fails the reader
  exactly as no tag would. It is a grammar and not a registry: nokre
  checks that your value is a tag, never that it is *the* tag, on the
  line the origin rule draws ([static-sites.md](static-sites.md))
- text that would be illegible where it sits: any element drawing text on
  the ambient background (text, headings, links, toggles, inputs) must
  clear WCAG AA contrast (4.5:1) against the nearest box fill, **in both
  appearances** — the two ramps are independent, so a pair can clear the
  floor in light and fall under it in dark — `error.InsufficientTextContrast`
- text that would be a glare source: the same pair must also stay at or
  below 16:1. True ink on true paper is 21:1, which is past the point
  where contrast buys legibility — `error.ExcessiveTextContrast`

#### One page, one top — and it is stated, not found

A page's outline starts at its title, and nokre asks for that title
rather than looking for it. A routed screen already stated it once, at
the route table, so the library draws it (`RouteDef.title`,
[routing.md](routing.md)); a screen whose reader-facing title is
per-reference restates it with `App.setTitle`, and `setTitle("")` says
this screen draws none. Every other append at level 1 is
`error.HeadingAtTitleLevel`.

This replaced an audit rule, `multiple_h1`, and the trade is worth
recording so it is not re-litigated:

- **What the old rule enforced is not normative.** HTML5's sectioning
  permits several `h1`s, and nothing in WCAG says otherwise — unlike
  the citations on this page for focus (2.1.2), contrast, and target
  size (2.5.5/2.5.8). Its basis was screen-reader outline navigation
  and the outline a search engine builds. Failing a build over a
  convention, while presenting it beside cited rules, was the defect.
- **So it stopped being a rule about your content.** It is now a
  consequence of the library owning the page's top: you are never told
  you wrote two tops, because you were never able to write one.
  nokre's position — one page, one top — is unchanged and is still
  nokre's own, but it is now the shape of the API instead of a lint.
- **A page with no visible top became statable.** Under the old rule
  the outline started at whatever `h1` was found, and
  `heading_level_skipped` counted from 0, so a page whose first heading
  was `h2` failed as well: "no title at all" was not an available
  shape. It is now, and it is said out loud rather than worked around.

Structure is refused; encoding is repaired. Every string entering
tree-owned memory — append fields and spans, choice options,
`setContent`, an IME update, typed text — is validated during the copy
the tree already makes, each invalid sequence becoming one U+FFFD
(maximal subparts, deterministically). The tree holds only well-formed
UTF-8, so a fetched document carrying arbitrary bytes renders as text
and every scan downstream trusts sequence lengths instead of
re-checking them.

Mutation faces the same gates: `setContent` on a `text` element re-runs
the append contrast check once the new content has visible words
(`error.InsufficientTextContrast`, the element untouched on refusal),
and on a field it clamps a stale caret to a codepoint boundary rather
than leave it dangling mid-sequence.

`App.setNav` additionally rejects a roster outside 2 to
`nav.max_nav_items` (`error.NavItemCount`), a destination the route
table does not have (`error.UnknownRoute`), one whose route takes
arguments (`error.RouteArgCount`), and a set where some destinations
carry a glyph and others do not (`error.NavIconsMixed`) — an unnamed,
unpressable or half-marked destination is refused at the roster rather
than drawn.

The design system itself is proven, not reviewed: unit tests in
[src/core/color.zig](../src/core/color.zig) assert that every text alias
sits inside the readable band — at or above WCAG AA and at or below 16:1
— on paper in both appearances, that component boundaries clear non-text
contrast (3:1), and that the dark ramp *eases* text rather than mirroring
it (an inversion would leave dark exactly as harsh as light, which is the
wrong answer for the appearance where halation is worse); a test in
[src/core/layout_test.zig](../src/core/layout_test.zig) asserts that no
interactive element can lay out below the 24×24 minimum target size
(WCAG 2.5.8), and a second one that every control which is *nothing but
a target* — a bare glyph (`icon_button`, `back`, `sheet_close`, an
glyph-form `button`, the notices indicator) or a `checkbox`/`toggle` row —
lays out at the full 44×44 of WCAG 2.5.5 (AAA), which is also Apple's
44pt. The 24px floor is what conformance permits; it is not a size a
finger can reliably hit, and a control with no pill and no words draws
no border to say where it ends.
Changing a palette byte or a metric that breaks compliance fails the build.

### The audit

[src/testing/audit.zig](../src/testing/audit.zig) covers the residue that
construction cannot see: whole-tree content rules, and state that later
mutation or removal could degrade. The harness runs it automatically at
init and after every driver action — there is nothing to remember. It
fails on:

- `heading_level_skipped` — a heading more than one level deeper than
  the previous heading (h2 → h4 with no h3 between). The sequence
  starts at level 1 whether or not a title is drawn, because level 1 is
  the screen's either way, so a page opens at `h2` and a page that
  opens at `h3` has skipped one
- `duplicate_interactive_label` — two enabled interactive elements with
  the same accessible name are ambiguous to voice control, to screen
  reader users, and to test queries alike. It is the *name* that must be
  unique, not the words: a roster of rows each ending in "Remove" passes
  as soon as each button states its own `accessible_name`, and two
  buttons whose visible words differ still collide if their names are
  equal. Judged within the active
  layer only: everything behind an open sheet, picker, or notices pane
  is inert and cannot collide with what is in front of it — and the
  audit re-runs when the layer closes, catching a pair the moment both
  are live
- `unlabeled_interactive` — a label emptied by mutation after append
- `nav_item_count` — a nav whose destinations fell outside 2 to
  `nav.max_nav_items`, or whose rendered shape stopped matching the set
  it was given (removal). The off-roster marker is not a destination and
  is not counted
- `empty_nav_here` — the off-roster marker's title emptied by mutation
  after append; a plate with no words says you are nowhere
- `malformed_segmented` / `malformed_radio_group` / `malformed_select` —
  options or selection mutated into an invalid state
- `malformed_ranking` — a ranking mutated out of shape: the defects
  append refuses, or a cursor or armed slot past the last slot
- `unannounced_notice_description` — a notice whose description is not
  inside the name the snapshot carries. A live region is announced by
  its name, and the slot beside it reaches two bridges of five, so
  prose that is not in the name is drawn and never heard. Stated over
  the snapshot for the rule below's reason: the join is a derivation,
  and a rule reading the element's two fields would agree with itself
  while the reader got one of them
- `unnamed_table_column` — a cell in a table that declares a header row
  which the snapshot announces without its column's name. A column
  header is drawn once, at the top, and every row under it then reads
  as bare figures; what produces it is a header row that stops short of
  a body row's columns, or a header cell holding something that is not
  words — a badge, a control — and so has no name to lend. A table with
  no header row is not this rule's business, and neither is a cell that
  names its own row (`Cell.header`): the stub column it stands in is
  the one column a table with row headers leaves unnamed on purpose.
  Asked of `semantics.columnWords`, the one derivation that decides
  what a reader hears, rather than of the header row a second time
- `unannounced_ranking_slot` — a ranking slot the snapshot does not
  carry, does not name, or leaves nothing to press. One of the two rules
  that read the a11y snapshot instead of the tree, and that is the point:
  the derivation is what regressed, and a rule stated over the tree
  would have agreed with itself while the snapshot said nothing. A
  counted slot's value must also be the rank its plate draws, so a
  device that outgrew `Ranking.max_options` fails here rather than
  announcing short
- `malformed_dial` — a dial mutated out of shape: a floor below zero,
  an inverted or singular range, a value outside it, or a range past
  `Dial.max_digits`. Its label is not this rule's business — a dial is
  one focus stop with a name, so it stands with the controls
  `unlabeled_interactive` and `duplicate_interactive_label` hold
- `unannounced_dial` — a dial the snapshot does not carry, whose value
  is not the reading its plate draws, or whose step buttons are
  missing, unnamed, or wrong about what a press can still do. Stated
  over the snapshot for the rule above's reason, and the number is
  shaped again here rather than read off the element: the snapshot
  borrows that reading, so the two agree by construction and a layout
  pass that stopped settling would leave one stale figure standing in
  for both
- `insufficient_text_contrast` / `excessive_text_contrast` — an ink or box
  fill mutated after append into a pair that is illegible in either
  appearance, or harsh enough to glare
- `sheet_missing_dismiss` — an open sheet with no enabled button left in
  it; Esc still works, but pointer users need a visible way out
- `untitled_document` — a `document`'s label emptied by mutation after
  append; the label is its accessible name, and nothing else in a
  parsed document can stand in for one
- `malformed_progress` — a button's `progress_percent` pushed past 100,
  or work cleared while a number is left behind: a meter measuring
  nothing is the one thing worse than no meter
- `untitled_sheet` / `empty_notice` / `empty_badge` / `empty_copyable` /
  `malformed_meter` / `malformed_qr` — content emptied or degraded by
  mutation after append
- `empty_code_block` — a verbatim block emptied by mutation, leaving a
  tab stop over blank space
- `wordless_problem` — a text field whose `problem` is present but
  holds nothing but whitespace. The invalid state is *derived* from
  those bytes, so this is a field every assistive technology calls
  refused with no reason given: the exact defect the slot exists to
  abolish, reached from the other side. Not an `append` refusal,
  because no other string field in nokre looks past its UTF-8 check,
  and one field inventing a stricter door would be a rule the rest of
  the set does not keep
- `unfixable_problem` — a text field carrying both `problem` and
  `disabled`: it states what is wrong with the value and refuses the
  correction, which is a dead end no keystroke leaves. The pair has no
  honest producer — the form disables on submit, the server refuses,
  and the field is re-enabled *and* given its problem in the same frame
  — so what reaches it is a controller that set the reason and forgot
  to lower the flag, a bug the app cannot see and every screen reader
  can
- `malformed_selection` — a text field whose selection is not a place
  a caret can be: either end past the value, or inside a character
  rather than between two. Both ends face `segment.clusterFloor`, the
  one vetting rule every road into a field already runs — `append`,
  `setContent`, and a shell stating a range — so the rule states that
  the rule held rather than offering a second opinion about what a
  caret position is. What it catches is a road that skipped it: a
  `cursor` written into the element by hand, or a future edit that
  gives some new caller a way to move an offset without the clamp. The
  cost of a miss is not cosmetic — a range that splits a codepoint
  hands the measurer, the renderer's highlight and the snapshot above
  invalid UTF-8 out of a field the user is holding
- `empty_list` — a `list` with no items. This one is not about
  mutation: a list is appended before its items exist, so `append` has
  nothing to check and the whole-tree pass is the only place the rule
  can live
- `unresolvable_route` — a `link`, `tile`, `nav_item`, `notice` or
  inline span whose route reference the router cannot honor: a dead end
  wearing an interactive face. Not about mutation either — `append`
  cannot check it, because the tree has no router; this pass has the
  whole App and asks it. Spans inside a `document` are exempt: there a
  destination belongs to the document lane (the browser, or a site
  generator's own resolver), not the route table — one that does route
  in-app is still caught at activation, by the refusal record. The
  audit gate also fails on that record and on a raised notice routing
  nowhere ([routing.md](routing.md), errors and refusals)
- `desk_without_main` — a `desk` screen with no `main` region. Without
  one the desk has neither a remainder to give the band nor anything to
  show when it folds. `append` cannot catch it: a builder states its
  roster before its main, so the set is only whole here — exactly
  `empty_list`'s argument
- `unshipped_icon` — an icon whose glyph the artifact's own face does
  not carry, which draws as a blank box. The face is the glyphs the
  sources spell, derived by scanning them
  ([elements.md](elements.md#icon)), and that scan reads literals — so
  this is the backstop for its one blind spot, an icon chosen from data
  the sources never name. The fix is to spell the name somewhere, which
  also makes the choice greppable
- `cleanly_clipped_scroll_region` — an overflowing fixed-height scroll
  region whose offset-0 edge cuts nothing visible. At rest the bar is
  quiet or not drawn at all, so the mid-element cut is what makes the
  overflow perceivable; an edge landing in a gap, on an element
  boundary, or in a text line's leading reads as complete content.
  Fill (null) heights, a desk `region`'s band height and the picker's
  list all resolve against the viewport and are exempt — a rule firing
  at one window size and not another would be unfixable. The scope is
  the **viewport**, which nothing declares, and not the medium, which
  an app does ([testing.md](testing.md), "The audit matrix"). The
  scroll bar presentation is not a scope either: the rule runs in the
  layout the app stands in and again in the other layout a
  presentation can put it in — an interactive bar reserves its strip
  and rewraps what is beside it ([elements.md](elements.md#scroll_region))
  — and a failure names the layout it failed in. Two layouts are every
  one there is, so a pass holds under every presentation

Because the audit inspects the same tree that renders, a passing audit is a
real guarantee, not a lint heuristic.

**Skipping a rule, and the one reason to.** `audit.collect` takes
`Options.skip` — rules whose findings are dropped from its list, with
everything else still fatal-grade. It is not a severity dial and it is
not a suppression list for findings somebody has not got to: the only
sanctioned use is a caller that has *replaced a rule's authority with a
stricter one of its own*. The known case is a static-site generator
skipping `unresolvable_route`: on that substrate a document's destination
belongs to the site's own resolver rather than to any route table, and
that resolver already fails the build on a reference it cannot honor,
which is harder than this rule's answer. Skipping a rule nothing else
checks is turning the guarantee off. The boundary that sanction is read
off — which destinations are a generator's and which are the library's —
is [static-sites.md](static-sites.md).

The default skips nothing, and `audit.audit` — the one the harness runs
at init and after every driver action — has no way to pass anything
else. So an app's own test suite cannot skip a rule at all: the knob
exists for a generator holding the whole tree, not for a screen.

## Reaching assistive tech

The `Snapshot` is produced and tested platform-independently; each
platform shell attaches an adapter that feeds it to the OS —
[AccessKit](https://accesskit.dev) on desktop, UIAccessibility on iOS,
an `AccessibilityNodeProvider` on Android. On the web there is nothing
to feed: the DOM the app renders *is* the accessibility tree, not a
mirror of one. Bridge work touches zero application code, so the
backend is a shell property: the [README](../README.md) support matrix
lists each platform's, and
[internals/platform-shells.md](internals/platform-shells.md) shows how
the bridges are built.

**Where "polite live region" stops being literal.** A `status` node —
a notice, a stand-in, the copy acknowledgement — is a live region to
the two backends that have the concept: the browser's `role="status"`
and AccessKit's. UIKit has neither, and on Android a live region mode
is read off the node an event is *sourced at* — every content-changed
event that shell sends is sourced at the host view, which carries no
words. So both flattening shells say the arrival themselves:
`UIAccessibilityAnnouncementNotification` on iOS,
`announceForAccessibility` on Android.

What is announced is the node's **name**, which is the whole message by
construction (`Notice.reading`), and what makes it an arrival is the
set of names standing at the last update: a status that was already
there is not said again, so a screen rebuilt under a reader does not
repeat itself. The first set seen after a reader starts is adopted in
silence — a notice raised while nothing was listening is on the screen
to be read, not shouted.

That is *why* what those nodes carry is the whole message rather than a
headline: being read is the guarantee that holds everywhere, and being
announced now rides on the same words.

A [`dial`](elements.md#dial)'s value is the other half of what
[roadmap.md](roadmap.md) §3 named, and it arrives from the other side:
the number is on the node the reader is standing on, and both
flattening platforms re-read an adjustable node's value after their own
increment. On iOS the shell restates that value from a fresh snapshot
as it performs the step, because the element VoiceOver is holding was
built before it.
