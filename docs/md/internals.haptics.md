# Haptics, and the gestures

nokre has one **screen** gesture — a drag inward from the leading screen
edge, which goes back — and its **knock**: the haptic that gesture fires
as it crosses the point where releasing would commit, and again if it
crosses back out. This doc is why both exist in a framework that refuses
animation, and what each platform does with them.

The second haptic is an element's, not the frame's: a [`dial`](../elements.md#dial)
fires one **per detent** as its value passes each one, which is the same
bargain read at a smaller scale — the finger travels, a threshold is
crossed, and nothing moves but the number the crossing produced. It
belongs to the element that owns the gesture (a gesture belongs to
whatever it started on), not to the screen, so the two never fire for
one another.

**The detent is the turning stream's alone.** A key and a step button
land the device rather than turning it through anything, and the figure
that changed is their feedback — no other control in this framework
knocks, and a step that did would make End on a thousand-value range a
thousand knocks with nothing but a cap to defend it. The distinction is
a named type rather than a condition at each call site
(`input.zig`'s `DialTurn`), and both arms go through the one door a
dial's value moves through.

Consumer surface for the gesture: [../routing.md](../routing.md). The
service row: [../services.md](../services.md).

## Why a gesture at all

The obvious way to do iOS-style back is the interactive slide: two
screens on screen at an offset, tracking the finger, settling under its
own power on release. That is something nokre cannot have. A screen 40%
slid has no tree behind it — it is two screens and a state in flight — so
it has no accessible description and no byte-exact frame to golden, and
the frames that would settle it have no tree behind them either. The clock
is not the objection ([../introduction.md](../introduction.md), "No
transitions or animation", draws that line); the missing tree is.

So the gesture is kept and the motion is dropped. **Nothing moves.** The
finger travels, a threshold is crossed, and the feedback for that
crossing is a haptic knock plus the Back control's chevron becoming an
arrow — a chevron points the way navigation goes, an arrow is the going,
so the armed control states the outcome rather than looking like a button
being held (the `copy_glyph` → `copy_check` swap `App.ack` already
makes). On release past the threshold the screen changes the way it
changes when the Back control is tapped: instantly. What is left is the *affordance* — the
thing a thumb reaches for on a large phone — without the animation that
usually carries it.

Two consequences follow from that trade and are load-bearing:

- **No velocity.** A flick that commits below the threshold needs a
  speed, which needs a clock. Position decides, and only position.
- **The gesture is never the only way.** The framework installs a Back
  control on every pushed screen, and it stays the discoverable,
  focusable, screen-reader-reachable path. The gesture is a shortcut for
  people who already know it, not a route to anything the chrome does not
  already offer.

## The threshold

Core owns every decision; a shell reports geometry (`event.zig`'s
`EdgePan`: which physical edge, how far in, which phase) and nothing
else. `input.zig`'s `handleEdgePan` decides:

| | |
| --- | --- |
| eligible | stack depth > 1, no modal open, and the edge is the *leading* one — the left in LTR, the right in RTL, mirrored with the chrome like the Back chevron itself |
| threshold | the numbers are the consumer contract's ([../routing.md](../routing.md#the-back-gesture)); in code, `layout.metrics.back_gesture_*`. A ratio with a floor, because "most of the way across this screen" is a different pixel count on a phone and in a desktop window |
| hysteresis | 8px. Arming takes the full distance; giving it up takes a retreat past the band, so a hand holding still at the boundary settles instead of rattling the taptic engine at the touch stream's sample rate |
| release | past the threshold, `navigateBack()`; short of it, nothing |
| cancel | never commits, and never knocks — the system took the gesture away, and the user did not undo anything |

Eligibility is answered once, at `.begin`, and a gesture that fails it
stays dead for its whole life. That is deliberate: a knock announcing a
navigation that will not happen is worse than no feedback.

## The knock, per platform

Two shells export `nokre_shell_haptic`, and for different reasons: iOS
has both signals, Android has the detent alone. Everywhere else the
extern is never named (clipboard's `has_shell_hook` rule) and `knock`
compiles to nothing — the three desktop shells and the web have neither
a nokre threshold nor a finger turning anything.

- **iOS** — a process-wide `UIImpactFeedbackGenerator` at
  `UIImpactFeedbackStyleRigid`: the sharpest impact style, a knock rather
  than a thud. `prepare` runs when a pan begins, because the Taptic
  Engine idles and a generator asked cold can miss the moment by enough
  to feel late; it runs once more at the first idle moment after launch,
  because the *first* generator of a process also pays for the framework
  and its daemon connection, and that bill should not arrive attached to a
  gesture (`nokreSchedulePrewarm`, which warms the keyboard for the same
  reason and cannot leave the main thread, only wait for it to be idle).
  Arming and disarming are opposite events, so they must
  not feel identical: the same knock at intensity 1.0 and 0.6, rather
  than a second vocabulary for a finger to learn. **The detent is a
  generator of its own**, a `UISelectionFeedbackGenerator`, prepared
  beside the other at the same idle moment: a detent is a value moving
  under a finger rather than a threshold being crossed, which is
  precisely what that generator is for and what `UIPickerView` feels
  like. Borrowing the impact generator would tell the finger a
  threshold had been passed every time the number changed.
- **Android** — the detent, and no arming or disarming, because there
  is no threshold. Gesture navigation owns both screen edges, so the app
  never sees the back drag; the OS runs its own threshold, draws its own
  predictive-back preview, and delivers a decided command, and nokre's
  share is routing it (`on_back`). A dial's detents are the app's own,
  so this is where **Android's first haptic hook** lands:
  `performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)`, the
  constant the platform gives exactly this — the tick of a value passing
  under a finger, what its own pickers and time wheels fire.
  `FLAG_IGNORE_GLOBAL_SETTING` is deliberately not passed, for the
  reason the last section of this page gives.
- **macOS, Windows, Linux, web** — no gesture and no knock. A wheel is
  not a finger on a device, and none of the four has a turning one. The
  web's back is the browser's own, already mirrored through the route
  observer and `hashchange` (a fragment the router cannot honor is put
  back with `history.replaceState`).

There is no nokre-side setting for any of this, because iOS already
honours the system haptics toggle. A framework switch would be a second
answer to a question the OS has asked.

## Why it is a service

`haptic` is a field on `Services` with a journaling mock, and no
consumer-facing verb whatsoever — no `App.haptic(...)`, now or later.
Those two facts are not in tension:

- It is **not a capability** apps get. Firing a buzz on demand is a
  feedback hook in the same family as a styling hook, and the roster
  `iap` closed stays closed to things apps can reach.
- It is **platform-flavored state**, so the injection rule applies
  anyway: nothing platform-flavored may be a module-global extern that
  no test can observe ([architecture.md](architecture.md)). The knock
  *is* the feature here, so a version of it that tests cannot see would
  be a feature with no tests.

Under `zig test` the mock journals every knock in order, which is what
makes "crossed the threshold once, crossed back once, crossed again"
assertable without a finger (`HarnessApp.knocks()`).

## What is testable, and what is not

Everything above the shell boundary: eligibility, the threshold, the
hysteresis band, the knock sequence, cancel-versus-release, the RTL
mirror, and the armed Back control (a golden — `back-armed.ppm` differs
from `back-chrome.ppm` by one glyph, which is the whole visual footprint
of this feature).

A dial's detents are in that set too: the sequence a turning stream
fires, that a bound stops it short, and that a key and a step button
fire none are all assertions over the journal.

Below it, one thing is not: on iOS the edge recognizers must win the
touch against the hidden `UIScrollView` that feeds scrolling, and
`requireGestureRecognizerToFail:` is what arranges that. No headless test
reaches recognizer arbitration — it is verified in the Simulator or not
at all ([shell test tier](platform-shells.md)).

**As of 2026-09-22 two things below the boundary are unproven on a
device.** `Knock.detent` has never been felt: the iOS selection
generator and Android's `performHapticFeedback` are written against the
platform APIs and compile-checked, and `check-targets` is the whole of
what has run over them. Android's is also **the first
`nokre_shell_haptic` that shell has ever exported**, so the JNI method
lookup itself — `haptic(I)V` on `NokreView` — has only been read, never
called. Both are verified on a phone or not at all.
