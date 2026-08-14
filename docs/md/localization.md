# Localization

nokre reads the same catalog format Flutter does — ARB, one JSON file
per locale, ICU message syntax — and then takes a different road: no
`l10n.yaml`, no generated file, no runtime parsing. The `.arb` sources
are embedded and compiled at comptime; the catalog *is* the code.

```zig
const L = h.l10n.Bundle(&.{
    @embedFile("l10n/app_en.arb"), // first source = the template
    @embedFile("l10n/app_fa.arb"),
});

// In a build function or action: the app's chosen locale (App.setLocale)
// picks the catalog.
const loc = L.resolve(app.locale());
const b = app.root();
try b.heading(.h2, L.tr(loc, .inboxTitle));
try b.text(try L.fmtIn(&app.tree, loc, .nUnread, .{ .count = unread }));
```

`Bundle` returns a type: `Locale` (one enum field per source, named by
its `@@locale` — `"pt-BR"` becomes `.pt_BR`), `Key` (one field per
message id), and the calls:

| Call | Contract |
| --- | --- |
| `tr(locale, .key)` | A message with no placeholders, as a slice of constant data. No buffer, no error. Calling it on a message *with* placeholders is a compile error pointing at `fmt`. |
| `trAny(locale, key)` | `tr` for a key that exists only at **runtime** — a table-driven label (month words, enum-indexed captions) where `tr`'s comptime key would force a switch per arm. One read of a comptime-generated dense table, the same constant bytes `tr` returns. A key whose message has placeholders is a programming error and panics naming the key — the runtime twin of `tr`'s compile error. |
| `fmt(buf, locale, .key, args)` | Formats into the caller's buffer, returns the written slice. `args` is an anonymous struct with exactly the message's placeholders — a missing, extra, or mistyped field is a compile error naming the message. The only runtime error is `NoSpace`: text is never silently truncated. |
| `fmtIn(tree, locale, .key, args)` | `fmt` into the tree arena — `Tree.fmt`'s contract for a catalog message, and the form for a label the tree is about to store: no buffer to size, no `NoSpace`, the slice valid for the tree's lifetime. Placeholders are checked exactly as `fmt` checks them. `fmt` remains the form for bytes that outlive the tree (storage keys, worker messages). |
| `resolve(tag)` | Runtime tag → bundled locale: exact match first (case and `-`/`_` ignored), then bare-language match in source order, then the template. `"fa-IR"` finds `.fa`; `"de"` against an en/fa bundle yields `.en`. |
| `of(app)` | `resolve(app.locale())`, made once, as a **bound view**: `L.of(app).tr(.key)`, and likewise `trAny`/`fmt`/`fmtIn`/`tag`/`dir`/`chrome` with the locale argument gone and the resolved locale readable as `.locale`. A value, not a reference — honest because a build or an action is one moment in one locale. Takes anything that answers `locale()` with a tag (the App, a test harness). |
| `in(app)` | `of`'s twin for the one call that allocates: the locale **and** the tree the bytes land in, both from the app. `try L.in(app).fmt(.key, args)` is `fmtIn` with nothing re-passed — at a build site the tree is always `&app.tree` (a `Cursor`'s `tree` is that pointer), so naming it beside the app was only a chance to name the wrong one. `fmt` here means the arena; the lifetime is `fmtIn`'s, unchanged. A second binder rather than a wider `of`, because `of` needs only `locale()` and nothing that knows just its locale should lose a call. |
| `chrome(locale)` | nokre's own words (`App.Chrome`) out of this catalog, via one **reserved key per field** — see [The framework's own words](#the-frameworks-own-words). |
| `tag(locale)` | The locale's **BCP 47 tag** — what `App.setLocale` takes, what a `lang` or `hreflang` attribute carries, and what storage keeps. It is the `@@locale` with an underscore read as the subtag separator it stands in for, so a catalog spelled `pt_BR` (Flutter's convention, and this repo ships one) yields `"pt-BR"`. The field name keeps the underscore because a Zig identifier must; the tag does not, and a tag the library published that its own `element.validLangTag` refused was a byte a browser dropped in silence. |
| `dir(locale)` | The locale's writing direction (`l10n.Direction`), read from its tag at comptime. Feed it to `App.setDirection` to mirror the chrome — see [Right-to-left](#right-to-left). |

There is no allocation anywhere, and no state in the bundle: which
locale the app is *in* is the **App's own state** — chosen with
`App.setLocale` (or `Options.locale` at boot), read back as a tag with
`App.locale()`, "" until chosen — so every screen, controller, and
route title reads one live fact instead of keeping a copy a change
could miss. Which locale the *device* wants is the `locale` service
([services.md](services.md)) — on a page nokre generated it is the
language that page was written in, reported on the same lane and
resolved by the same line — and `resolve` is the bridge:

```zig
// The device picks the catalog, the catalog decides the rest.
const dev = h.services.locale.tag(app);  // "fa-IR", or "" if it won't say
const loc = L.resolve(dev);              // "" and unbundled → the template
try app.setLocale(L.tag(loc));           // the app is now *in* that locale
app.setDirection(L.dir(loc));            // see Right-to-left, below
```

A device tag nokre's bundle doesn't carry is not an error state, it is
the template — the fallback `resolve` was written for. A language
switched mid-session runs the same lines from the service's change
handler; the chosen tag is App state, so reading it per frame costs
nothing.

`setLocale` is also what a *generated* page says it is in: the third
line above is where the `lang` attribute on a serialized document comes
from, so an app that renders pages without it publishes them claiming a
language it may not be speaking. The one page it does *not* answer for
is the web app's shell — that one is written by the build before any app
exists, boots into an empty body and follows the reader's own device, so
its `lang` is declared instead: `.web_lang`
([getting-started.md](getting-started.md)).

A static site that publishes every locale runs those same lines once per
`L.Locale` and writes its tree again inside the loop — the loop, the
output paths and the URL scheme are the generator's, and nokre asks for
no list of locales anywhere, since the bundle is the list. The one page
it *does* write for you is the chooser at an unprefixed address, whose
script resolves the reader's tag through the rule above rather than a
second one: `dom.localeStub`, in
[internals/dom-edition.md](internals/dom-edition.md#the-locale-axis-and-the-one-page-that-is-about-the-reader).
The other thing it writes for you is the `hreflang` set those copies
annotate each other with — `dom.Alternates` takes the bundle rather than
a list of tags, as everything here does, and the `x-default` it adds is
the chooser's address rather than any language's
([the alternate set](internals/dom-edition.md#the-alternate-set-and-the-two-writers-that-spend-it)).
What it does **not** write for you is the chooser a reader finds in a
page's footer rather than at an unprefixed address — that is a `stack`
of `link`s your page builder appends, one per `L.Locale`, each labelled
with the language's name in that language. Two things about those
anchors are worth stating because both are easy to get wrong from the
outside. Their `hreflang` is already in the head, over the whole
alternate set, so a copy on the anchor tells a crawler nothing. Their
**`lang` is not**, and it is the one a reader hears: `Link.lang` carries
the tag so a screen reader says `فارسی` in Persian rather than with
English phonemes (WCAG 3.1.2, and [elements.md](elements.md#link) has
the grammar `append` holds it to). Pass `L.tag(loc)` — the same tag the
alternate set takes, off the same bundle — because a string typed by
hand is the mistake the field exists around.

Which half of a generated site is the library's and which is the
generator's, past the locale axis, is
[static-sites.md](static-sites.md).

## The format

An ARB file is a JSON object. `@@locale` is required — nokre embeds
file contents, so there is no filename to infer from. Either separator
is accepted (`pt-BR`, `pt_BR`); `L.tag` publishes the BCP 47 spelling
whichever was written, and a tag that is not one at all (`Persian`,
`tr-`) fails the build where the catalog is read. `@@`-prefixed
provenance (`@@author`, `@@last_modified`, `@@x-…`) is accepted and
ignored. Each message may carry `@message` metadata, and only the
template may carry any of it at all
([What the compiler checks](#what-the-compiler-checks)). Three fields
are read: `placeholders`, `identical`
([Words a language really shares](#words-a-language-really-shares)) and
`sense` ([What the build checks](#what-the-build-checks)) — that last
one by the build's own checker and by the drafting tool's prompt
([The glossary](#the-glossary)) rather than by the compiler, which
ignores it. `description` and `example` are for translators and
tooling.

```json
{
  "@@locale": "en",
  "inboxTitle": "Inbox",
  "nUnread": "{count, plural, =0{All caught up} one{# unread message} other{# unread messages}}",
  "@nUnread": {
    "description": "Unread badge line under the inbox heading",
    "placeholders": { "count": { "type": "num" } }
  },
  "fromSender": "From {name}",
  "@fromSender": {
    "placeholders": { "name": { "type": "String", "example": "Ada" } }
  },
  "pronoun": "{gender, select, male{he} female{she} other{they}}"
}
```

Supported message syntax, deliberately Flutter-compatible:

- **Placeholders** — `{name}`, typed by metadata: `String`,
  `int`/`num` (both are integers here; counts are integers, and
  fractional plurals would drag float formatting into core), or
  nokre's own `date` (below). An undeclared placeholder defaults to
  String, or to the kind its usage implies (a plural count is an int,
  a `{name, date, …}` reference a date).
- **Dates** — `{when, date, skeleton}` over a **civil date the caller
  supplies**: any struct with integer `year`, `month`, `day` fields —
  `l10n.Date`, `l10n.dateFromMillis(millis)` for the epoch
  milliseconds servers speak (integer Hinnant math, UTC), or a domain
  model that already carries the three. The skeleton set is closed:
  `y`, `M`, `d` render one unpadded component; `MMM` renders the
  month's *word*; `yMd` is ISO 8601 `y-MM-dd`, the locale-blind
  numeric form. Order and separators belong to the message — each
  locale writes the components where it wants them, the same authority
  translators hold over every other word — which is why the combined
  text skeletons (`yMMMd`) don't exist: they would fix an order the
  message can already state.

  ```json
  "dateLabel": "{when, date, d} {when, date, MMM} {when, date, y}",
  "@dateLabel": { "placeholders": { "when": { "type": "date" } } }
  ```

  `MMM`'s words are the catalog's, not nokre's: the twelve **reserved
  keys** `monthJan` … `monthDec`, ordinary messages required (at
  compile time) the moment any message uses `MMM`, in every locale the
  bundle carries. Digit shaping applies to date numbers exactly as to
  counts. A bare reference to a date placeholder (`{when}` with no
  skeleton) is a compile error — a date without a format would have to
  guess one, which is the locale-library behavior this kind exists to
  refuse. No clock and no zone anywhere: the value is the caller's,
  so the same arguments are the same bytes forever.
- **Plurals** — `{count, plural, =0{...} one{...} other{...}}`: `=N`
  exact matches (which win over categories, per ICU), the six CLDR
  category keywords, and `#` for the count. Nesting is allowed, and `#`
  inside a select nested in a plural still means the enclosing count.
- **Selects** — `{gender, select, male{...} female{...} other{...}}`:
  case-sensitive match, `other` mandatory, unmatched values fall to it.
- **Escaping** — ICU quoting as Flutter's `use-escaping: true`, always
  on: `''` is a literal apostrophe; `'` opens a quoted run only
  immediately before `{`, `}`, or a plural's `#`, so prose apostrophes
  (`Isn't`) pass through unquoted. A literal brace is `'{'`.

Integers render with no grouping separators, in the digit shapes of the
catalog doing the formatting: a `fa` catalog writes Extended
Arabic-Indic digits (۰–۹, U+06F0–U+06F9), an `ar` catalog Arabic-Indic
(٠–٩, U+0660–U+0669), and every other locale ASCII. The shape is read
from the language subtag of the `@@locale` tag against a fixed table —
there is no setting, because the locale already is the decision — and
each set is a ten-codepoint substitution, so the same count is still
the same bytes on every platform; the determinism argument that refuses
NumberFormat does not reach it. Digits only: the minus sign stays ASCII
`-`, and there are no separators to localize. Plural categories are
selected on the numeric value, never on the shaped string.

The table is not the catalog's alone. It lives in `core/lang.zig`
(`digit_langs`, `digitsOfTag`), below `l10n`, because an **ordered
list's ordinals** are the same question asked by a layer that has no
catalog: `layout.listMarker` numbers ۱ ۲ ۳ in a Persian app and 1 2 3
in an English one, from `App.digits` — which is derived from
`App.setLocale`'s tag and has no setter of its own. Unlike
`setDirection`, whose mirror is a choice an app may decline, what a "3"
looks like in a language is the language's; a setter would be a knob
two apps could disagree on and one an app could forget, which is the
Latin-digits-in-Persian bug it exists to prevent. The DOM edition
answers the same table from the other side: the browser draws the
ordinal there, so the stylesheet carries one `ol.list:lang(…) {
list-style-type: … }` rule per row, generated from `digit_langs`
through an exhaustive switch — a language added to the table is a
compile error until the CSS counter style is named, so the two editions
of one document cannot number it differently.

## Right-to-left

There are two questions here, and nokre keeps them separate: which way
the *text* reads, and which way the *chrome* is laid out.

**Text is decided by the text.** Persian and Arabic render correctly
with nothing declared: direction is derived from the string itself (UAX
#9's first-strong rule, per hard paragraph), an RTL paragraph
right-aligns its lines, embedded Latin and numbers take their own
left-to-right runs, and Arabic script shapes through the bundled
companion face. **Numbers** means Arabic-script digits too, and that
sentence was false until revision 55: the renderer picked a run's
shaping direction from whether it was Arabic *script*, and Extended
Arabic-Indic digits are Arabic script and bidi class EN — so `۷۴`
shaped right-to-left and printed `۴۷`. A Persian balance screen showed
47 credits to a reader holding 74, beside an ASCII table that was
correct. Face and direction are two questions now, not one, and
`tests/golden.zig` asserts the order in pixels. There is no `dir`
attribute and no per-locale direction
flag in ARB — a Persian string in an English locale and an English
string in a Persian locale each lay out correctly on their own evidence.
This never depends on the setting below.

**Chrome is decided by you.** Whether the interface mirrors —
navigation order, field labels, chevrons, toggle knobs, scrollbars,
table columns — is `App.setDirection(dir)`, one call, defaulting to
`.ltr`. It is not inferred from the strings on screen, because the same
screen can carry both scripts; it is a property of the locale, which the
locale knows. The bridge is in the bundle:

```zig
// On locale change (and once at startup), beside setLocale:
app.setDirection(L.dir(loc));   // L.dir(.fa) is .rtl, L.dir(.en) .ltr
```

`L.dir(locale)` reads the direction from the `@@locale` tag at comptime,
and is what the three lines above pass on: the chrome mirrors the
language actually on screen — the *resolved* locale — not the one the
device asked for. For a tag that never passes through a bundle (a saved
preference, a tag echoed back by a server, the device tag when you
branch on it before resolving), `l10n.directionOfTag("fa-IR")` does the
same at runtime: an explicit script subtag decides (`az-Arab` is RTL,
`az-Latn` LTR), otherwise the primary language subtag's default script
does, and anything unknown — the empty tag included — is `.ltr`. Both
return `l10n.Direction`, which is what `setDirection` takes.

Under `.rtl` every leading/trailing choice flips together: intrinsic
blocks and tables snap to the right, horizontal stacks and nav slots run
right-to-left, field labels and values lead from the right, the back and
tile chevrons point the other way, toggle knobs travel the other way,
and the overlay scrollbar moves to the left. Two things deliberately do
*not* follow the chrome: paragraph text still aligns by its own content
(an English caption stays left-aligned inside a mirrored screen), and a
QR code's modules never mirror — a mirrored symbol does not scan. The
vertical axis is direction-blind throughout, so `↑`/`↓` in a radio group
mean the same thing in both, while `←`/`→` swap with the layout.

### A value that opens in the other direction

One place needs both answers at once, and it is the catalog: a value
sits in a locale whose direction the `@@locale` tag already states, so
the string is not all the evidence there is. A Persian value that opens
on a Latin token — `FQDN (مثلاً company.com)`, `iOS ۱۶ یا بالاتر`, a
cloud vendor's name — has `L` as its first strong character, so P2 lays
the whole line left to right inside a right-aligned page, with the
sentence-final full stop at the wrong end. Nothing in the bytes looks
wrong; the defect exists only once the text is laid out.

`Bundle` settles that at comptime, where both facts are in view: a value
whose locale disagrees with its own first strong character is compiled
with the matching mark in front of it — U+200F RIGHT-TO-LEFT MARK in an
RTL locale, U+200E LEFT-TO-RIGHT MARK in an LTR one. The catalog keeps
the author's bytes; `tr`, `trAny`, `fmt`, `fmtIn` and `chrome` return
the corrected ones. No consumer call changes, and **user-supplied text
is untouched, because it never passes through a bundle.**

Three rules bound it, and each is load-bearing:

- **Only a value carrying both directions is corrected.** A value
  written in one script is that script whatever locale it sits in:
  `English` in a Persian language picker stays a Latin label, `فارسی`
  in an English one stays a Persian one. That is a structural
  distinction rather than an exemption list, and it is what keeps this
  from overriding "text is decided by the text".
- **A value that already opens with a bidi control is left exactly as
  written.** The author stated the direction and nokre defers. Both
  marks are *strong* characters, so without this rule a deliberate LRM
  at the head of a Persian value would read as a disagreement and take
  an RLM in front of it — inverting the override it was written to
  state.
- **Only the leading position is read.** A mark placed inside a value is
  the mechanism for mixed content and is never touched.

A value that opens with a **placeholder** is read too, and what decides
it is what the argument can substitute. `{alias} از این سازمان حذف
شود؟` is a Persian sentence whose first strong character belongs to a
display name the user typed: a Latin alias lays the whole confirmation
left to right and puts the question mark at the wrong end, and a Persian
one does not — the same value renders both ways depending on whose name
is in it. The literals are the evidence the catalog does have, and they
are Persian, so the value takes its locale's mark like any other. This
is not the chrome overriding content: `hasStrong` still has to find the
locale's own direction in the words the translator wrote, and a value
whose literals carry none — `{name} {version} ({build}) · {installer}`
— is still left exactly as written.

Which leading placeholders qualify is the whole of it:

- **A leading `plural` or `select`, or a `{when, date, …}`, is not
  marked, and that is correct rather than a gap.** A plural renders its
  count first and digits are bidi class `EN`, not strong, so P2 walks
  past them to the branch's own Persian words and already finds RTL. A
  select renders a branch the translator wrote. Nothing is wrong to fix,
  and a mark would only change bytes.
- **A leading simple placeholder is marked iff it can carry strong
  text** — declared `String`, or declared nothing at all. An `int`
  argument is digits by the same reasoning as a plural count.
  Undeclared counts as possibly-strong on purpose: a needless mark on a
  value already in its own direction is invisible, while a missing one
  is the defect this rule exists to catch.

The arms are symmetric, and the left-to-right one is not decoration:
`{recipient} will receive` is an English line whose first strong
character is a display name, so a Persian alias turns it right to left
and moves its punctuation. English values that open on an argument
therefore render with a leading U+200E — invisible, zero-width, and it
is why an assertion on such a value's rendered text carries the mark.

What is still left to the rendered string is the other half of a mixed
value: a **leading literal that carries no strong character of its own**
— an opening quote or bullet before the argument — still hands the
decision to whatever the runtime substitutes. Only the first segment is
read, in both rules.

## The chrome nokre writes

Two things on a screen carry words the app never typed at the point they
appear: what a **screen** is called, and what nokre's **own controls**
are called. Both are localizable, from their own home, and a locale
change says all of it in three lines beside `setDirection`:

```zig
fn applyLocale(state: *State, loc: L.Locale) void {
    state.app.setLocale(L.tag(loc)) catch {}; // what each screen is called
    state.app.setChrome(L.chrome(loc));       // nokre's own words
    state.app.setDirection(L.dir(loc));       // which way the chrome runs
}
```

**A screen's name is the route table's** — `RouteDef.title`, which every
line of the nav is labelled from ([routing.md](routing.md)): the
destinations, the collapsed chip's section, the rows of the picker it
opens, and the marker for a screen that is none of them. That is one
home on purpose, so a nav and a screen's own chrome cannot disagree. A
translated app declares each title as a **function of the chosen
locale** and the one table serves every language:

```zig
const routes = nok.Routes(State).table(&.{
    .{ .name = "notes", .title = .{ .of_locale = notesTitle }, .build = buildNotes },
    .{ .name = "note", .title = .{ .of_locale = noteTitle }, .args = 1, .build = buildNote },
    .{ .name = "settings", .title = .{ .of_locale = settingsTitle }, .build = buildSettings },
});

fn notesTitle(tag: []const u8) []const u8 {
    return L.tr(L.resolve(tag), .notesTitle);
}
```

The **chosen locale is the App's own state**: `Options.locale` for an
app that knows it at boot, `App.setLocale(L.tag(loc))` whenever it
changes, `App.locale()` to read it back, and `""` — the tag of an app
that never chose — until then, which `resolve` already reads as the
template. Pass the tag of the locale actually on screen (the *resolved*
one), so the titles and the catalog agree. A title function must answer
**every** tag with constant data — `tr` hands back exactly that — and
`setLocale` verifies it before committing: a tag some title answers
with nothing is `error.EmptyRouteTitle` and the app is left exactly as
it was, the same footing as the empty `.fixed` title `App.init`
refuses. The nav re-says itself on the spot: a row of destinations, a
collapsed chip and the marker beside them all change together, with no
second table to hold and no positional re-stamp to forget.

### The framework's own words

Everything else nokre puts on a screen is nokre's, and no consumer's
*data* can name it — only their catalog. `App.Chrome` is the whole list,
English until an app says otherwise:

| Field | English | Where it appears |
| --- | --- | --- |
| `back` | "Back" | the back control's accessible name; nothing draws it |
| `close` | "Close" | the sheet's close control |
| `section` | "Section" | the collapsed nav chip's *name* (its section is its value) |
| `current_screen` | "Current screen" | the marker for a screen that is no destination |
| `sections` | "Sections" | the chip's picker, as a dialog name and as the nav landmark's |
| `notices` | "Notices" | the notices pane's heading and its name |
| `show_notices` | "Show notices" | the minimized indicator |
| `show_all_notices` | "Show all notices" | the banner's expand control |
| `minimize_notices` | "Minimize notices" | the banner's and the pane's |
| `dismiss_all_notices` | "Dismiss all notices" | the pane's header |
| `open_prefix` | "Open: " | joined to a notice's title, on its open control |
| `dismiss_prefix` | "Dismiss: " | joined the same way, on its dismiss control |
| `important` / `other` | "Important" / "Other" | the pane's two group captions |
| `copied` | "Copied" | the live region an acknowledged `copyable` grows |
| `more` | "More" | the control an overflowing row of actions folds into |

```zig
app.setChrome(L.chrome(loc)); // every word, from the catalog, or no build
```

`L.chrome(locale)` is the localized app's opt-in, and the shape to
reach for the moment a second language exists. It reads one **reserved
key per `Chrome` field**, the name derived from the field's — `chrome`
plus the field camel-cased at its underscores:

| Field | Reserved key |
| --- | --- |
| `back` | `chromeBack` |
| `close` | `chromeClose` |
| `section` | `chromeSection` |
| `current_screen` | `chromeCurrentScreen` |
| `sections` | `chromeSections` |
| `notices` | `chromeNotices` |
| `show_notices` | `chromeShowNotices` |
| `show_all_notices` | `chromeShowAllNotices` |
| `minimize_notices` | `chromeMinimizeNotices` |
| `dismiss_all_notices` | `chromeDismissAllNotices` |
| `open_prefix` | `chromeOpenPrefix` |
| `dismiss_prefix` | `chromeDismissPrefix` |
| `important` / `other` | `chromeImportant` / `chromeOther` |
| `copied` | `chromeCopied` |
| `more` | `chromeMore` |

A catalog missing one of them does not compile — the posture the rest
of this document already holds, a catalog mistake is a build error,
extended to the one place it could not reach: a bare `Chrome` literal
compiles with a field missing, and the miss ships as English in the
middle of a translated nav bar, silently, until a reader of that
language hears it. The bare literal stays for what its defaults are
for: the zero-config app, or one saying a word or two. Nothing to
re-declare when nokre grows a chrome string, either — the key is
derived from the field, so the new field simply stops every opted-in
app compiling until its catalogs say the new word, in every locale
they carry (key parity does the fanning out). The reserved keys are
ordinary messages otherwise — placeholder-free, required, translated
where every other word lives.

One struct and one call, not a setter per control: these are one fact —
what nokre calls its own chrome — and a locale changes every one of them
at once, so a half-translated nav bar is not a state that can be
reached. Chrome already standing is re-said on the spot, so the call
does not wait for the rebuild that follows a locale change. The strings
are **borrowed**, exactly as `RouteDef.title` is: `tr` hands back
constant data, which is what these are for.

The two prefixes are prefixes and not format strings, deliberately. A
runtime `"Open: {title}"` is a placeholder a translator can drop,
reorder, or mistype, and this document's whole posture is that such a
mistake is a *build* error — but there is no comptime left to check a
string written into a struct at run time. Joining costs the reordering a
few languages would want and buys a string that cannot be wrong.

One of them is also *measured*: `more`, the control an overflowing row
of actions folds into ([elements.md](elements.md#the-folded-tail-more)).
Every other string here rides on the node it names, but layout claims
that control's width while *deciding* the fold — before the control
exists — so this word reaches layout on its own. The consequence is
worth knowing: it is the one chrome string whose translation changes a
layout. A long word takes its room from the row and folds it an action
deeper, rather than clipping the pill that carries it.

## What the compiler checks

Everything below is a build failure with the locale, message, and line
in the error — the categories Flutter's gen_l10n reports at generation
time, plus several it never checks.

One precondition governs all of it: **Zig analyses lazily, so a
`Bundle` nothing reaches is one nokre never checks.** A bundle a screen
reads from is analysed by that read, and every rule below runs. A bundle
held for a language nothing publishes yet, or reached only from a branch
this build did not take, is inert — write `comptime { _ = L; }` beside
the declaration, and the catalog is checked because it is named rather
than because some call site happens to mention it.

- **Key parity, both directions.** A locale missing a template key
  fails; a locale carrying a key the template dropped fails too. There
  is no `untranslated-messages-file`, because there is no such state:
  an untranslated message cannot build, so template text can never leak
  into another locale's screen.
- **`@`-metadata in the template alone.** Metadata declares a message's
  interface, so the catalog carrying it *is* the source; any other
  catalog carrying a `@key` entry fails the build naming that locale and
  that key. Two things in nokre answer "which catalog is the template"
  — `Bundle` positionally, the first embedded source, and the drafting
  tool by reading a directory for the metadata
  ([Drafting a translation](#drafting-a-translation)) — and this is what
  keeps them from naming different files.
- **Placeholder interface.** The template (its text plus its
  `@`-metadata) defines each message's placeholders. A translation
  using a name outside that set is rejected — the typo is caught in the
  catalog, not at the call site of some other locale. A placeholder
  used both as a count and as a select value is rejected as
  contradictory.
- **Placeholder parity, in the direction nothing else can see.** A
  translation that *drops* a placeholder the template's sentence writes
  fails too, naming the locale, the message and the name. It is the one
  corruption with no other symptom: every argument type survives it,
  every call site goes on compiling, and the value is simply never
  shown to that language's readers. Two things that look like the same
  defect are not, and are deliberately allowed — a name written twice
  interpolates twice, and a translation may put the set in whatever
  order its grammar wants, because arguments match by field name and
  position never enters. A name the template declares in `@`-metadata
  but does not use is how a translation says something the template
  leaves implicit, so it is not required of anyone.
- **Bytes, before any of the above.** A catalog decoded with the wrong
  codec and saved again parses and renders — `Ù…ÛŒâ€ŒØ´ÙˆØ¯` where a
  word should be. `@embedFile`'s bytes are checked for that first, plus
  a BOM, invalid UTF-8, U+FFFD and stray control characters, and the
  mojibake finding names the text the file should have held rather than
  only the line it is on
  ([src/l10n/encoding.zig](../src/l10n/encoding.zig)). The same scanner
  reaches the documents a build declares rather than embeds
  ([What the build checks](#what-the-build-checks)) — one set of rules,
  two ways in.
- **Plural completeness, per locale.** Each locale's plural is checked
  against *its own* CLDR integer categories: Russian without `few`
  fails naming a number it would mishandle; English with a `few`
  branch fails too, because that branch can never be selected — dead
  translation work. `=1{...} other{...}` still passes in English:
  `one` selects exactly {1} there, and the exact provably covers it.
  (One deliberate exception: the Romance `many` for whole millions —
  CLDR 42 grammar that almost no catalog writes — falls back to
  `other` at runtime instead of failing the build.)
- **Select case parity.** The template's case set is part of the
  message's interface; every locale must carry exactly those cases. A
  dropped case would fall to `other` silently — in production, in one
  language.
- **Reserved keys.** A message using `{…, date, MMM}` requires
  `monthJan`…`monthDec`; an app calling `chrome(locale)` requires one
  `chrome…` key per `App.Chrome` field. Both are ordinary messages —
  required placeholder-free, translated everywhere by key parity — and
  a miss is a build error naming the key. A bare `{when}` reference to
  a date placeholder, and an unknown date skeleton, fail the same way.
- **Call sites.** `fmt` args are matched against the message: missing
  argument, unknown argument, string where a count belongs, a
  non-civil-date value where a date belongs — each is a compile error
  naming the message and the field.
- **A translation that is the template's own words.** A value
  byte-for-byte the template's fails unless the language really does
  say it that way and the template records why — two derived
  exemptions aside
  ([Words a language really shares](#words-a-language-really-shares)).

The plural rules live in
[src/l10n/plural_rules.zig](../src/l10n/plural_rules.zig) — eighty
language tags across nineteen rule families, integer operands only (which
is what collapses CLDR's grammar to plain arithmetic). A language not
in the table errors only when one of its messages actually uses
`plural`, and the error says where to add the row.

## Words a language really shares

Key parity proves every message *exists* in every locale. It cannot
prove anyone wrote them: a drafting pipeline fills the keys that are
*absent*, and a key holding the source language is, to every tool that
looks, done. That is how forty English values per locale sat in a
catalog a drafting run reported complete.

So a translated value byte-for-byte the template's fails the build,
unless one of three things is true. Two are derived, and no one may
declare them; the third is declared in the template's `@`-metadata, with
its grounds:

```json
"monthApr": "Apr",
"@monthApr": {
  "identical": { "de": "German writes this month's abbreviation exactly as English does." }
}
```

The field maps a locale to the reason that locale writes the message in
the template's own words. The locale is the other catalog's `@@locale`,
verbatim — one that names no embedded catalog fails, and so does the
template naming itself. **The grounds are not optional and may not be
empty.** A declaration without them is a skip, a list of skips stops
describing anything, and only somebody who reads the language can supply
them: no rule derives that German writes *Sport*, *Bonus* and seven of
the twelve month abbreviations as English does.

Repeating one reason across the keys it covers is the cost, and it is
smaller than it looks: a shared reason table keyed by an id would save
*characters*, not entries — there is one entry per key either way — and
it would buy that with a second thing to read, a second thing to keep in
step, and two failure modes of its own. The reason stays beside the
message it is about.

The two derived exemptions:

- **A value with no translatable text.** Strip the placeholders, the
  counts and the date references, and what is left of `"{label}:
  {date}"` is punctuation. Nobody translates punctuation, in any
  language, so nobody has to say so. The literal text inside a plural or
  select branch is the translator's and is kept — a wholly untranslated
  plural is not machine punctuation. A codepoint counts as a word unless
  it is an ASCII non-letter or falls in the punctuation, digit, currency
  and symbol blocks: an unknown script reads as words on purpose,
  because treating a word as a mark exempts a real untranslated value in
  silence, while treating a mark as a word only asks for a declaration
  somebody can write.
- **A locale that names the template's own language.** `en_GB` against
  an `en` template repeats it verbatim in over two hundred of the
  kitchen sink's messages, and that is what a regional catalog *is*: a
  handful of overrides, identity everywhere else. Demanding a
  declaration for each of the rest would turn the channel into the skip
  list it exists not to be. Identity carries information only across
  languages, so the rule reads the primary subtag and stands down when
  it matches.

Both are refused as declarations for the same reason they are exempt:
declaring one claims credit for what the derivation already covers, and
the claim would outlive the derivation.

**A declaration that stops describing an identity fails.** Translate the
message and the declaration for it must go, naming the locale and the
key. Without that, the channel decays into exactly the skip list its
grounds are written to prevent.

Two things a host tool could do here, `@compileError` cannot, and they
are losses rather than simplifications: **the first finding stops the
build**, so a catalog with nine of these is nine compiles rather than
one report; and there is **no passing tally**, so a run that exempts
everything looks the same as a run with nothing to exempt. The trade is
deliberate. This rule is unconditional and rides the compile itself, so
it reaches every build that compiles the bundle; the host checker beside
it ([What the build checks](#what-the-build-checks)) reports a whole run
at once and refuses a pass with nothing behind it, and is reached only
by an app that declared it.

The drafting tool inherits all of it, because its validator is this
compiler ([Drafting a translation](#drafting-a-translation)). It also
asks the question a round earlier: an answer byte-for-byte the source's
is refused at drafting time by the per-key check, with the two
exemptions above derived there the same way, so a model that echoed the
English is re-asked instead of costing the whole catalog a `.partial`
with this compile error in it. What reaches the probe anyway — a value
the check let through, or a locale it could not re-ask into shape —
still fails here. If the answer was right, and the language really does
say it that way, declare it in the template and re-run with `--fill`.

## What the build checks

Everything above is reachable from the catalog alone, which is why the
compiler can hold it. Five rules are not: whether a key anything
*defines* is a key anything *uses*, whether a word on screen came from
the catalog at all, whether the words are the ones the product decided
on, whether the bytes of a document outside the catalog set are the
bytes somebody typed, and whether a translated document still has its
source's shape. The first two need the app's sources, and no `@import`
reaches those — a check written as a test would have to name every
source file to read it, and the file it forgot is the one hiding the
defect. The third needs a vocabulary that is shared by more than one
package and therefore lives above any module root, where `@embedFile`
does not reach; and it could not move into the compiler even if it did,
because the same multi-needle scan over a real-scale corpus cost 71.6 s
and 2.0 GB at comptime against 0.27 s natively — Zig's comptime is a
tree-walking interpreter, and the search itself is the cost. The last
two need a *directory*: comptime can embed a file it is given the name
of and cannot walk a tree to find out what the names are, so a rule
whose subject is "every document under here" has no comptime form at
all.

So they run beside the compiler, in a host tool the build attaches —
one declaration, whose optional halves are what turn on the rules that
need more than a catalog and a source tree:

```zig
const app = nokre.addApp(nokre_dep, .{
    // …
    .l10n = .{
        .template = b.path("src/l10n/app_en.arb"),
        .src = b.path("src"),
        // Rule three: the vocabularies the drafting tools already take.
        .glossary = b.path("../../l10n/glossary"),
        // Rules four and five: the Markdown collections this app ships.
        .documents = &.{ b.path("src/content/articles"), b.path("src/content/docs") },
    },
});
```

`.l10n` unset is the default and checks nothing — an app with no
catalog, or a generator whose words live somewhere these rules would not
understand, says nothing and gets nothing. `.glossary` and `.documents`
are the same bargain one rule down: unset, that rule checks nothing;
set, it refuses to report a pass it did not earn. Set, the findings ride
the **app's own artifact**, so a plain `zig build` runs them.

That is deliberately not where the store listing reports
([services.md](services.md)). A listing finding is about copy that
changes late, long after the code around it settled, and it blocks
what a release is assembled from rather than the developer's next
compile. These five are about code being edited now: an orphaned key
arrives in the same commit that stopped using it, a hardcoded string
arrives in the same commit that typed it, and a heading a reviewer
deleted arrives in the commit that deleted it. A rule whose subject is
the edit in front of you belongs on the build that edit runs.

- **Every key is referenced.** A key in the template that nothing under
  `src` names is reported by name. A key is named by its enum literal
  in either spelling — `.someKey`, and `.@"some.key"` where the key is
  dotted — or *composed*, where a screen driven by data joins a
  namespace to an id it read (`stringToEnum(Key, prefix ++ id)`); the
  evidence for that is the namespace written as a literal, and only a
  whole segment ending in `.` counts, so a short literal cannot exempt
  keys it merely happens to start.

  The keys nokre reads for itself are never orphans: `Bundle.chrome`
  derives one `chrome…` key per `App.Chrome` field and a
  `{…, date, MMM}` reference reads `monthJan`…`monthDec`, and neither
  has a literal in the consumer's tree to find. That set is derived
  from the same declarations the compiler derives it from
  (`l10n.reserved_keys`), never listed — a `Chrome` field nokre grows
  reserves its key here in the same breath.
- **No word on screen is a literal**, unless the app says its words are
  not the catalog's (`words_from_catalog`). A string literal reaching
  one of nokre's text-taking element fields — `label`, `title`,
  `content`, `description`, `detail`, `placeholder`, `problem`,
  `options`, `text`, `section`, `name` — is reported with the field and
  the method that took it. The set is derived from the element structs and
  its coverage is a comptime check, so an element that grows a field of
  words cannot be missed; so is the arity of every builder the scan
  looks inside, which is what tells `Cursor.text(content)` from a
  consumer's own `text(fmt, args)`.

  This one is a token scan and says so: it reads what is written at the
  call site, not what a type would prove, so it sees a literal and
  never a variable holding one. A type could have carried the rule
  instead — a wrapper every word passes through — and that is the
  rejected alternative worth naming: the escapes such a type needs
  (user data, server payloads, operator scaffolding) are most of the
  traffic, so the wrapper would be named more often than not and stop
  being read. A `test` block is skipped — a test builds screens nobody
  reads — and so is a code block, because code is not translated.

  One exemption, and it is declared rather than guessed: `dev_gate`
  names the consumer's own comptime flag — the build option under
  which operator-only scaffolding is compiled in. A function whose
  every call site sits under that flag may write English, because
  nothing without the flag can reach it. A second call site outside the
  gate ends the exemption, which is the property that makes it worth
  declaring at all.

  Server-provided strings need no exemption: they are never literals,
  so they never reach this rule. What a screen owes them is localized
  framing around the payload, which is a review question and not a
  scan's.

  The whole rule stands down for an app whose catalog exists to give
  *nokre's* chrome its words and nothing else — a single-language site
  whose prose is written where it is read. That is a decision about the
  product, not about the code, so it is declared
  (`.words_from_catalog = false`) rather than inferred from a locale
  count. nokre's own documentation site is that app; the key rule keeps
  running there, because a key nothing references is dead copy in any
  number of languages.
- **The product's fixed words are the words that landed.** A drafted
  value that ignores one of them is well-formed, plausible and wrong,
  which is the defect no structural check can see and the reason the
  vocabularies exist at all ([The glossary](#the-glossary)). `.glossary`
  names the directory those same files live in, one `<locale>.txt` per
  destination language, read a second time here as a rule over what
  landed.

  The rule is derived from the mappings already written and adds no
  vocabulary of its own: **where the English template value uses a
  source term, that locale's value must use the term's destination.**
  There is deliberately no forbidden-word list, which would be a second
  vocabulary to keep in step with the first. Unset checks nothing. A
  directory that names no vocabulary any catalog can use fails rather
  than passing quietly, and so does a run that judged catalogs and found
  not one of the vocabulary's terms in the template — a pass with
  nothing behind it reads exactly like a pass.

  The catalogs judged are the template's own siblings — every `.arb` in
  its directory, the set `translate-arb --dir` levels — and a locale
  with no file in the vocabulary directory is left alone.

  Matching is by substring, which is what survives the morphology of
  real destination languages: *halka* is inside *halkanın*, *Guthaben*
  inside *Guthabenstand*, ارتباط inside ارتباطات. Four things are
  normalized first, each because one language writes one word two ways
  — Turkish dotted and dotless i, the Arabic and Persian letter forms
  of a single letter, Persian harakat (optional orthography), and the
  zero-width non-joiner and tatweel, which are spacing rather than
  spelling. Turkish stem-final *k*, *p*, *t* and *ç* voice before a
  vowel suffix — *anonimlik* becomes *anonimliği* — so a destination
  ending in one is matched in both forms.

  A term's singular and plural are one **family**, and either
  destination satisfies either source: Turkish takes no plural after a
  numeral and Persian's خدمات shares no letters with خدمت. The rule
  judges which word was chosen, never which inflection.

  Two things scope a match, and neither is an exemption list. **A
  never-translate term consumes the text it covers**, so the word
  inside the product's own name is not an occurrence of that word.
  **The longest entry wins**, and an entry may be a phrase, so a legal
  document's title written as its own entry takes the word inside it
  and stops being read as the product's channel of the same name.
  Matches are word-bounded and no stretch of text is claimed twice.

  What is left over is genuine sense ambiguity — اتصال is right for a
  connection to a server, while a Connection between two people is
  ارتباط — and that is declared per key in the template's
  `@`-metadata, beside `identical` and on the same terms:

  ```json
  "@splashOfflineMessage": {
    "sense": {
      "fa": { "connection": "reaching the server, not a Connection between two people" }
    }
  }
  ```

  A locale maps each source term this message does not use in the
  product's sense to the reason it does not, **and the grounds are not
  optional** — only somebody who reads the language knows the word
  covers two things. The declaration **decays in both directions**,
  which is what keeps it from becoming an exemption list: one whose
  template value does not use that term at all is a finding, and so is
  one whose translation uses the destination anyway, because that
  declaration describes nothing. Naming a term the locale's vocabulary
  does not map, or a locale no judged catalog answers to, is a finding
  too.
- **A document's bytes are the bytes somebody typed.** The catalogs get
  this from the compiler — every `.arb` a `Bundle` embeds is scanned
  before it is parsed ([What the compiler
  checks](#what-the-compiler-checks)) — and a repository that also
  ships Markdown gets nothing, because an
  article is read at build time from a path rather than embedded by
  name. `.documents` names the collections, and every `.md` under one
  is put through the same scanner the catalogs go through: a
  byte-order mark, invalid UTF-8, U+FFFD, a control character, and a
  run that is a UTF-8 sequence read back in Latin-1 or Windows-1252 —
  reported with the text the file should have held. The source language's
  own documents are scanned with the rest: corruption is a property of a
  file, not of a translation.

  A collection is a directory holding **one subdirectory per locale,
  named by the tag**; which of them is the source is the template's
  `@@locale` and is not declared twice. A declared collection holding
  no `.md` file at all fails rather than passing: a rule that never
  opened a file reads exactly like a rule that found nothing wrong. So
  does one with no directory for the source language, which leaves every
  other language nothing to be held against — and a `.md` lying directly
  under the collection, in no locale directory at all, is a finding on
  its own.
- **A landed translation is still the shape of its source.**
  `translate-md` refuses a draft whose heading outline, block
  sequence, list kinds, link destinations or code spans differ from the
  source's ([Drafting a document](#drafting-a-document)) — and then
  nothing ever asks again. A heading deleted in review, a destination
  translated by hand, a list that lost an item: every one of those
  passes the consumer's build, renders, and links nowhere. So the same
  comparator runs over what is committed. `.documents` is the whole
  declaration: within a collection the pairing is the file's own name
  under each locale's directory, and a slug one language has and
  another lacks is a finding by itself.

  Two things are the comparator's and stay the comparator's. The
  complaints are written *at a drafting model* — "you wrote X where the
  source has Y" — and they are quoted here verbatim rather than
  reworded, because the sentence that teaches a model is the sentence
  that teaches a reviewer and a second copy would drift. And the
  front-matter *schema* does not arrive here: nokre owns the grammar
  and never the schema ([Drafting a document](#drafting-a-document)),
  so what this rule holds a block to is what the grammar can see on
  its own — the same keys, in the same order, each value in the same
  written form. The one value it reads is the locale: where exactly one
  of the source's fields carries the source's own tag, that field must
  carry this document's tag. Byte-equality of a *structural* value is
  `translate-md`'s, at drafting time, where the schema is stated.

## Drafting a translation

`zig build translate-arb` drafts a locale's catalog from the template
with an OpenAI-compatible LLM — one key per request, the key's
`@`-metadata as context, the target's CLDR categories quoted into the
prompt from the table above:

```
zig build translate-arb -- --input examples/kitchen_sink/l10n/sink_en.arb --dest fa
```

**Its output is a draft for a human to read.** A model is
nondeterministic and this repo is not; the tool's job is to get a
translator to "review this" sooner, never to commit a catalog nobody
read. What makes that safe is the last step: before the draft is
accepted it is compiled against the template by nokre's own validator —
everything under "What the compiler checks", on the real file. A draft
that fails is left as `<output>.partial` with the compiler's error
quoted verbatim, and the run exits non-zero.

Between requests a cheap per-key check earns a retry — a lost
placeholder, a plural branch the language never selects, a trimmed
prefix, a `#` that went missing, or the English source handed back
unchanged. It is deliberately a subset of the validator: being wrong
there costs one retry, not a catalog. Two rules are on both lists for
the same reason. A dropped placeholder the compiler refuses now ("What
the compiler checks"), and an answer identical to the source it refuses
too — the identity rule under
[Words a language really shares](#words-a-language-really-shares) — and
both stay here because a retry carrying the reason is worth more than a
`.partial` the tool cannot explain. The identity rule's **two derived
exemptions are derived here as well**, off the same two facts: a value
whose literal text carries no word (an ICU pattern, a lone placeholder)
is not a translation anybody withheld, and a destination whose primary
subtag is the template's is a regional catalog, which is identity
everywhere it does not override. A check that refused either would
spend a real catalog's whole retry budget on the keys that cannot be
wrong. The
re-ask happens at answer time and is never blind: the corrective prompt
quotes the rejected answer and the check's own complaint, and from the
first rejection onward it also quotes the same key's value from the
template's other completed catalogues — worked examples, discovered
beside the template and included only when they pass the same per-key
check for that key, because an invalid example teaches the mistake.
The base prompt stays cheap on purpose; examples are paid for only by
a key that has already got it wrong. What the base prompt does state
up front is the shape contract — a placeholder keeps exactly the
source's usage, a plural with no `#` gets none, a date skeleton is
copied verbatim — because a model's canonical-ICU reflex rewrites
exactly the shapes an unusual message deliberately uses, identically
across models, and a complaint after the fact was measured (two
models, seven attempts) not to talk either of them out of it. The
other thing it states is what the *words* have to be — the terms of the
product's vocabulary this key's own English uses, and any second sense
the template declares for them ([The glossary](#the-glossary)).
`--retries` (default 3) is the per-key budget, spent by these
rejections and by transport failures alike; a key that exhausts it is
announced on its own line as it fails and again in the end-of-run
list, and the run exits non-zero.

The draft lands beside the template with the locale suffix swapped —
`sink_en.arb` drafted to `de` becomes `sink_de.arb` — so it joins the
catalog set rather than sitting next to it. It does not join the
*bundle*: that is an explicit `@embedFile` list, not a directory scan,
so a draft nobody has read yet cannot become a language the app ships.
Adding it is one line, and key parity then applies to it like any other
locale.

`--dest` is a locale tag, not a language name — `fa`, `pt-PT`, `fa-IR`
(`pt_PT` is accepted; `@@locale` is written BCP 47's way and the file
keeps the catalog set's `_` naming). The tag is the
catalog's identity: it is what `@@locale` states, what selects the
plural rule and the digit shapes, and what names the output file. A
name would have to be resolved back to a tag, and that resolution has
no right answer — "Portuguese" is `pt` or `pt_PT`, two rows of the CLDR
table that count differently, and choosing one silently yields a
catalog with the wrong plural forms that compiles. Any tag works, not
only the ones with an English name on hand; `--src` defaults to the
template's own `@@locale`.

**`--dir` brings a whole folder level.** Point it at a catalog
directory and it works out what is missing where, then fills each gap:

```
$ zig build translate-arb -- --dir examples/kitchen_sink/l10n
Template: en (3 key(s), from examples/kitchen_sink/l10n/sink_en.arb)
  de is missing 1
  fa is missing 2
  ru is missing 1
```

Nothing has to declare which catalog is the template — it is the one
carrying the `@`-metadata, and that agrees with the bundle by
construction rather than by luck: `Bundle` refuses metadata outside its
own template ([What the compiler checks](#what-the-compiler-checks)), so
a directory whose catalogs compile has exactly one carrier. The choice
is checked against nokre's own rule that every key lives in the template
first. Every other catalog is
filled *from the template*, never from a peer: only the template has the
metadata a prompt needs, and pivoting `ru` → `de` would ask a model to
collapse one/few/many into one/other on top of translating.

A key that exists outside the template stops the run and is named:

```
  fa has 'l10nOnlyInPersian'
error: nokre refuses a key the template lacks ("every key lives in the
template first"), so a catalog cannot introduce one. Add each to 'en' —
with its @-metadata — or drop it, then run again.
```

That is deliberate. Spreading such a key to the other locales would
spread a build failure, and its `@`-metadata — the placeholder types the
whole bundle keys off — only ever exists in the template.

**When the template grows a key, `--fill` translates only that key.**
An existing catalog's lines are kept verbatim — a reviewed line
re-drafted is a diff someone has to re-read, which is exactly the cost
worth avoiding — and only the keys it lacks are requested:

```
$ zig build translate-arb -- --input …/sink_en.arb --dest de --fill
Filling …/sink_de.arb: 2 of 3 key(s) already translated, 1 to add.

  [3/3] [█████████████░░░░░░░]  66%  done (0.5s)  elapsed 0.5s  ETA 0s
```

A key the template has since dropped is named and removed, because
parity is total and carrying it would fail the build. `--fill` and
`--force` contradict each other and are refused together: one keeps the
existing translations, the other replaces them.

`LLM_BASE_URL` is the OpenAI SDK's `baseURL` — the `/v1` root, not a
full path; unset it defaults to OpenAI's own. `LLM_API_KEY` is optional,
because the local models this was built for take no key. `--resume`
picks a *crashed* run back up from its `.partial`, and an existing
output is never overwritten without `--fill` or `--force`.

**Reasoning is switched off by default**, and it is the difference
between a catalog that drafts in seconds and one that takes minutes. A
thinking model deliberates for thousands of tokens before emitting the
same JSON: on one real message, 3,206 completion tokens against 34, and
a two-key catalog took 71 seconds instead of 1.5. Translating a UI
string is not what reasoning is for, and the answer is checked twice
afterwards anyway. The tool asks the server's chat template to skip it
(`chat_template_kwargs`, llama.cpp's own field — dropped automatically
if the endpoint rejects it, as OpenAI does). `--think` restores it for a
catalog whose wording is genuinely hard.

### The glossary

`--glossary <path>` folds a term list into the prompt, and both drafting
tools take it. Terminology drift is the one defect no structural check
can see: a German draft in a consumer repo named one monetized unit five
different ways across one app — including one word that means
"acknowledgements", on the purchase screen's own title — and every one
of those answers had the right placeholders and the right shape. A
glossary is the only control for it.

The format is two lines' worth of grammar, because the file is written
and reviewed by whoever owns the product's words:

```
# a comment
read credit = Lesekredit
Rokovski
feedback.pricing
```

A line with `=` fixes the destination term for a source term. A line
without one is a term that is never translated — product names, route
names, code identifiers. One file per destination locale: a mapping's
right-hand side is in one language. A malformed line is fatal, never
skipped; a glossary that quietly ignored half its entries would report
success having enforced nothing.

The same files are a rule once the draft has landed, in the build's own
check rather than in this tool ([What the build checks](#what-the-build-checks)).
Folding the list into a prompt asks; reading the catalog back tells.

**What a key is told is what that key will be judged on.** A catalog's
vocabulary runs to dozens of mappings and a UI string uses one of them
or none, so `translate-arb` names in each request only the terms the
message's own English actually uses. What decides *actually uses* is not
a second reading — it is **the build rule's own matcher**, over the same
template value, with the same folding, the same singular/plural family
and the same longest-first consumption that lets a name take the word
inside it. A term the matcher finds is named in the prompt and enforced
on the catalog; a term it misses is neither named nor enforced. The
instruction and the rule cannot drift apart, because there is only one
implementation of the question and only one English for it to read.

Sending all of them was the alternative, and it is what this replaced:
every request carried the whole vocabulary whether or not a word of it
appeared in the string, which said nothing about the message and buried
the two or three lines that did.

The **never-translate terms are not narrowed**, and the asymmetry is
deliberate rather than an oversight. Nothing judges them — the rule
derives itself from the mappings alone and never asks whether a name
survived — so the argument above does not reach them. What does reach
them is that a name can enter a request through the key's description,
its example, or whatever a placeholder substitutes at run time, none of
which a value-scoped matcher reads. They are also few: the first
consumer's Persian file has three of them against fifty-seven
mappings.

`sense` reaches the prompt too, and it is the declaration a model most
needs. A key that declares one is saying *this message does not use that
word in the product's sense* — اتصال is right for reaching a server and
wrong for a Connection between two people — so the fixed rendering
leaves that key's terminology block and the declaration arrives in its
place, with its **grounds quoted rather than reworded**. The grounds are
a sentence somebody who reads the language wrote about that key, and a
paraphrase would be the tool guessing at a distinction it cannot see.
Only the destination locale's declarations are sent; another locale's
are not this draft's business. This is the same data the build reads
([What the build checks](#what-the-build-checks)) — declared once, in
the template, and now spent twice.

## Drafting a document

`zig build translate-md` is the same tool for one Markdown document —
a documentation page, an article, anything a consumer keeps as
`.md` with a front-matter block:

```
zig build translate-md -- --input content/articles/en/why.md --dest de \
  --front-translate title,summary --front-structural publishedAt,tags \
  --front-locale-key locale --glossary content/glossary-de.txt \
  --sibling content/articles/tr/why.md
```

One file per run, named. Nothing here walks a directory: the consumer
knows its own content layout and states it, and a tool that guessed
would encode one repository's tree into a library. What *is* pointed at
a tree is the same comparator, over what is already committed
([What the build checks](#what-the-build-checks)) — drafting is one
moment and a document is edited for years.

**The validator is nokre's own Markdown parser.** There is no comptime
probe behind this one, so the comparator *is* the verdict rather than a
prefilter — which is why it is built the one way that cannot drift from
what will be rendered. Both documents are parsed by appending a
`document` element to a `Tree`, exactly as an app would, and what is
compared is the elements that came out: the heading outline, the block
sequence and nesting, the list kinds and item counts, the styled runs
per block, the link destinations byte for byte, the code spans and
fenced blocks byte for byte. Nothing re-implements the subset and
nothing reads the source with a regular expression.

Two failures are why it exists.

**A translated destination.** A destination is an address — a route
name like `feedback.pricing`, or a URL. Translated, it yields a
document that builds, reads well, and links nowhere.

**Degradation.** The subset is closed and everything outside it comes
through as its own literal source text ([markdown.md](markdown.md)) —
exactly right for bytes nobody reviewed, and exactly wrong for a draft,
because the page then shows the syntax. An image, an HTML tag, a
footnote, a link whose brackets slipped: none of them fails, all of
them ship. So marker residue is counted on both sides of the comparison
and the draft may carry no more of any marker than the source does. The
source's own count is the allowance, so prose that legitimately
contains an asterisk is not an alarm.

The quietest one is an unclosed `**`. nokre reads it as an opener and
leaves the style set to the end of the block: the parse succeeds, every
word arrives, no marker reaches the rendered text, and the page ships
with half a paragraph in bold. The per-kind counts do not move —
`**a** b` and `**a b` each hold one strong run — so what is compared is
whether the block *ends* inside a style where the source's does not.

That check began as a comparison of each block's **total** run count,
which included its unstyled runs, and that was wrong in a way worth
recording: how many unstyled runs a block has is a fact about word
order. English opens `Open **Connections** and tap …` with a plain word
and Turkish opens `**Bağlantılar**ı aç ve …` with the styled one, so
the totals differ (5 and 4) while every marker still closes around the
same words. Held against the first consumer's shipped content, the
total-run comparison rejected four of fourteen correct translations,
and a rejected sibling is silently withheld as a worked example — so
the rule degraded every future draft of those documents rather than
failing loudly. **A rule that varies with word order cannot be part of a
translation comparator.**

**The front-matter schema is a parameter, never a hole.** nokre owns
the grammar — an opening `---`, one `key: value` per line, a closing
`---` — and never the schema. Which keys are prose (`--front-translate`),
which are facts about the entry that every language's file must agree on
(`--front-structural`), and which one names the locale
(`--front-locale-key`) are the collection's decisions and arrive on the
command line. The classification is closed in both directions before a
token is spent: a source key in neither list stops the run naming it,
and so does a schema key no document states. That is what keeps a
`draft: true` from being silently translated into publication.

More rules are about the *file* rather than the document, and every one
of them came from reading a real draft whose parse was perfect.

- **A trailing newline**, if the source has one.
- **The wrap**: the longest line may not run half again as wide as the
  source's longest. Comparative rather than a fixed column — the source
  states the width it was written at.
- **Dashes set tight** against the word on one side or both. Comparative
  too, because the tight form is real typography rather than a mistake:
  American house style sets an em dash closed, and which dash a language
  uses and how it spaces it is that language's business. What is not a
  style choice is that a tight dash is a place the line cannot break, so
  the paragraph runs past the wrap or sprawls to avoid it.
- **Trailing whitespace**. Comparative, because inside a fence a
  trailing space is content and only the document can say whether it has
  such a fence. Two trailing spaces are read as a hard line break, so
  past one space this changes what the page shows; at one space it
  changes nothing and is committed anyway.
- **A line ending in a hyphen**, anywhere the parser joins the run's
  lines — a paragraph or a list item, not a fence or a table. This one
  is absolute rather than comparative, and it can afford to be because
  compliance is free in every language: the line wraps one word earlier
  and renders identically.

The dash rule and the wrap rule were one rule for a while, and that is
the lesson in this group: the width complaint's *advice* told a model to
space its dashes, and it only ever reached a document that had also
blown the width budget. A draft that stayed inside budget shipped its
tight dashes untold, and one did — seven of them. **Advice carried
inside another rule's complaint is not a rule.** It fires on that rule's
trigger, not on its own.

**Truncation is its own named failure, never a valid draft.** This is
the hazard the ARB path does not have: a document cut off mid-body
still has front matter that parses and a body that is merely short. The
tool sizes a token budget from the source, sends it, and reads
`finish_reason` back; `length` widens the budget and re-asks the *base*
prompt unaltered, because the model did nothing wrong and must not be
told it did. A budget the operator pinned with `--max-tokens` is not
widened. An endpoint that reports no reason at all is a blind spot, not
a pass — the structural comparison catches truncation there, by the
blocks that never arrived. A draft whose prose is under half the
source's length is complained about separately, counted in codepoints so
a script change does not read as a summary.

The retry loop is `translate-arb`'s: the corrective re-ask quotes the
rejected document and the comparator's own complaint, never a stack of
prior ones, and `--retries` (default 3) is the budget. Worked examples
are `--sibling <path>`, repeatable — the same document in the locales
that already have it, quoted whole on the first rejection only. Each is
gated through the comparator against this very source, because an
example that would itself be rejected teaches exactly the mistake, and
one that does not fit `--example-bytes` is skipped whole rather than
truncated: a half document is the failure mode being policed.

What the comparator cannot judge, the prompt states: register and tone,
the glossary's terminology, the hard wrap, and the claim rule —
translate every claim at exactly the strength the source makes it,
never strengthen one, never introduce an absolute the source does not
make. A translation that upgrades a hedge into a guarantee is a legal
defect, not a stylistic improvement, and nothing structural will ever
see it.

`--output` is derived when the input path has a directory component
that *is* the source locale's tag: `…/articles/en/why.md` drafted to
`de` becomes `…/articles/de/why.md`. A path with no such component, or
with two, is refused with the operator told to pass `--output` — a
stated rule with a loud failure, not a guess. An existing output is
never overwritten without `--force`, and a rejected draft is kept as
`<output>.partial` so a reviewer reads it beside the complaint.

## The refusals

Same posture as everywhere else in nokre
([introduction.md](introduction.md)): what would break determinism is
refused loudly, at compile time, with the reason in the error.

- **No `DateTime`, no `double`, no `format:`.** NumberFormat and
  DateFormat delegate to the platform's locale library, which means
  different bytes on different OS versions — and `DateTime` needs a
  clock, which nokre's core does not have. Format decimals in app code
  and pass a String; pass counts as integers; pass calendar dates as
  the `date` kind's civil value — the one date shape admitted, because
  the caller owns the value and fixed skeletons own the bytes.
- **No `{n, number}` / `{n, time}` argument types**, for the same
  reason. A bare `{n}` renders an int deterministically, and
  `{n, date, skeleton}` is the deterministic date (its skeleton set is
  closed; there is no freeform pattern to vary by platform).
- **No `offset:`** — restate the message with `=N` branches, which say
  the same thing without the arithmetic. **No `selectordinal`** — a
  second CLDR table no consumer has needed yet.
- **No runtime catalog loading.** Catalogs ship inside the binary.
  Downloadable translations are a distribution feature with a cache, a
  version skew story, and a failure mode on first launch — that is an
  app, not a GUI library.
- **No fallback chains.** A bundle has one fallback: the template, and
  only in `resolve`, for a *device* locale nokre doesn't carry.
  Between catalog entries there is no falling back, because parity is
  enforced instead — fallback is what silent untranslated text is made
  of.
- **No localized route arguments** — the one refusal here that lands at
  the call rather than at compile time. A route argument is an
  identifier, so `router.zig`'s `validIdent` admits `[A-Za-z0-9_.-]` and
  nothing else: a Persian or Turkish slug is refused outright by
  `Router.writeRef` (`error.RouteArgCharset`) and by the same check on
  the way back in (an `.arg_charset` refusal), never transliterated,
  percent-encoded or otherwise quietly repaired. The ground is the
  router's own — *"an argument is an identifier and not a payload. Free
  text is a URL, which is deep_link's business"* — and it does not move
  for a locale. What this costs a multi-locale surface is the localized
  *slug*, not the localized page: key the route by an ASCII id and
  localize the words the screen puts on it, the way route titles are
  localized under [The chrome nokre writes](#the-chrome-nokre-writes)
  above. A BCP 47 locale tag is itself ASCII, so a per-locale route
  argument is fine; `note~fa` is a reference, `note~یادداشت` is not.
- **No Persian digits as ordered-list markers in Markdown source.** A
  Persian author wrote `۱.` to get Persian numerals and got eight
  run-on paragraphs, because the parser reads ASCII `1.` and nothing
  else. Widening it was refused: Persian prose is full of Persian
  digits, so admitting `۱.` as a marker imports the `8. April 2026`
  hazard — a date opening a line, silently becoming a list — into every
  Persian paragraph, and the sentence that trips it is ordinary
  writing rather than a mistake. Source stays ASCII and rendering
  localises, which is the same split the whole of this section rests
  on: `1.` in the file, `۱.` on the screen (see the digit shapes
  above, and [markdown.md](markdown.md)). Consequence, stated: a
  Persian `.md` reads with Latin ordinals in a plain text editor and
  renders with Persian ones. That is the price of the parser having one
  grammar in every language.
- **No locale→quotation-mark table, and no quote rule in the
  comparator.** Asked for after a German draft kept ASCII `"` where
  German typography sets `„…"`. Three grounds, and the first is
  decisive. **There is no convention here to enforce**: of the first
  consumer's four content locales, English and Turkish both use ASCII
  quotes and only Persian localises them (to `«…»`, and it did so
  without being told). A rule would be nokre imposing one locale's
  habit on a corpus that does not share it. Second, a table would make
  nokre assert a typographic convention for every locale it might ever
  draft — a claim it cannot verify and that has real exceptions, Swiss
  German setting `«…»` where Germany sets `„…"`. A wrong entry is worse
  than no entry, and it would be nokre's to be wrong about. Third, the
  weaker version — hold the draft to the source's *count* of quote
  pairs, which needs no table — is not shape but punctuation fidelity,
  and languages legitimately differ about where they quote at all.
  **This is a parameter, not a hole**: a consumer that wants German
  quotes states it in its own glossary, which is exactly the seam for a
  convention nokre does not own.

## Against gen_l10n

For a reader arriving from Flutter:

| | Flutter gen_l10n | nokre |
| --- | --- | --- |
| Pipeline | `l10n.yaml` → generated Dart class | `@embedFile` → comptime |
| Untranslated key | Falls back to template at runtime; optional report file | Build failure |
| Stale key in a translation | Ignored | Build failure |
| Plural categories | Whatever branches you wrote; misses fall to `other` | Validated against the locale's CLDR set, both directions |
| Select cases | Per-locale freeform | Template's set enforced everywhere |
| Placeholder args | Typed method parameters | Comptime-checked anonymous struct |
| Number formats | intl NumberFormat | Refused; integers only |
| Dates | intl DateFormat over a `DateTime` | A caller-supplied civil date, closed skeleton set, month words as reserved catalog keys |
| A value that opens in the other direction | Renders as it lays out; the mark is the translator's to remember | Compiled with the mark its locale implies ([above](#a-value-that-opens-in-the-other-direction)) |
| Runtime | Parse + lookup through intl | Straight-line writes into your buffer |

The through-line: Flutter treats the catalog as data checked by a tool
you remember to run; nokre treats it as source. If it builds, every
locale is whole.

## Testing

Nothing special is needed: `tr` and `fmt` are pure functions, and the
harness drives the same `App` your shells do ([testing.md](testing.md)).
Assert on rendered text with the locale set in your state, as the
kitchen sink's localization section does
([examples/kitchen_sink/main.zig](../examples/kitchen_sink/main.zig) —
its Russian catalog exists precisely because four plural forms prove
the validation is real). nokre's own coverage is
[src/l10n/l10n_test.zig](../src/l10n/l10n_test.zig).
