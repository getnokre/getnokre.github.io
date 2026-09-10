# Platform shells

One contract, five shells — the web has none, because the browser is
one and nokre's substrate there renders into it
([dom-substrate.md](dom-substrate.md)). (That is the count of record, the
one other docs point at: six platforms, five shells — the web is a
platform without a shell.) Per-platform status lives in the
[README](../../README.md)'s support matrix; this is the
contract a shell implements.
A shell's complete job description:

1. Create a window/surface and report its logical size and integer scale.
2. Deliver input: tap, key, text, IME, scroll, a stated selection, an
   IME's deletion, a long press.
3. When the app has a dirty frame, fetch the rendered RGBX buffer and
   blit it.
4. Write text to the system clipboard when asked — the one C hook
   behind the clipboard service ([../services.md](../services.md)),
   which backs the `copyable` element and `App.copyText`. Read it back
   on the platform's own paste verb and deliver the bytes as text.
   Hand a URL to
   the system browser when asked — open_url's hook, the same shape
   (outbound, nothing links; it answers only "did the handoff start",
   and only oauth's loopback leg reads even that).
5. Report the device locale at install and on every change — the one C
   hook behind the locale service, which is what a localized app
   resolves its strings against.
6. Give the platform's text system an honest document: ask core what the
   focused field holds and where its characters are drawn, instead of
   telling the OS the field is empty.

Anything smarter than that belongs above the platform line and is rejected
in review. This is what keeps six platforms maintainable by very few
people. OS capabilities beyond this contract (secure storage, inbound
links, sign-in, …) are separate optional modules — see
[services.md](../services.md).

Selection is comptime in
[src/platform/platform.zig](../../src/platform/platform.zig) — dead shells
cost nothing.

Note what job 3 does *not* include: the shell never draws. Each platform
file names a **frame-source installer** — `skia_frame.install`, which the
Runner calls right before `c_shell.config` — and the shared code delegates
to it, reconciling only the viewport and safe area the OS reported. So no
shell names a rendering backend, and a second renderer substrate installs
its own source instead of forking all five
([substrates.md](substrates.md)).

## The C shell contract (macOS, iOS, Windows, Linux, and Android)

[src/platform/shell.h](../../src/platform/shell.h) defines
`nokre_shell_config`: logical size, title, and callbacks —
`on_frame` (returns the RGBX pixel buffer for the current scale, and
carries `safe_bottom` — the height of any OS-drawn band at the view's
bottom edge, 0 where there is none; core keeps layout above it and
extends bottom-pane fills through it),
`on_pointer` (a press, its motion, and its release, with a
`NOKRE_POINTER_*` phase — core activates on the release so a press that
leaves before letting go aborts, WCAG 2.5.2, and reports motion only
between the two — plus two facts about the press itself: how many clicks
deep it is and a `NOKRE_POINTER_SOURCE_*` for what is making it),
`on_key` (portable keycode enum + modifier bits), `on_text`
(committed UTF-8), `on_ime_update/commit/cancel`, `on_scroll` (deltas
plus a `NOKRE_SCROLL_*` phase: wheel shells send free events routed at
the pointer; touch shells bracket a drag begin/move/end so core locks
the gesture to the scrollers under the initial touch),
`on_edge_pan` (one step of the drag that goes back: which physical edge
the finger started on, how far in it has come, and a `NOKRE_PAN_*` phase
whose `CANCEL` is deliberately not `END` — implemented only by iOS,
the one platform that leaves the screen edge to the app),
`on_back` (the platform's *decided* back command, returning whether
nokre consumed it — Android's leg, where gesture navigation owns both
edges and there is no drag to report),
`on_select` (the focused field's selection as the platform's own text
system moved it), `on_delete_range` (an IME deleting around the caret),
and `on_long_press` (a recognized long press *or* a
secondary click — one callback, because they are one meaning),
`wants_frame`, `wants_text_input` (drives the software keyboard on
shells that own one), `wants_submit_action` (whether the focused field
would act on Enter — asked beside `wants_text_input` by the two shells
with a software keyboard, and unused by the other three, which have no
IME action to set), the five questions about the focused field the next
section describes (`editable_snapshot`, `field_rect`, `caret_rect`,
`offset_at`, `selection_rects`), `on_appearance` (OS light/dark), `on_ready`
(native view handle, for attaching the a11y adapter), and
`on_window_focus`. `nokre_shell_request_frame` lets the Zig side mark the
view dirty from outside the input stream — assistive-tech actions need
it. `nokre_shell_write_clipboard` replaces the system clipboard with UTF-8
text (NSPasteboard on macOS, UIPasteboard on iOS, the Win32 clipboard
as CF_UNICODETEXT on Windows); the clipboard service calls it
directly — no install step. `nokre_shell_request_paste` is its
counterpart and the only *inbound* half of that service: the shell reads
its own clipboard on an explicit user action and delivers the bytes back
through `on_text`, which is why nothing is returned and there is no call
that answers what the clipboard holds ([../services.md](../services.md)
owns the posture). `nokre_shell_haptic` fires the back gesture's
threshold knock and exists on iOS alone, since no other shell runs a
threshold of nokre's own ([haptics.md](haptics.md)). `nokre_shell_post_main` runs a
callback on the UI thread from any thread — the worker service's
delivery hop ([workers.md](workers.md)); only shells whose main queue
the Zig side cannot reach directly implement it (Windows posts a
window message; Apple platforms call libdispatch from Zig and never
link the symbol).

**Space goes down one leg per press.** It is the one key that is also a
character — it activates a button *and* it types — so the contract makes
the shell choose, at the moment of the press, off `wants_text_input`:
`on_text` while a field has focus, `on_key` everywhere else. Neither half
is optional. A shell that maps Space to a key and stops there has no
space bar in its text fields; a shell that sends both legs types a stray
space into whatever the activation just focused — for a `select`, that is
the filter field of the picker it opened. Each shell reaches the rule
through the machinery it already has: macOS hands the event to
`NSTextInputContext` rather than mapping it, iOS lets `pressesBegan` fall
through to `UIKeyInput`, the web's fields are real DOM inputs so the
browser owns the choice,
Linux and Android ask `wants_text_input` before picking a leg, and
Windows — where `WM_CHAR` follows `WM_KEYDOWN` whether anyone wanted it
or not — decides in `WM_KEYDOWN` and latches the echo off. Core is the
backstop, never the decision: a Space key inside a field is inert and
text with nothing editable focused is dropped
([editing.zig](../../src/core/editing.zig)).

**The shell counts clicks; core decides what a count selects.** Every
platform already holds the interval, tied to that reader's own
double-click speed and their accessibility settings —
`NSEvent.clickCount`, Win32's `WM_LBUTTONDBLCLK` and
`GetDoubleClickTime`, and elsewhere the timer the shell already runs for
key repeat — and core has no clock to keep a sixth answer in. What a
count *means* is core's, the same split the key chords run on:
[../elements.md](../elements.md#text_input) has the meanings. `source`
is read for one thing only — a caret pressed by a finger grows a grab
handle to drag it by — and the argument for why a grab target may be
device-shaped when a control may not is beside the declaration, in
[event.zig](../../src/core/event.zig)'s `Pointer.Source`. A shell that
sends `NOKRE_POINTER_SOURCE_MOUSE` and 1 for every press behaves exactly
as every shell did before the two arguments existed.

Two things about those arguments are easy to get wrong and are stated in
the header beside them. The source is **latched at the press**, because
the phases that end one are not all input messages a shell can ask the
device about — `WM_CAPTURECHANGED` is not a message about a device at
all — so a shell that re-reads it per phase reports one press as two
kinds. And a press claimed by `wants_pointer_stream` **still carries its
count**: what claims the stream over a field is a grab target, a grab
target sits on the text it marks, and so the second tap of a double tap
into a field arrives on the claimed path and nowhere else — a shell that
bypasses its own tap recognizer there and sends a bare 1 leaves
double-tap-to-select unreachable exactly where a reader taps twice.

**A platform that draws its own text grab targets says so**, through
`nokre_core_declare_platform_grab_targets` — the one symbol in shell.h
the Zig side exports and a shell calls, since every field of
`nokre_shell_config` travels the other way and reaches the shell
`const`. iOS is the caller: a `UITextInteraction` owns the handles, the
loupe and the press-and-hold over the focused field, so nokre's own
teardrop would be a second affordance drawn on top of the system's and
one the reader mostly could not drag. Core then raises neither handle
flag, nothing claims the pointer stream over a field, and no press is a
grab. It is declared rather than inferred from "this shell sends no
`on_long_press`", which is true of iOS and would be silently wrong for
the first shell that simply has not sent one yet.

### The honest document

Every platform text system is written against a document it can *read*.
A shell can answer "the in-progress composition, and nothing else" and
ordinary typing still works, which is why most of these shells did. What
does not work is everything the keyboard infers from the document, and
the defect that settled it is **a held Backspace on iOS**: the key
repeats against the document, so a shell whose document is empty between
compositions has nothing to delete on the second repeat and the key dies
after one character. The loupe, the drag handles, "select all", a11y
reading the field aloud and an IME replacing a range are all the same
shape — five workarounds, or one honest answer.

So core answers five questions about the focused field, and the shell's
document becomes the field. The declarations and the reasoning behind
each are [shell.h](../../src/platform/shell.h)'s; what a shell writer
needs to know before calling them is here.

- `editable_snapshot(out)` reads the field out whole — its value, the
  selection's two ends, any open pre-edit and the IME's caret in it, the
  direction the caret's line runs, and whether the field is obscured or
  multiline — or answers 0 with nothing focused. **The document a text
  system must be shown is not `value`**: an open pre-edit is carried
  beside it, and the shell splices it in at the cursor by the formula
  the header states. Every shell that builds a document does that splice
  and none keeps a pre-edit of its own, because a second copy is a
  second answer to what the IME has in flight.
- `field_rect(out)` is the field's own bordered box — not the words
  inside it and not the label or problem words around it. It exists for
  a platform whose text interaction claims every touch in the view until
  it is told where the text is; iOS's `UITextInteraction` is that
  platform and the only caller there is.
- `caret_rect(offset, out)` is where that offset's caret is drawn. The
  IME candidate window, iOS's loupe and `firstRectForCharacterRange:`
  all position from this one answer, so a caret is never in two places.
  While a pre-edit is open the snapshot's `cursor` answers *inside* it,
  at the caret the IME reported — a candidate list docked at the splice
  point instead stood a word away.
- `offset_at(x, y)` is the inverse, about the *focused* field, `-1` when
  none is focused. It is deliberately not a hit test: a shell asking "is
  there a field under this finger" is asking core to leak what is on
  screen, and the answer it wants is to send the event and let core
  decide.
- `selection_rects(out, max)` gives one rect per wrapped line and per
  bidi piece, returning how many it wrote — never how many it needed, so
  a shell picks its own cap and a long selection draws short. The
  renderer's highlight and the a11y layer read the same core answer, so
  the platform's idea of the selection cannot disagree with the painted
  one.

**The snapshot is borrowed, and a geometry call ends the borrow.**
`value` and `composition` point into the tree, and any call back into
core may rebuild them — a key, a text insertion, a frame, and equally
`field_rect`, `caret_rect`, `offset_at` and `selection_rects`. A shell
that wants the text *and* a rect copies the value before it asks for the
rect. Two shells write the ordering down where they depend on it, which
is how obvious it is not: macOS reads the document only *after*
`characterIndexForPoint:` has answered, and the Windows candidate placer
takes `cursor` out of the snapshot and nothing else, so no borrowed byte
outlives the `caret_rect` call.

**Offsets are UTF-8 byte offsets into the value** — every offset in this
contract: `cursor` and `anchor`, `caret_rect`'s argument, `offset_at`'s
answer, and the two ends of `on_select` and `on_delete_range`. Core
indexes bytes everywhere, so a UTF-16 index means nothing below the
platform line, and **each shell whose text system counts UTF-16 owns its
own conversion**: macOS and iOS (`NSRange`/`UITextPosition`), Windows
(IMM32 and the wide clipboard), Android (Java's `char`). The whole value
crosses so that conversion runs against the same bytes core is holding
rather than a copy the shell took earlier.

**A shell states a selection; core vets it.** `on_select` is how the
platform's own text system reports that the selection moved — iOS's grab
handles through `setSelectedTextRange:`, Android's `setSelection`, a
range macOS asks to replace. **`anchor` is the fixed end and `cursor`
the live one**: where the caret is, and where a following Shift+motion
extends from. A platform that knows which handle moved says so with the
order; one whose range has no direction sends anchor = start, cursor =
end, which is what both Apple shells do. Both ends are then clamped into
the value and onto grapheme-cluster boundaries, so a shell that converts
wrong loses a selection edge and nothing else — the same bargain
`on_ime_update`'s caret already makes. Windows and Linux never send it:
neither IMM32 nor text-input-v3 has a verb that moves the selection.

**An IME's deletion is its own verb.** `on_delete_range(start, end)`
carries Android's `deleteSurroundingText` and text-input-v3's
`delete_surrounding_text`. Both platforms define that operation as
deleting around the caret and **excluding** the selection, so the idiom
it replaces — state the range with `on_select`, then send Backspace —
deleted exactly the selection it had just overwritten. Two shells were
spelling it that way; both send the verb now, and a deletion beside a
selected run leaves that run selected. A platform whose call names two
runs, one either side of the selection, sends the later one first, so
the earlier one's offsets are still the offsets it computed.

**A *visual* line key is the snapshot's to resolve.** macOS's ⌘←
arrives as `moveToLeftEndOfLine:`, and left is the line's logical start
on an LTR line and its logical **end** on an RTL one — so a shell maps
such a key onto `NOKRE_KEY_HOME` when the snapshot's `rtl` is 0 and
`NOKRE_KEY_END` when it is 1, mirrored for the right-end key. Logical
chords never ask: `moveToBeginningOfLine:`, Ctrl+A, the Home and End
keys themselves, and both delete-to-line keys below. macOS is the only
shell with a visual key to map, so it is the only one that reads the
flag — Android does not even ferry it across JNI.

**Two keys delete to the line's bound.**
`NOKRE_KEY_DELETE_TO_LINE_START` and `NOKRE_KEY_DELETE_TO_LINE_END` are
where ⌘⌫ and ⌃K land, and Ctrl+U and Ctrl+K on the Wayland shell —
readline's pair, which every terminal on that desktop binds. Keys rather
than a shell spelling them as a shift-select plus Backspace, for
`on_delete_range`'s reason above: that pair leaves an
undo entry holding a selection the reader never made. Windows and
Android map neither — no chord in either platform's own convention names
the operation, and inventing one is not a shell's job.

**The paste verb is the platform's**, and each shell honors its own
through `nokre_shell_request_paste` and its own chord table, both
arriving as `on_text`: Cmd+V and the Edit menu on macOS (`NSPasteboard`),
the edit menu and hardware Cmd+V on iOS (`UIPasteboard`), Ctrl+V and the
edit row on Android (`ClipboardManager`), Ctrl+V on Windows
(`OpenClipboard` + `CF_UNICODETEXT`, converted to UTF-8), Ctrl+V on the
Wayland shell (the held `wl_data_offer`, `receive`d through a pipe the
poll loop reads), and the browser's own paste on the web. An empty or
non-text clipboard delivers nothing at all, not an empty `on_text`.

**Long press and secondary click are one event.** `on_long_press` means
"act on what is under this point without activating it", and a platform
reaches it either way — a Windows touch press-and-hold arrives as
`WM_RBUTTONDOWN`, so a second callback would only make the shell choose
a name. Inside a field core selects the word, raises the two grab
handles and opens the edit row (Cut, Copy, Paste, Select all) as
framework chrome; anywhere else it is ignored, so no shell needs a gate.

**A long press cancels the press it grew out of.** It is a finger that
is still down and core is still holding that press, so the shell sends
`NOKRE_POINTER_CANCEL` for it *before* the long-press call — otherwise
the finger's release activates whatever it was resting on, which is a
row that navigates away from the selection the press just made. Both
recognizing shells do it: Windows on the `WM_RBUTTONDOWN` that follows a
touch hold, Linux when its own 500 ms `timerfd` fires. A secondary click
has no press in flight and sends the callback alone, which is macOS's
whole leg; Android has none either, since its tap is a DOWN and an UP
sent together on the release its detector suppresses. iOS sends the callback
never: UIKit owns press-and-hold inside a `UITextInteraction`, and a
second selection gesture over the top of that is two systems fighting
for one finger. The web sends it never either — the browser's own edit
menu stands.

What each shell does with the contract, and what it deliberately
declines:

- **macOS** — a field with focus takes the press through
  `interpretKeyEvents:`, so the chord table is `doCommandBySelector:`
  over NSResponder *commands* and not over key codes: the user's own
  bindings and the Emacs-flavored defaults (Ctrl+A/E to the line ends,
  Ctrl+B/F by character, Ctrl+D forward-delete) arrive already
  translated, and the document motions (⌘↑, ⌘↓, the Home and End keys,
  which AppKit spells as scrolls) collapse onto HOME/END because core
  has no document key. The Edit menu is not decoration: the standard
  chords are *menu key equivalents* on this platform, so a Mac app
  without one cannot paste — and because the menu claims them before any
  view is offered the press, no command can arrive twice.
  `NSTextInputClient` is answered from the snapshot, converting to UTF-16
  as it goes; `firstRectForCharacterRange:` hands core's rect to AppKit's
  own view → window → screen conversions rather than un-flipping it by
  hand (the view is flipped, so core's logical pixels *are* its
  coordinates). `NSEventModifierFlagFunction` is `NOKRE_MOD_FN`, which
  AppKit also sets for the arrow keys, so that bit alone never
  discriminates a chord. ⌘⌫ and ⌃K become the two delete-to-line keys,
  each from both its line and its paragraph selector because AppKit's own
  bindings name one for ⌘⌫ and the other for ⌃K; ⌘← and ⌘→ are the two
  visual keys, and this is the one shell that resolves them against the
  snapshot's `rtl`. `rightMouseDown:` is `on_long_press`, and
  `nokre_shell_request_paste` is where the menu's `paste:` and a binding
  naming it both land — one read. `NSEvent.clickCount` travels as the
  click count unaltered: it is already that reader's double-click speed
  from System Settings and whatever their accessibility configuration
  does to it, and AppKit is also what resets it, so this is the one
  shell keeping no run of its own. A tablet stylus reports `PEN`, off
  the mouse event's own tablet subtype; a trackpad is a `MOUSE` here and
  cannot be anything else, because its click is an indistinguishable
  mouse event and it drives a cursor — and no Mac has a touchscreen, so
  `TOUCH` never leaves this shell.
- **iOS** — the whole `UITextInput` document from the snapshot, every
  dispatch bracketed by the `inputDelegate`'s will/did change pairs (the
  held-Backspace fix), a `UITextInteraction` attached while
  `wants_text_input` and bounded by `field_rect`, `selection_rects`
  behind the grab handles, `keyCommands` for the hardware chords, the
  edit menu, and `nokre_shell_request_paste`. It sends `on_long_press`
  never: UIKit owns that gesture inside the interaction.
- **Android** — `NokreInputConnection` answered from the snapshot with
  the composition spliced in, `setSelection` as `on_select`,
  `deleteSurroundingText` as `on_delete_range`, `updateSelection` after
  each dispatch, `AccessibilityNodeInfo.setTextSelection`, the Ctrl chord
  table, a long press inside editables as `on_long_press`, and
  `nokre_shell_request_paste`. Three parts of the contract are declined
  and each absence is a decision: `rtl` is not ferried across JNI at all,
  because this platform's line keys are logical; `field_rect` is not
  called, because TalkBack reads the a11y snapshot's own rect for every
  node and a second convention for the focused field alone would move a
  box under the cursor; and `caret_rect` and `selection_rects` have no
  caller yet, because an Android IME positions its candidate window from
  `CursorAnchorInfo`, its own opt-in protocol ("Android specifics" below
  carries the shapes).
- **Windows** — the `WM_KEYDOWN` chord table with its `WM_CHAR` echoes
  swallowed, the IMM candidate window placed from `caret_rect`,
  `WM_RBUTTONDOWN` as `on_long_press` with the left press it began
  cancelled first, and `nokre_shell_request_paste`. It builds **no
  document**, and the absence is a decision: the composition string is
  IMM32's own, and this shell answers none of the reconversion requests
  that would ask it for the text around the caret — so the one thing it
  takes from the snapshot is `cursor`, to dock the candidate list
  ("Windows specifics" below carries the shapes).
- **Linux** — the xkb chord table including Ctrl+U and Ctrl+K,
  text-input-v3's `set_surrounding_text` from the snapshot and
  `set_cursor_rectangle` from `caret_rect`,
  `delete_surrounding_text` as `on_delete_range`, `BTN_RIGHT` and a
  `wl_touch` long press as `on_long_press`, and
  `nokre_shell_request_paste` over the held data offer. Two decisions
  read as absences: the surrounding text deliberately **excludes** the
  open pre-edit — v3 defines it that way, and a shell that spliced would
  place every deletion an IME asks for wrong by the composition's own
  length — and `field_rect` goes uncalled, because the request v3
  actually defines is the bounding box of the *text cursor*.

None of the five questions is optional and none is ever NULL: the Zig
side fills every entry of `nokre_shell_config`
([c_shell.zig](../../src/platform/c_shell.zig)), so a shell calls them
unconditionally, and a shell that asks nothing simply keeps the document
it had. The *export* is the one that is not optional in the linker's
sense — every native build names `nokre_shell_request_paste` through the
clipboard service, so omitting it is an unresolved symbol rather than a
missing feature, locale's posture.

A few *service* hooks ride the same native files without being part of
this dumb contract — the shell implements them, but they answer to a
service header, not shell.h. `nokre_shell_write_clipboard` above is one
(clipboard, outbound). open_url's `nokre_open_url_open`
([src/services/open_url/open_url.h](../../src/services/open_url/open_url.h))
is its sibling, outbound: the scheme allowlist has already run in Zig,
so every shell opens what it is handed (`NSWorkspace` on macOS,
`UIApplication openURL` on iOS, ShellExecuteW on Windows, an
ACTION_VIEW intent via `NokreView.openUrl` on Android, a double-fork
`xdg-open` on the Wayland shell; the web has no C shell — services.js
implements the import as `window.open(…, "_blank", "noopener")`,
reached only by keyboard activation, since the live driver leaves
pointer clicks on external anchors to the browser). This hook is each
desktop's *one* URL launcher: oauth's loopback leg names the same
symbol instead of keeping its own ShellExecuteW/xdg-open copy, which
is why the hook returns "did the handoff start" — the open_url service
discards it (fire-and-forget at that surface), oauth's
`BrowserUnavailable` reads it, and the coupling is deliberate and
owner-approved (the header states it). share's `nokre_share_show`
([src/services/share/share.h](../../src/services/share/share.h)) is the
same shape with one asymmetry: the Wayland shell does not export it —
the Linux desktop has no share sheet, and the service answers
`available` false there instead of the shell faking one. Where it
exists, each shell hosts its own sheet (`NSSharingServicePicker`
anchored to the view's center on macOS, `UIActivityViewController` from
the topmost controller — centered arrowless popover on iPad — on iOS,
an ACTION_SEND chooser via `NokreView.showShare` on Android, the WinRT
share pane through `IDataTransferManagerInterop` on Windows — combase
bound at first use, the interfaces declared against the SDK IDL in
shell.c since mingw ships neither — and `navigator.share` on the web,
where the same services.js instance answers the boot-time
`nokre_share_available` probe). deep_link's `nokre_deep_link_install` is the inbound
twin: the OS hands the app a URL (iOS `scene:openURLContexts` /
`continueUserActivity`, Android `onNewIntent`, macOS
`application:openURLs:`), and the shell forwards it on the main thread to
the ctx + callback the service installed, buffering a launch URL that
arrives before install. The contract is
[src/services/deep_link/deep_link.h](../../src/services/deep_link/deep_link.h);
it is wired on all five shells — macOS, iOS, Windows, Linux, and
Android. The web has no C shell: the Zig side keeps the receiver and
exports `nokre_deep_link_receive`
([src/services/deep_link/web.zig](../../src/services/deep_link/web.zig)),
and live.js calls it with `location.href` after boot when the page
loaded with a fragment — by then the handler the app registered inside
its first build is installed, which is the launch-URL contract — and on
every `hashchange`. That delivery runs alongside the live driver's own
reading of the fragment as route navigation, deliberately: the two
answer different questions (*a URL arrived* versus *which screen is
showing*, [docs/routing.md](../routing.md)), and an app that both links
deep_link and routes on the fragment sees it twice — routing.md says to
route on one or the other. The export exists only when the app linked
the service, so a page that never claims a deep link pays nothing.

notification's hooks
([src/services/notification/notification.h](../../src/services/notification/notification.h))
are the roster's only two-directional pair: the app asks the OS to show,
schedule or take back a message, and the OS reports a decision, a tap, an
arrival or a push token. Placement is split rather than uniform, and each
half earns it — Apple's leg is service-owned like oauth's (a
`UNUserNotificationCenter` delegate need not be the app delegate, so one
file serves macOS and iOS both, and each shell carries only the APNs
token line UIKit/AppKit hands nowhere else), while Android, Linux and
Windows are shell-owned like deep_link's, because there the object the OS
calls back really is the shell's: `NokreActivity` and `NokreView` on
Android, the very D-Bus connection this Wayland loop already polls on
Linux, and on Windows a COM activator the shell registers so a tap can
reach a *closed* app. That Windows registration is a deliberate,
recorded narrowing of deep_link's refusal to write the registry, scoped
to two keys ([notifications.md](notifications.md)). The web has no C
shell: services.js implements the imports and the site's own service
worker carries what a page cannot — Chrome for Android refuses
`new Notification()`, and a push arrives with no page open at all.

One service on the roster deliberately asks the shells for *nothing*:
`clock`. Wall time is a call every OS exposes to the process directly —
`clock_gettime` on the POSIX family, `GetSystemTimePreciseAsFileTime` on
Windows, `Date.now()` through services.js on the web — so it has no
header and no shell hook, and a new shell owes it no line. It is
recorded here only so the omission reads as a decision rather than a
gap: a shell that grew a `nokre_clock_*` export would be answering a
question the process can already answer, which is the redirection this
document's last paragraph makes in the other direction
([../services.md](../services.md)).

locale's `nokre_locale_install`
([src/services/locale/locale.h](../../src/services/locale/locale.h)) is
the second inbound hook, and the one a new shell cannot skip: it links
nothing — no framework, no entitlement, no permission — so it has no
build flag to sit unlinked behind, and every native build names the
symbol. A target joins locale.zig's `has_shell_hook` switch only once
its shell defines the function; stub targets never name the extern, and
that switch is the whole of "optional" here (clipboard's posture). The
shell stores ctx + cb like deep_link's and buffers nothing: a launch URL
can be missed, a device locale cannot, because it is readable on demand.
That is what pays for the promise deep_link's hook does not make — **the
first callback fires synchronously, inside the install call.** Install
runs in `App.init` and the app reads the tag inside its first `build`;
nokre has no ticker to retire a loading frame an async answer would
strand. Every later OS locale change fires again, on the main thread,
and *those* fires request a frame — the install fire does not, since no
window exists yet. The tag is UTF-8 BCP 47, not NUL-terminated, borrowed
for the call; a shell that cannot name a language fires with length 0,
and the Zig side turns that empty tag into the app's own template
language. Never substitute an "en" natively: which language an unknown
locale means is the app's decision, not the shell's. macOS is the
reference implementation — `NSLocale.preferredLanguages.firstObject`
(the user's ordered *display-language* preference, already hyphenated
BCP 47, not `localeIdentifier`'s POSIX-flavored *formatting* locale)
plus an `NSCurrentLocaleDidChangeNotification` observer on
`[NSOperationQueue mainQueue]`, which *is* the marshal the main-thread
rule asks for. The other four shells' sources are in their sections
below, and the web's is `navigator.language`, seeded by the live driver
([live.js](../../src/render/dom/live.js)) — except on a page nokre
generated, where the shell's answer is the language that page was
written in and the device is not consulted at all
([dom-substrate.md](dom-substrate.md), "The page's locale, not the
reader's"); only Linux has no change source at all.

oauth is the one service whose native halves deliberately do **not** ride
the shell files, and the exception is worth stating because it looks like
an omission. A browser session is not something a shell has any business
knowing about, so `nokre_oauth_start` lives under
[src/services/oauth](../../src/services/oauth) — secure_store's placement,
not deep_link's — and each leg is a service-owned file the build compiles
beside the shell (`apple.m`, `windows.c`, `linux.c`, the Android JNI
shim). The shell gets involved in exactly one place, for one platform:
Android's redirect arrives as an intent, so `NokreActivity` routes it and
`NokreView.nativeAuthResult` hands it to the service — the same doorway
`nativeDeepLink` uses, and the shell still learns nothing about what a
flow is. Contract in
[src/services/oauth/oauth.h](../../src/services/oauth/oauth.h).

The Zig half of the contract is shared:
[c_shell.zig](../../src/platform/c_shell.zig) owns all state, every
callback adapter, and — for the four shells whose loop `nokre_shell_run`
owns — the whole `run`: `c_shell.Runner(Adapter, install_frame)`. A
platform file ([macos.zig](../../src/platform/macos/macos.zig),
[ios.zig](../../src/platform/ios/ios.zig),
[windows.zig](../../src/platform/windows/windows.zig),
[linux.zig](../../src/platform/linux/linux.zig)) only names its a11y
adapter and frame-source installer. What used to differ invisibly
across four `run` wirings — who forwards window focus, who lends its
loop for worker wakes, who consumes `RunOptions.app_id`, whether attach
wants the window class — is now a comptime branch in the Runner,
derived from the adapter's own surface (`@hasDecl` for
`detach`/`focusState`, attach's arity for the window class) or the
platform predicates c_shell already had. Android is not a Runner
instantiation: its loop is the Activity's, so android.zig keeps its own
wiring over the same shared adapters. The native side (~300–900 lines
of Objective-C or C per platform) holds no state.

Frames are rendered **on demand**: the shell asks `wants_frame` and only
repaints when true. No ticker, no vsync loop, zero idle CPU.

## iOS specifics

[ios/shell.m](../../src/platform/ios/shell.m) is a UIKit port of the
same contract with twists of its own:

- **Safe area.** The view respects the safe area's top and sides but
  runs to the physical bottom edge, reporting the home-indicator band's
  height as `safe_bottom` — so a bottom pane's surface (the notice
  banner, the notices pane) reaches the true bottom instead of floating
  above a letterbox, and the nav, which paints no surface at all, still
  anchors its items above the band while the page scrolls through it.
- **Software keyboard.** Two responders share the screen: the view is
  first responder exactly while `wants_text_input` says the focused
  element accepts text — which is what shows and hides the keyboard —
  and the view controller holds it otherwise, forwarding hardware keys
  via `pressesBegan`. The keyboard runs with every "smart" mutation
  (autocorrect, capitalization, smart quotes) disabled, and now on its
  own terms. The justification used to be that the shell's
  `UITextInput` document was only the IME composition, so there was no
  context to be smart with — but that document was the held-Backspace
  defect ("The honest document" above), never a reason. What stands is
  that nokre types what the user typed; turning any of them back on is a
  decision, not a consequence of the fix. The
  return key is `UIReturnKeySearch` exactly while `wants_submit_action`
  says the field would act on one, and `UIReturnKeyDefault` otherwise;
  UIKit reads the trait when it builds the keyboard, so a change while
  one stands takes a `reloadInputViews`. Either key still arrives as
  `insertText:@"\n"`, which is core's Enter — the label changes, the
  delivery does not. The keyboard **shortens the view** rather than
  covering it, as the Android shell does through its IME inset: the
  view controller observes every keyboard frame change and ends the
  view at a docked keyboard's top edge, reporting `safe_bottom` as 0
  while one stands, so a bottom sheet lands on the keyboard and core
  reveals the field being typed into (`App.setViewport`). Only a
  keyboard docked across the screen's bottom counts — iPad's floating
  and split keyboards, and the frame a hardware keyboard reports, cover
  no band to shorten by. The end frame is applied unanimated: the
  keyboard slides, the layout snaps to where it lands.
- **Text selection.** The `UITextInput` document is the focused field
  ("The honest document" above), and positions in it are **UTF-16
  indices** into the value with any composition spliced in at the caret
  — core keeps a pre-edit apart from the value, so the splicing, like
  the UTF-8 ↔ UTF-16 conversion around it, is the shell's. Every
  dispatch into core is bracketed by the `inputDelegate`'s
  `textWillChange:`/`textDidChange:` and `selectionWillChange:`/
  `selectionDidChange:` — **the held-Backspace fix** — and that
  includes the edits UIKit itself asked for, because core *vets* what
  it is handed (an offset snaps to a cluster boundary, an obscured
  field refuses a cut) and the document UIKit must act on is the one
  core kept. The `hasText` hack that answered `YES` unconditionally
  against the same defect is gone with its cause. A `UITextInteraction`
  in `.editable` mode is attached exactly while `wants_text_input`,
  which is what gives a field nokre draws itself UIKit's grab handles,
  loupe, double-tap word selection and Cut/Copy/Paste/Select All. It
  owns only `field_rect`'s box — the field's own bordered box, which is
  the question that call exists to answer — because an interaction with
  no box claims every touch in the view it is installed on, and the tap
  that activates a button would never fire. Outside the box it
  declines and both of the shell's recognizers run exactly as they do
  with no field focused; the tap and the press-drag yield to it through
  `gestureRecognizer:shouldRequireFailureOfGestureRecognizer:` rather
  than `requireGestureRecognizerToFail:`, which has no inverse and
  would outlive the field. The feeder's pan is deliberately outside
  that arbitration: a drag that starts on text still scrolls the page.
  The edit menu is answered from the snapshot, so no row is offered for
  something core would ignore, and the hardware chords are
  `keyCommands` — ⌘A/⌘C/⌘X/⌘V/⌘Z/⇧⌘Z, ⌥←/⌥→/⌥⌫ with the shifted
  motions that extend instead of collapsing, and ⌘⌫/⌃K for the two
  delete-to-line keys, which a hardware keyboard is the only way to
  reach here since no software keyboard offers either — while
  `pressesBegan:`
  keeps its narrow job. Paste is one read of `UIPasteboard` behind
  three verbs: the menu row, ⌘V, and `nokre_shell_request_paste`.
- **Touch.** A tap gesture sends `on_pointer` DOWN then UP at the
  recognized point. A second recognizer — a long press with no minimum
  duration, which is continuous and so begins immediately — carries the
  raw stream, but only for touches core claims: it is gated in
  `gestureRecognizerShouldBegin:` on `wants_pointer_stream`, so
  everywhere else it never begins and the tap recognizer is untouched.
  When it does begin, the tap and the feeder's pan both
  `requireGestureRecognizerToFail:` it. It is also the one recognizer
  exempt from the fling refusal below: that refusal exists because a
  finger stopping a fling lands on whatever the content drifted under
  it, and core claims only fixed chrome with nothing scrollable beneath
  it — so the chip is where the user aimed, and refusing it would leave
  the one press-activated control dead while any fling ran. The fling
  still stops; `touchesBegan` halts the feeder for every touch.
  Scrolling borrows a hidden
  UIScrollView as its physics engine (see the feeder comment in
  shell.m): UIKit runs drag and flick-deceleration against a vast empty
  content area, and the offset deltas stream to `on_scroll` bracketed
  begin/move/end — one drag, momentum included, stays locked to the
  scroller under the initial touch.
- **The back gesture.** Two `UIScreenEdgePanGestureRecognizer`s, left
  and right, reporting translation to `on_edge_pan`; core picks the
  leading edge for the chrome's direction and ignores the other. The
  feeder's transplanted pan `requireGestureRecognizerToFail:` both of
  them — without that, an inward drag from the edge would scroll *and*
  pan, and the screen would move under a gesture whose entire point is
  that nothing moves. The knock at the threshold is
  `UIImpactFeedbackGenerator`, prepared when the pan begins
  ([haptics.md](haptics.md)). This is the one shell behaviour no
  headless test reaches: recognizer arbitration is verified in the
  Simulator or not at all.
- **Deep links** ([services.md](../services.md)). The scene delegate
  forwards inbound URLs to `nokre_deep_link_install`'s callback: a
  Universal Link arrives as a `NSUserActivityTypeBrowsingWeb` activity
  (`scene:continueUserActivity:`, plus the connection options at launch),
  a custom scheme as `scene:openURLContexts:`. The launch URL is buffered
  until the app registers its handler — belt-and-braces, since on iOS the
  app is built (and `setHandler` run) before `UIApplicationMain`.
- **Locale** ([services.md](../services.md)). macOS's `preferredLanguages`
  read and main-queue observer, verbatim. In practice the boot read is
  what runs: iOS terminates a backgrounded app when the display language
  changes, so the observer earns its keep on the region and calendar
  edits that do arrive live. Both inbound hooks now share one weak
  `g_main_view` — it was `g_deep_link_view`, a deep_link name on a global
  the scene delegate sets for whichever hook needs to dirty the view.
- **Packaging.** UIApplicationMain owns the process, so `zig build
  -Dtarget=aarch64-ios[-simulator] -Dskia` produces static libraries and
  the example's own [Xcode project](../../examples/kitchen_sink/ios)
  compiles the shell, links Skia ([skia-build.md](skia-build.md)), and
  signs — the same wiring a consumer app would keep next to its own
  code. Run instructions: [getting-started.md](../getting-started.md).
- **Stack budget.** UIApplicationMain runs on the main thread, and iOS
  gives it 1 MB where a macOS process — the Simulator included — gets
  8 MB. An app's `State` therefore lives on the heap on every platform
  and is never a local of `main` or `run`: a 916 KB `State` on that
  stack left about 110 KB for everything a tap runs above it, and the
  secure store's first insert (a 36 KB frame over `native.list`'s
  72 KB) walked off the end on the first language switch — Teams on an
  iPhone 12 Pro Max, 2026-09-10 — while the Simulator, on 8 MB, never
  showed it. [getting-started.md](../getting-started.md) builds on the
  heap from Part 1 for this reason. A device crash is read through
  `xcrun devicectl device process launch --console`, which prints Zig's
  trace as unsymbolicated addresses; `atos -o <binary> -arch arm64 -l
  <load address>` names them, and the load address is the trace's
  `main` frame less `_main`'s file offset (`nm`), rounded down to 16 KB.

## Windows specifics

[windows/shell.c](../../src/platform/windows/shell.c) is a Win32 port
of the same contract — plain C, message loop, no framework. Its twists:

- **Blit.** GDI wants BGRX and the frame arrives RGBX, so the shell
  swizzles the channels
  once per frame and `SetDIBitsToDevice` maps it 1:1 onto device
  pixels. Repaints stay on demand: events call `wants_frame` and
  invalidate; `WM_PAINT` renders. Per-monitor-v2 DPI awareness, with
  the DPI rounded to an integer scale (125% → 1, 150% → 2) — the
  policy every shell shares — so glyphs never resample.
- **Input.** `WM_LBUTTONDOWN` is the tap; wheel messages send `FREE`
  scrolls at the pointer, 48 logical px per notch with sub-notch
  remainders accumulated for precision wheels. Keys map in
  `WM_KEYDOWN`; printable text arrives via `WM_CHAR` (surrogate pairs
  reassembled, control characters filtered — they already traveled as
  keys, so nothing fires twice). A Space spent on activation latches its
  echoing `WM_CHAR` off: the pair arrives whether or not core wanted
  both, and the choice belongs to the press, not to the echo.
  `WM_RBUTTONDOWN` is `on_long_press` — a touch press-and-hold arrives
  that way too, so the left press it began is cancelled first, as the
  contract requires.
- **Clicks.** Win32 delivers a double click as DOWN, UP, **DBLCLK**, UP.
  The second press *replaces* its `WM_LBUTTONDOWN` rather than arriving
  beside it, so `WM_LBUTTONDBLCLK` is a press on the same path: it sends
  a DOWN phase of its own — without it core would get a release it never
  armed — and it advances the count by exactly one. Treating it as a
  press on top of the one it replaced is how a double click becomes
  three. The third click comes back as a plain `WM_LBUTTONDOWN`, since
  Windows counts no further, and the shell counts it against
  `GetDoubleClickTime` and half of `SM_CXDOUBLECLK`/`SM_CYDOUBLECLK`
  (the metrics are the rectangle's full width and height, read through
  `GetSystemMetricsForDpi` at the window's own DPI) — the same numbers
  the system applied to the second click, so the run is one rule. The
  count needs `CS_DBLCLKS` on the window class to arrive at all, which
  also turns the second of two secondary clicks into
  `WM_RBUTTONDBLCLK`: that message is `on_long_press` too, or a fast
  double right-click would lose its edit row. A secondary click, a lost
  capture, or the window losing focus ends the run — the last because
  the click that went to another window is one this shell never saw,
  and Windows' own detection is per-window too.
  `GetCurrentInputMessageSource` names the
  device — touch and pen ride the same promoted mouse messages that make
  a press-and-hold a `WM_RBUTTONDOWN` — and `IMDT_TOUCHPAD` is a
  `MOUSE`, because a touchpad drives a cursor and the grab handle exists
  for a finger that has none.
- **Chords.** Ctrl+A/C/X/Z (Ctrl+Y and Ctrl+Shift+Z for redo),
  Ctrl+←/→, and Ctrl+Backspace/Delete become the semantic editing keys,
  Shift riding along as the selection bit. A chord is Ctrl *alone*:
  AltGr is Ctrl+Alt on international layouts, so matching on Ctrl with
  Alt down would eat the character AltGr types. Ctrl+V is not a key —
  paste is the platform's verb, so it makes the very clipboard read
  `nokre_shell_request_paste` makes ("The honest document" above), with
  `CF_UNICODETEXT`'s CRLF line endings squeezed to core's LF on the way
  into `on_text`. Nothing extra swallows the chords' echoes:
  `TranslateMessage` queues a `WM_CHAR` of 0x01–0x1A for Ctrl+letter
  and 0x7F for Ctrl+Backspace whatever `WM_KEYDOWN` returned, and the
  control-character filter above already drops exactly those.
- **IME.** IMM32: `WM_IME_COMPOSITION` streams `GCS_COMPSTR` as
  `on_ime_update` (caret converted from UTF-16 units to the UTF-8 byte
  offset the contract asks for), `GCS_RESULTSTR` as `on_ime_commit`, and an end
  without a result cancels. The IME's own composition window is
  suppressed — core renders the composition inline — while the
  candidate list stays, and that list is docked at the caret
  (`ImmSetCompositionWindow` plus `ImmSetCandidateWindow` from
  `caret_rect`, at composition start and on every update) instead of
  opening at the window's origin, which is where an IMM context with no
  form of its own puts it. The rects cross the shell's integer device
  scale on the way out, since core answers in logical pixels and IMM
  wants client ones, and the candidate form is `CFS_EXCLUDE` — the
  caret's line is what the list must not cover, so an engine that would
  sit on the text being composed drops below it.
- **Deep links** ([services.md](../services.md)). The one shell with no
  packaging derivation: an unpackaged Win32 app has no verified https
  App-Link (that is MSIX's `windows.appUriHandler`, a different packaging
  model nokre does not produce), so the URL arrives through a custom
  scheme the developer registers in the registry — the scheme-agnostic
  posture services.md already states. That launches a fresh process with
  the URL on the command line; `nokre_shell_run` parses it off
  `GetCommandLineW` (`CommandLineToArgvW`, the first `://` argument) and
  buffers it until the app's first build registers its handler, the macOS
  launch-URL bargain. A link tapped while the app runs launches a *second*
  process, which finds the running window by class **and** title and hands
  the URL over with `WM_COPYDATA` before exiting — Android's
  singleTask/onNewIntent, done with the tools an unpackaged app has —
  rather than stacking a duplicate. A plain launch (no `://` argument)
  forwards nothing, so two ordinary launches still both run.
- **Locale** ([services.md](../services.md)).
  `GetUserPreferredUILanguages(MUI_LANGUAGE_NAME, …)` — the reading
  language, not `GetUserDefaultLocaleName`'s formatting locale (an
  English UI with German number formats is an ordinary setup, and it is
  the reading language that has to choose the bundle); the formatting
  locale is the fallback only when that preference list will not fit the
  buffer. The change signal is `WM_SETTINGCHANGE`'s `intl`, the
  dark-mode leg's neighbor below, and it fires for *any* edit on the
  regional page — so the leg re-reads and reports only when the bytes
  moved, or changing the short-date format would wake a frame and re-run
  the app's handler for nothing.
- **Dark mode.** `AppsUseLightTheme` in the registry, re-read on
  `WM_SETTINGCHANGE`'s `ImmersiveColorSet`; the title bar follows via
  `DWMWA_USE_IMMERSIVE_DARK_MODE` (frame chrome is the OS's to theme —
  nokre content itself never recolors).
- **Toolchain.** The Skia prebuilt is MSVC-ABI, so `-Dskia` builds
  target `x86_64-windows-msvc` (build.zig defaults the ABI; Visual
  Studio's C++ Build Tools required) and text rasterizes through the
  prebuilt's FreeType from memory — pixels match the Linux and Android
  builds, not the CoreText platforms, which is the intended shape
  ([pixel-model.md](pixel-model.md)). Two
  consequences wired in build.zig: AccessKit's Rust static library
  supplies the compiler intrinsics zig's compiler-rt would duplicate,
  and FreeType's gzip references resolve to a never-runs stub
  ([shim/nokre_skia_zlib_stub.c](../../shim/nokre_skia_zlib_stub.c)).

## Android specifics

[android/android.zig](../../src/platform/android/android.zig) speaks
the contract with the boundary inverted: Android owns the event loop
(the Activity), so instead of a blocking `nokre_shell_run` the Zig side
exports `nokre_android_*` functions that forward into the shared c_shell
adapters, and the native side is
[android/shell.c](../../src/platform/android/shell.c) (JNI plumbing +
ANativeWindow blit, compiled by the example's CMake) plus the Java half
in [android/java](../../src/platform/android/java) — `NokreView` (the
shell proper) and `NokreActivity` (lifecycle), which the consumer's
manifest declares directly, the way the iOS app delegate lives in
shell.m. Its twists:

- **Boot.** `main` never runs — the consumer's root module exports
  `nokreAndroidBuild(gpa) !*App` and `nokre_android_boot` calls it (the
  `nokreWebBuild` bargain), with one comptime line forcing the export
  block into the build. The allocator is bionic's malloc
  (`std.heap.c_allocator`) — the same heap the NDK-linked Skia uses.
- **Blit.** `SurfaceView`: shell.c locks the `ANativeWindow`, copies
  the RGBX rows straight into the window buffer (the one shell whose
  format matches the frame's), and posts. The buffer stays at
  the window's own pixel size so the compositor never scales; density
  rounds to an integer scale and logical size is the ceiling, remainder
  cropped at the edge (the Windows policy). Edge-to-edge on API
  30+: the gesture-nav band's height is `safe_bottom`, the IME inset
  shrinks the view, and pre-30 devices run inside system windows with
  `adjustResize`.
- **Touch.** A `GestureDetector` tap sends `on_pointer` DOWN then UP at
  the recognized point. `onTouchEvent` asks `wants_pointer_stream` on
  `ACTION_DOWN` first: a claimed gesture is forwarded raw for its whole
  life, and every callback the detector would make for it is refused, so
  tap detection, scrolling and flings are untouched for everything else.
  A running fling is halted in that branch *before* the detector sees
  the press, so `onDown` finds nothing to stop and does not also swallow
  it — the iOS exemption by the same reasoning. Unclaimed drags bracket
  `BEGIN`/`MOVE`/`END` with the anchor locking core's routing, and
  flings hand off to `OverScroller` — the platform's own physics, the
  iOS hidden-UIScrollView bargain — stepped inside the paced frame
  below while decelerating. A touch during a fling stops it without
  also activating what it lands on. The detector's long press is armed
  only while a field holds focus (`setIsLongpressEnabled` follows
  `wants_text_input`) and then sends `on_long_press` wherever it landed,
  since core hit-tests the point itself. Arming it everywhere would cost
  the tap: a recognized long press cancels the `onSingleTapUp` that
  would otherwise follow, so a slow press on a button would stop
  activating it.
- **Clicks.** **The view counts the run, not the `GestureDetector`.**
  The detector stops at two — after a double tap it arms no further tap
  message, so a third tap arrives at it as a fresh first press — and
  taking the count from it cost the third tap twice over: core's
  paragraph granularity was out of reach by finger, and the 1 landed on
  the handle the double tap had just raised, where core reads a first
  press as a grab and drags one end of the selection instead. So
  `NokreView` counts every press of the run against the reader's own
  `ViewConfiguration` numbers — `getDoubleTapTimeout()` since the last
  press let go, `getScaledDoubleTapSlop()` from where it landed, the
  same tool — and the run ends where the platform ends it: a long
  press, a second finger, a cancel, or a gesture that crosses
  `getScaledTouchSlop()` and becomes a drag, a scroll or a fling.
  Owning the whole run and not resuming after the detector's two is
  what leaves one counter, with no second state machine to disagree
  and no 1, 2, 3, 2, 3 ladder. The detector keeps what it alone
  knows — long press, scroll, fling, and which of the two callbacks a
  recognized tap arrives on (`onSingleTapUp`, or `onDoubleTapEvent`
  gated to `ACTION_DOWN`, which is what makes it the tap that just
  landed rather than `onDoubleTap`'s first one) — and both callbacks
  now send the view's count. **A claimed gesture carries the same
  count**: this is the case `on_pointer` names, since what claims the
  stream over a field is a grab target and so the second tap of a
  double tap into a field is claimed by construction — the boundary
  moves *inside* a run, the first tap unclaimed and the second claimed,
  and one counter across both paths is what keeps the run from
  restarting there. The detector's own non-public minimum gap between
  taps has no equivalent here, because it guards a decision this
  counter does not make: it decides whether a pending tap *delivery* is
  cancelled, where a bounce costs a whole tap, while here every press
  is delivered and a spurious one can only raise a count — and only a
  count of 1 grabs. The tool comes from `MotionEvent.getToolType`, read
  per event rather than latched, since this is the one platform that
  answers it per event and has nothing to latch.
- **Pacing.** One `Choreographer` frame callback draws; input is
  applied to core on arrival and only marks, and the callback is armed
  by a mark, a geometry change or a running fling — never while the app
  is at rest, so idle stays silent (no `doFrame`, no post). A drawing
  frame arms the next slot *before* it draws, and that order is the
  whole point: the draw holds the main thread past the vsync, the
  batched touch moves are only received when it returns, and a vsync
  requested after its slot has begun fires a slot late — so a frame a
  hair over the 11.1 ms slot cost two of them. Measured on a Lenovo
  TB336FU at 90 Hz scrolling the Library with a virtual finger through
  `uinput` (125 Hz, paced on the device): 45 fps with 89 % of frame
  intervals at two vsyncs before, 81 fps with 94 % at one after, the
  frame itself unchanged (dequeue → queue 9.9 → 8.8 ms median, p90
  11.2 → 11.0). What the pacing costs is a tap: its UP is delivered at
  once, and the draw now waits for the next vsync rather than starting
  inside the handler — UP → first post 5.9–8.4 ms before, 9.1–19.3 ms
  after, at most one slot. A drag costs nothing, since its moves were
  already delivered at the vsync. The cadence that remains above one
  vsync is the frames that run past the slot, and they belong to the
  raster: the shell arms ahead but still draws on the thread that
  receives input.
- **Back.** Android's gesture navigation owns both screen edges, so
  there is no drag for the app to see and no `on_edge_pan` leg here:
  the OS runs its own threshold, draws its own predictive-back preview,
  and delivers a decision. `NokreActivity` routes it to `on_back` and
  finishes the activity when nokre had nothing to pop. Both roads are
  wired — the API 33+ `OnBackInvokedDispatcher` and the older
  `onBackPressed` — because which one is live is the consumer
  manifest's `enableOnBackInvokedCallback` choice and, from API 36, the
  platform's default; the system never uses both.
- **Text input.** The view's `InputConnection` is the focused field
  ("The honest document" above): the four getters and `getExtractedText`
  slice the snapshot, `setSelection` states it back as `on_select`, and
  `onCreateInputConnection` fills `initialSelStart`/`initialSelEnd` —
  the one selection report that cannot travel as `updateSelection`,
  because there is no connection yet to send it on. Every later one
  does, after each dispatch, so the keyboard's own idea of the caret
  tracks core's. `getSurroundingText` is overridden beside the older
  getters and not left to `BaseInputConnection`, whose answer comes from
  an editable that is empty here — an IME on API 31 or later asks only
  the new question. Offsets cross as UTF-16, converted in this shell
  against the same bytes core is holding. The composition is *not* in
  those bytes — core keeps the pre-edit beside the field — so the
  connection splices it back in at the caret, and that splice is exactly
  the composing region the IME is told about; `setComposingText` streams
  `on_ime_update`, commits and `finishComposingText` land as
  `on_ime_commit`, an emptied composition cancels.
  `deleteSurroundingText` measures its two lengths from the two ends of
  the *selection*, and each run travels as its own `on_delete_range` —
  the run after the selection first, so the earlier run's offsets are
  still the ones this shell computed. Mid-composition it does nothing at
  all: the pre-edit is the IME's own to edit.
  `deleteSurroundingTextInCodePoints` walks the document's code-point
  boundaries and hands the same method the char counts, so there is one
  implementation of the deletion. Suggestions stay off, and whether the keyboard's smart
  mutations come back is its own undecided question. The same snapshot
  is what `AccessibilityNodeInfo.setTextSelection` carries on the
  focused field's node, which is the door
  [accesskit.zig](../../src/a11y/accesskit.zig) names when it declines
  to carry a range itself. The keyboard shows and hides off
  `wants_text_input` after every event, and text crosses JNI as
  standard-UTF-8 `byte[]` — never
  `GetStringUTFChars`, whose *modified* UTF-8 would mangle emoji.
  Hardware keys map in `onKeyDown`, with printable characters sent as
  text instead — Space by whichever leg `wants_text_input` selects — and
  the Ctrl chords map onto the semantic keys before anything else, so
  Ctrl+Left is a word and not an arrow. Ctrl+V is not among them,
  because a paste is not a key: it is `nokre_shell_request_paste`'s own
  read of `ClipboardManager`'s primary clip, delivered as text, and the
  chord and the framework's edit row reach it through the one method. An
  unmapped Ctrl chord types nothing — `KeyCharacterMap` ignores Ctrl, so
  the text fallback would write the bare letter — unless Alt is held
  with it, which is how some layouts spell AltGr. The
  editor declares `IME_ACTION_SEARCH` exactly while
  `wants_submit_action` says the field would act on one, and
  `IME_ACTION_NONE` otherwise. `imeOptions` is read once, at
  `onCreateInputConnection`, so moving focus between a field that
  submits and one that does not restarts the connection — without that
  the key keeps the label of the field before it. The action key does
  **not** arrive as `commitText("\n")` the way the plain return does:
  the IME calls `performEditorAction`, which `BaseInputConnection`
  answers with nothing, so the connection overrides it and sends the
  same Enter.
- **Deep links** ([services.md](../services.md)). `NokreActivity` reads the
  App-Links intent's data URI — `getIntent()` at launch, `onNewIntent`
  while running — and hands it to `NokreView.deepLink`, which crosses JNI
  as standard-UTF-8 `byte[]` (the text path's rule) to
  `nokre_deep_link_install`'s callback on the UI thread. The launch URL is
  buffered in C until the app boots and registers its handler. The
  generated manifest adds `android:launchMode="singleTask"` when
  deep_link is claimed, so a link routes to the one running instance
  rather than stacking a duplicate.
- **Locale** ([services.md](../services.md)). The tag comes from Java —
  `Configuration.getLocales().get(0).toLanguageTag()`, not
  `Locale.getDefault()`, because the `LocaleList` honors the Android 13
  per-app language override that the app's own resources already follow
  — and crosses JNI as standard-UTF-8 `byte[]`, the text path's rule.
  Its change lane is unlike every other shell's: the generated manifest's
  `configChanges` ([packaging.zig](../../src/packaging/packaging.zig))
  deliberately does not claim `locale`, so an OS language change
  *recreates the Activity* instead of calling `onConfigurationChanged`.
  The shell reboots, the app does not (`nokre_android_boot` is idempotent,
  so install runs once per process), so `NokreView`'s constructor reports
  the tag again right after `nativeBoot` and the C side drops the report
  when the bytes have not moved — a recreate for any other reason costs
  nothing. Claiming `locale` in the manifest would be cheaper at runtime
  and is still not done: the recreate path has to be correct regardless
  (the system recreates for reasons no `configChanges` list opts out
  of), and one lane that always works beats two that mostly do.
- **Blit.** None: the shell locks the window buffer first and hands it
  to `nokre_android_frame_into`, and the shim rasterises the frame's
  bands straight into it (`hsk_surface_render_into`) — RGBX on both
  sides, so no row is copied. The source declines a frame that does
  not begin by painting every pixel or a buffer smaller than the frame,
  and the shell then takes `nokre_android_frame` and copies row by row
  as it always did. On a Lenovo TB336FU at 1600x2560 the copy was
  2.9 ms of an 11.6 ms frame.
- **Packaging.** `zig build -Dtarget=aarch64-linux-android` produces
  one static library of all the Zig (no C rides along — qrcodegen and
  the shim need bionic headers zig does not bundle); the example's
  [Gradle project](../../examples/kitchen_sink/android) compiles the
  JNI shell, shim, and qrcodegen with the NDK — one C/C++ toolchain
  with the NDK-built Skia
  ([tools/build-skia-android.sh](../../tools/build-skia-android.sh),
  FreeType from memory, so pixels match the Windows and Linux builds) —
  and links `libnokre_app.so`. Worker wakes ride
  `nokre_shell_post_main`, implemented as a pipe on the main thread's
  ALooper (the Windows message-loop lend, relocated).

## Linux specifics

[linux/shell.c](../../src/platform/linux/shell.c) is a Wayland port of
the same contract — plain C against libwayland, one poll loop, no
framework. X11 is deliberately absent: Wayland is the modern default,
and one backend per platform is the charter. Its twists:

- **Blit.** `wl_shm`: the shell swizzles RGBX to XRGB8888 into a
  double-buffered memfd pool and commits the free buffer, tracking
  `wl_buffer.release` so it never overwrites one the compositor still
  holds. Integer buffer scale from the `wl_output` the surface is on, the
  logical size from `xdg_toplevel.configure` — the Windows integer-DPI
  policy, so glyphs never resample. The generated `xdg-shell` and
  `text-input-unstable-v3` client glue is produced by `wayland-scanner`
  at build time (build.zig), never committed — the qrcodegen/harfbuzz
  vendoring rule.
- **Window identity.** `RunOptions.app_id` is set as the
  `xdg_toplevel` app_id — the key compositors match against
  `<app_id>.desktop` for the icon, task grouping, and deep-link handler
  registration. It defaults to the packaging declaration's id, so it
  cannot drift from the `.desktop` file `zig build pkg` names; null (no
  declared identity) sets none at all, because a wrong id breaks the
  association worse than none. This is the one shell that consumes the
  field — every other platform derives identity from the bundle or
  package, not the window.
- **On demand.** The loop blocks in `poll()` over the display fd, a
  worker/a11y wake `eventfd`, a keyboard-repeat `timerfd`, a
  long-press `timerfd`, the single-instance socket, the D-Bus fd, and
  the read end of a paste transfer while one is open; it renders only
  when the frame is dirty (a configure, an input event whose
  `wants_frame` is true, a wake). No frame-callback ticker — an app at
  rest costs zero CPU, and the `wl_display_prepare_read`/`read_events`
  handshake keeps the sleep race-free.
- **Input.** `BTN_LEFT` press is the tap; `wl_pointer.axis_value120`
  sends `FREE` scrolls at 48 logical px per detent with sub-notch
  remainders (the Windows `WHEEL_DELTA` parity), falling back to `axis`
  below v8. Keys map through xkbcommon (`XKB_KEY_*` → `NOKRE_KEY_*`);
  printable text arrives via `xkb_state_key_get_utf8`, control
  characters filtered — they already traveled as keys, so nothing fires
  twice. Space, having no text system here to defer the choice to, is
  routed by `wants_text_input` in `dispatch_key` itself: a focused field
  makes it a character like any other. The compositor delegates
  key repeat, so the shell drives one `timerfd` for the held key —
  and each semantic key says whether it repeats at all, because a held
  Ctrl+Z unwinding a field's whole history is not what holding a key
  means, while a held Ctrl+Backspace is.
  The Ctrl chord table is GTK's (A, C, X, Z, Y and Shift+Z, ←, →,
  Backspace, Delete), read off **level 0 of the layout** so Shift stays
  a modifier bit rather than a second table, and searching the keymap's
  other groups for a Latin letter when the active one has none — a
  Persian or Cyrillic group spells Ctrl+C with a keysym no table can
  hold, and the Latin group beside it is where the letter is. Ctrl+V is
  not in the table: paste is the platform's verb, not a key.
  `BTN_RIGHT` is `on_long_press`; so is a `wl_touch` press held 500 ms
  without wandering, which is the one recognizer this shell owns
  (Wayland recognizes nothing for a client) and the reason for the
  second `timerfd` — key repeat can be pending while a finger rests,
  and one timerfd carries one deadline. Firing it cancels the press
  first, as the contract requires. Touch otherwise *is* the pointer stream, one finger at a time; there
  is no touch scrolling here and so nothing for `wants_pointer_stream`
  to arbitrate. A `wl_pointer` press reports `MOUSE` and a `wl_touch`
  press `TOUCH`, which is what gives a Wayland tablet the caret's grab
  handle.
- **Clicks.** No Wayland protocol carries a click count, and none
  carries the reader's double-click speed either — that setting lives in
  each desktop's own configuration, which a shell this thin does not
  parse — so this shell counts, the way it already owns the key repeat
  the compositor delegates. A press within **400 ms** and within a small
  slop of the last one, *from the same kind of device*, is the next
  click of that run; anything else starts a new one, as does a
  secondary click, the pointer leaving the surface, a cancelled touch,
  or a long press taking the gesture. 400 ms is GTK's and Qt's shared
  default, so the number is the one the desktop around this app already
  uses; the slop is 5 px for a pointer and the long press's wider 10 px
  for a finger, and both are argued where they are defined.
- **IME.** `zwp_text_input_v3`: `preedit_string` streams `on_ime_update`
  (the caret is a UTF-8 byte offset by contract, and `cursor_begin`'s
  -1 "hide it" maps to the end), `commit_string` lands
  as `on_ime_commit`, and the batch applies on `done` — the enable/disable
  follows `wants_text_input` after every event, which is what raises an
  on-screen keyboard where the compositor offers one. The document is
  the field ("The honest document" above): `set_surrounding_text` from
  `editable_snapshot` and `set_cursor_rectangle` from `caret_rect`, so
  the candidate popup docks at the caret, pushed only when one of them
  moved — a commit per event would reset a live composition. The bare
  `value` is already the right document here and nothing is spliced into
  it, because v3 defines both the surrounding text and the deletion
  lengths as excluding the pre-edit; a shell that spliced would place
  every deletion an IME asks for wrong by the composition's own length.
  The protocol carries at most 4000 bytes of surrounding text, so a longer
  field crosses as a window centred on the caret, cut at codepoint
  boundaries with an out-of-window anchor clamped to the edge; an
  `obscured` field crosses as *no* text at all under
  `content_purpose` password, stated empty rather than skipped so the
  IME cannot keep holding the previous field's sentence.
  `delete_surrounding_text` arrives before the commit it makes room for
  and travels as one `on_delete_range`: v3 measures both lengths from
  the cursor itself, so the two runs meet there and the deletion is the
  single span around it.
- **Deep links** ([services.md](../services.md)). Like the Windows leg,
  no packaging derivation: an unpackaged app has no verified https
  association, so the URL arrives through a custom scheme the developer
  registers in a `.desktop` `x-scheme-handler`. The OS launches a fresh
  process with the URL in argv (read from `/proc/self/cmdline`); if this
  app already runs, the new process forwards the URL over an abstract
  Unix socket named for the app and exits — the WM_COPYDATA / onNewIntent
  bargain — rather than stacking a duplicate. The launch URL is buffered
  until the app's first build registers its handler.
- **Locale** ([services.md](../services.md)). POSIX keeps it in the
  environment, in the precedence `setlocale` itself obeys: `LC_ALL`, else
  `LC_MESSAGES` (the message-catalog category — the one that decides
  which language a user *reads*, as against `LC_NUMERIC` and friends),
  else `LANG` — read with `getenv` and never through `setlocale`, whose
  job is to mutate the C library's global state, not to answer a
  question. The value is a POSIX locale name, so the codeset and modifier
  are stripped and `_` becomes `-`
  (`fa_IR.UTF-8@calendar=persian` → `fa-IR`); that strip is load-bearing
  rather than cosmetic, since l10n's tag compare starts with the length,
  so an unstripped value would miss the exact match and silently demote
  `fa_IR` to whatever bare `fa` bundle exists. `C`, `POSIX`, and unset
  all report the empty tag. **No change source, which is the honest
  answer and not the lazy one:** the environment is fixed at `exec` and
  cannot move under a running process, Wayland has no locale event, and
  the portal Settings namespace this shell already speaks carries
  `org.freedesktop.appearance` keys and nothing about language. The
  callback fires exactly once, inside install; a user who switches
  language restarts the app, as they must for the GTK and Qt programs
  beside it.
- **Clipboard & appearance.** Copy is a `wl_data_source` offering the
  text mime-types and set as the selection. The *service* stays
  write-only; the one read is the paste verb's, on the user's own
  action, out of the `wl_data_offer` the compositor already handed it
  ("The honest document" above). That read is a `receive` of
  `text/plain;charset=utf-8` into a pipe the poll loop drains across
  iterations, so `nokre_shell_request_paste` returns before the bytes
  arrive — the header's "otherwise soon, on the main thread" — and no
  slow source can stall the window. A selection this process *owns*
  skips the pipe and delivers its own bytes: the compositor would ask
  this thread for them, and a clipboard past the pipe's capacity would
  block that write against a reader that is this same loop. A transfer
  over 64 KiB is dropped whole rather than truncated mid-codepoint, and
  a second Ctrl+V abandons a transfer still in flight instead of
  queueing behind a source that never wrote. Dark mode is the
  `org.freedesktop.appearance color-scheme` value read from
  xdg-desktop-portal over D-Bus, re-read on the portal's `SettingChanged`
  signal; absent a portal the shell reports light, the honest default.
- **Accessibility.** AccessKit's Unix adapter (AT-SPI — Orca) registers
  the process on the a11y bus. Unlike the macOS/Windows subclassing
  adapters it has no window handle and runs its handlers on its own
  thread, so the shim (shim/nokre_accesskit.c) marshals assistive-tech
  actions to the UI thread through `nokre_shell_post_main` — the Windows
  message-only-window marshal relocated to the wake eventfd.
- **Toolchain.** `zig build … -Dtarget=x86_64-linux -Dskia` links the
  Linux Skia + AccessKit prebuilts (tools/fetch-deps.sh) with the system
  `wayland-client`, `xkbcommon`, `dbus-1`, and `libsecret-1`; text
  rasterizes through the prebuilt's FreeType, so pixels match the
  Windows/Android builds.

## The web has no shell

It had one: a wasm module driven from a Worker, blitting Skia's buffer
into a canvas and mirroring the a11y snapshot into a hidden ARIA tree.
That shell is gone, and so is the Skia build behind it.

What replaced it is not a shell at all. The browser already *is* one —
it owns the event loop, the window, the input, the text rasterizer and
an accessibility tree — so nokre's substrate there renders the semantic
tree into that document rather than beside it
([dom-substrate.md](dom-substrate.md)). There is no surface to blit, no
frame to request, no ARIA to mirror, and nothing on this page to
specify: the contract below describes the five shells that drive a
`FrameSource`, and the web drives none.

What the web still shares with them is everything above the shell line:
the same `App`, the same tree, the same services. The service hooks a
linked service calls out through are the same free functions this
document names, answered in JavaScript
([services.js](../../src/render/dom/services.js)) instead of in C.

## The headless shell

One more program sits in the shell's seat: a *driver* — a headless
native binary (nokre's own `tests/dev_store.zig` and
`tests/http_stress.zig`, a consumer's system-test or e2e runner) that
links the library and therefore owes the same free functions. nokre
ships that shell as
[src/testing/shell.zig](../../src/testing/shell.zig), and its doc
comment is the contract: which hooks it defines, why three of them
record instead of staying silent, and why naming the module
(`comptime { _ = nokre.testing.shell; }`) is the whole install. Two
shell-side facts belong here rather than there. It is `export`s only —
linking it into a windowed build collides with the real shell's
definitions, and that loud duplicate-symbol error is the intended
guard. And it installs no wake and owns no loop: worker and http
replies queue until the driver's own `app.runtime.pumpDeliveries()` runs
([workers.md](workers.md)), which is the pump the platform shells wire
into their main loops and a driver runs by hand — the consumer-facing
half of that story is [testing.md](../testing.md)'s "Driving an app
outside `zig test`".

## IME

The IME protocol (start/update/commit/cancel) is part of core
([src/core/event.zig](../../src/core/event.zig)) and the composition string
renders identically everywhere.

`update` carries the caret with the pre-edit — a **UTF-8 byte offset
into the composition** — and core draws it there. Every shell already
converts into that unit from whatever its engine reports: `cursor_begin`
on Wayland is already bytes, IMM32's `GCS_CURSORPOS` and Apple's marked
range are UTF-16 units the shell converts, and Android's
`InputConnection` hands over the selection within the composing region.
Core clamps and snaps to a codepoint boundary on the way in
(`editing.handleIme`), so a shell that converts wrong loses the caret's
position and nothing else. A shell whose engine will not say — the web,
where `compositionupdate` carries no caret — sends the end, which is
where a caret that never moved sits anyway. Shell-side IME is implemented on macOS
(NSTextInputClient), iOS (UITextInput), Windows (IMM32), Android
(InputConnection), and Linux (text-input-v3) — every shell. The web's
fields are real DOM inputs, so the preedit is composed *in the field*
by the browser itself; the live driver forwards the same
update/commit/cancel legs into core off the composition events, and
what an open session owns on that platform is
[dom-substrate.md](dom-substrate.md)'s to say.

## The accessibility bridge

The semantic `Snapshot` ([accessibility.md](../accessibility.md)) is
produced and tested platform-independently; a shell only attaches an
adapter:

- **Desktop/mobile:** the snapshot feeds [AccessKit](https://accesskit.dev),
  which fans out to VoiceOver, NVDA/JAWS (UIA), Orca (AT-SPI), TalkBack.
  The binding is live on macOS (VoiceOver), Windows (UIA — Narrator,
  NVDA, JAWS), and Linux (AT-SPI — Orca) via accesskit-c:
  [src/a11y/accesskit.zig](../../src/a11y/accesskit.zig) flattens the
  snapshot into a plain-C node array, and
  [shim/nokre_accesskit.c](../../shim/nokre_accesskit.c) translates it
  into AccessKit tree updates — role and action mapping is
  compile-checked against the real `accesskit.h`. Click and focus actions
  from assistive tech dispatch back into the same core event path as
  pointer input, marking the view dirty via `nokre_shell_request_frame`.
  Two Windows wrinkles live in the shim: the subclassing adapter wraps
  the window procedure, so it attaches while the window is still hidden
  (shell.c orders `on_ready` before `ShowWindow`), and UIA may deliver
  actions off the UI thread, so they marshal through a message-only
  window before dispatch. The Linux Unix adapter has the same off-thread
  wrinkle without a window: it holds no HWND and runs its handlers on its
  own thread, so the shim marshals actions to the UI thread through
  `nokre_shell_post_main` (the wake eventfd) and serializes its tree reads
  with a mutex. Other desktop shells reuse the shim and add only the
  per-platform adapter glue.
- **iOS:** no AccessKit — UIKit's UIAccessibility natively consumes a
  flat element list, so the shell builds `UIAccessibilityElement`s
  straight from the same flattened node array (roles → traits, the
  topmost modal's subtree only, activate/VoiceOver-focus dispatching
  back like clicks). Same fill/action callbacks, no extra library.
- **Android:** no AccessKit either — `NokreView`'s
  `AccessibilityNodeProvider` serves virtual `AccessibilityNodeInfo`s
  from the same flattened array (shell.c walks it and hands each node
  across JNI; roles → class names, the topmost modal's subtree only,
  flat under the host view like iOS). TalkBack's click and
  accessibility-focus dispatch back through the same fill/action
  callbacks, and a content-changed event fires after frames while
  assistive tech listens.
- **Web:** nothing to bridge — the DOM substrate renders the semantic
  tree as the document, so the browser's accessibility tree is the
  output, not a mirror ([dom-substrate.md](dom-substrate.md)).

## Writing a new shell

Port `shell.h` to the platform's windowing API (~300–500 lines of native
code), map keycodes to the `NOKRE_KEY_*` enum — Space by the one-leg rule
above, which no golden can catch for you, and the platform's own editing
chords onto the semantic keys, since core will not map them for you —
blit RGBX. Fill the platform's text document from `editable_snapshot`
rather than from the composition, which is the mistake this contract was
widened to stop ("The honest document" above). Add
`nokre_locale_install` with it — the one service hook that has no unlinked
path, so an omission is an unresolved symbol rather than a missing
feature (the contract, including the fire-before-you-return clause, is
above). Then run the kitchen-sink example and the golden suite; if
goldens pass, the platform renders byte-identically and the job is done
— remembering that byte-identity is per-platform by design
([pixel-model.md](pixel-model.md)): the committed goldens are
macOS-generated, so a new shell validates against its own regenerated
set, permanently, rather than waiting for one set to serve everything.
