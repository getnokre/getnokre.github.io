# Contributing

Core values are in [../../CLAUDE.md](../../CLAUDE.md), "Values" — read
those first. The consumer docs ([introduction](../introduction.md) onward)
state what nokre promises; this directory is how the promises are kept.
Start with [architecture.md](architecture.md) for the layer rules — they
are enforced in review, not aspirational.

## Conventions

- After any change: `zig fmt src/`, then `zig build test`.
- Modules past a few hundred lines keep their tests in a sibling
  `*_test.zig`, wired from the test block in
  [src/nokre.zig](../../src/nokre.zig); small modules keep design-proof
  tests inline. Implementation files should read in one pass.
- Comments carry design rationale — WCAG citations, why-not-the-obvious.
  Keep that voice; don't add narration. The checklist for keeping one true
  is [below](#comments).
- Integer math in layout, geometry, and anything that produces
  coordinates or bytes. The one sanctioned float user is the contrast
  check in [color.zig](../../src/core/color.zig) — deterministic
  IEEE-754, a construction-time gate that never positions a pixel. No
  clocks, no randomness — anything nondeterministic breaks the
  [pixel model](pixel-model.md). Both carve-outs live in services and
  nowhere else (`oauth`'s CSPRNG, `clock`'s wall time), for the reason
  stated at each: a service is not core, and neither one may be reached
  from `src/core` or `src/render`.

## Comments

A comment earns its place by carrying what the code cannot: a constraint, an
invariant, a rejected alternative, a contract a signature does not spell. That
much is the voice, and it is already the house style. What this codebase
actually accumulates is not narration — it is comments that were true once.
Treat a comment as code: it is reviewed and updated with the behavior it
describes, in the same change, and a comment touched by a change gets read even
when the change is not about comments.

Before leaving a comment in place, check it against each of these. Every one
has caught a live defect here.

- **It sits on what it describes.** A doc block runs to the *next* declaration,
  so a missing blank line silently reassigns it — a contract reading "returns
  the field" can end up on a `const`, leaving the function it belonged to
  undocumented. When two declarations sit close together, check which one the
  compiler thinks the doc is on.
- **Its references resolve.** Symbols get renamed and `docs/` pages get
  rewritten. Never quote another document verbatim: restate the fact and cite
  the page, so a rewrite there cannot leave a lie here. Point at symbols by the
  name they have today.
- **Its checkable claims still check.** Counts, widths, ordinals, "N of them",
  "four lines up". If a test proves otherwise, the test wins and the comment is
  wrong — fix the words, and do not touch a fixture to make a sentence true.
- **It states the library's fact, not a consumer's.** A downstream site's page
  count or route names in a library comment will rot on someone else's schedule.
- **It has one home.** Each fact lives in one place and is pointed at from the
  others; a second copy is a future contradiction, and the two will not drift
  together. Where a `docs/` page, a sibling module, or the declaration above
  already owns the fact, reference it instead of restating it.

Delete on sight: dead plan labels from a finished round ("Part E", "B3"),
tombstones for symbols that no longer exist, and a section heading with no
section under it. A `// ---- label ----` divider over a real API surface in a
long module is not ceremony — keep it, and keep any docs anchor it carries.

## Adding an element

The element set is closed on purpose; additions are argued on semantics,
never styling ([introduction.md](../introduction.md) has the argument).
If a proposed element can't state its semantics in one sentence, it
doesn't go in. When one does, it is a cross-cutting commitment:

1. Struct + `Element` union arm + `Role` in
   [element.zig](../../src/core/element.zig)
   (`role()`, `isInteractive()`, `isFocusable()`, `label()`,
   `needsRuntime()` — that last one decides whether a page holding the
   element can be published as a file with nothing running behind it,
   and its switch is exhaustive so the answer cannot be skipped; it
   switches on the *element*, so where a field of yours decides whether
   the thing navigates or acts, read that field the way `tile` reads
   `route` rather than answering for the kind), and its
   cursor method in [cursor.zig](../../src/core/cursor.zig) in the same
   pass — the builder is closed exactly as the element set is, and the
   comptime check there refuses to compile a union member the cursor
   cannot spell. No `...Id` twin: those four exist for the leaves real
   screens patch mid-flight, and a new one earns its twin from a call
   site, not from symmetry. A text-shaped field is also the l10n
   check's business: every one is classified as *words* or as *data* in
   [l10n/check/literals.zig](../../src/l10n/check/literals.zig), and an
   unclassified one is a compile error there rather than a rule that
   quietly stops covering an element
   ([localization.md](../localization.md), "What the build checks").
2. Layout rules in [layout.zig](../../src/core/layout.zig) — including
   the element's stance on the advised margin (`Ctx.margin`): apply it,
   the default; or, only if the element must reach an edge to work,
   decline it and bleed. A new container must state whether it passes
   the advice through (borderless flow) or consumes it (anything that
   draws or clips an edge) — `flowChildren` demands the choice at every
   call site. Any leading/trailing geometry mirrors under `Ctx.rtl`:
   place intrinsic blocks with `startX`, not a bare `x`, and give each
   corner control a left/right branch. Vertical geometry is
   direction-blind — don't touch it.
3. Drawing in [renderer.zig](../../src/render/renderer.zig) — mirror the
   same leading/trailing choices with the renderer's `mirrored(app)` /
   `startX(app, …)`. Content that must not mirror (paragraph text aligns
   by its own bytes; a QR symbol never flips) stays put — say why in a
   comment, as the QR and radio cases do.
4. Markup in [render/dom/serialize.zig](../../src/render/dom/serialize.zig)
   — the second edition's draw, and the recurring tax
   [renderer-editions.md](renderer-editions.md) named: the switch there
   has no `else`, so this step is a compile error until it is done. Pick
   the tag whose implicit role is already the one `roleOf` gives the
   element, and state the role explicitly only when no tag carries it.
5. A11y mapping in [semantics.zig](../../src/a11y/semantics.zig), and its
   row in the table in [accessibility.md](../accessibility.md). A new
   `A11yRole` **appends** — the enum's ordinals are a wire contract that
   `accesskit.flatten` sends straight to the shim, and the C header
   (the `NOKRE_A11Y_ROLE_*` enum in
   [nokre_accesskit.h](../../shim/nokre_accesskit.h))
   plus the Android and iOS tables mirror it position by
   position (the DOM edition takes no copy — it derives its roles in
   Zig from `roleOf`). Inserting or reordering silently renames every role after
   it; a comptime check in semantics.zig pins the boundary.
6. Construction rules in [tree.zig](../../src/core/tree.zig)
   (`validateAppend`) for structure that must never exist, audit rules in
   [audit.zig](../../src/testing/audit.zig) for content and mutable
   state.
7. Event handling in [input.zig](../../src/core/input.zig) if interactive
   (activation, keys; [editing.zig](../../src/core/editing.zig) if it
   edits text).
8. Unit tests for each of the above (in the module's sibling
   `*_test.zig`), a kitchen-sink entry, a golden, and the element's row
   of the renderer contract in
   [render/dom/serialize_test.zig](../../src/render/dom/serialize_test.zig)
   — what the second edition must convey, which a pixel golden cannot
   check for it.
9. Its section in [elements.md](../elements.md) — semantics first, then
   the visual spec, then when to reach for it over its neighbors.

## Writing a service

Consumer-facing roster and philosophy: [services.md](../services.md).
The authoring rules that keep the shell/service split honest:

- **One header per service.** No shared "misc" surface. A service that
  needs another service composes on the Zig side, never natively.
- **No third-party dependency, with one argued exception.** nokre has no
  dependency manager, so a vendored SDK would mean inventing one — which
  is why `oauth` takes the browser flow over two vendor SDKs and names
  Custom Tabs' extras by their string constants rather than linking
  androidx. The exception is `iap` on Android: Google removed the AIDL
  interface that was once a protocol and requires the Play Billing
  Library, so there is nothing to reimplement. It is handled by moving
  the cost into the open rather than hiding it — the service's Java half
  lives outside the shell's source set
  ([src/services/iap/java](../../src/services/iap/java)), and a consumer
  who links the service adds the source directory and the coordinate to
  their own `build.gradle`. Any future proposal to take a dependency
  meets this bar: no protocol to speak, the cost stated in the consumer's
  own build file, and the shell unchanged.
- **Native side holds no state.** Same as shells: callbacks carry a
  `ctx`, Zig owns everything.
- **A service may name the shell; the shell may never name the service.**
  A shell links into every app and an optional service's native leg links
  into some, so a shell that calls a service's C function is a link error
  in every app that does not link that service — which is most of them,
  and which no compile-only check can see. Where the OS hands something
  to the shell that only a service can interpret, the shell defines the
  entry and the service installs itself into it: a function pointer
  (notification's Apple push-token sink) or a dispatch the service
  implements (`nokre_notification_dispatch`, `nokre_oauth_dispatch` on
  Android). `__attribute__((weak_import))` is not a substitute — zig's
  MachO linker rejects an undefined weak symbol no input defines, so the
  null check such a shell writes is never reached.
- **Callbacks arrive on the main thread**, interleaved with shell events.
  A service that does async work (OAuth, IAP) delivers results as
  callbacks, never blocks.
- **Optional means optional**, in one of two shapes. A service that
  links something (secure_store's Keychain, deep_link's URL
  registration) gates on its `nokre_*_options.linked` and is a curated
  comptime error at the call site when unlinked. A service that links
  *nothing* — clipboard, clock, haptic, http, locale, open_url, share,
  worker — has no unlinked state to error on, so
  it gets no options module and no build flag: adding one would be
  ceremony over a decision the app never makes. For those, "optional"
  means costing nothing where the platform has no hook (a comptime
  `has_shell_hook` switch, so stub targets never name the extern) and
  having an honest answer where it does — the empty value, never an
  invented one (share's honest answer is `available` false, because a
  missing share sheet is a fact the app draws around, not an empty
  value it can render). Either way core and the shells never depend on a
  service, and the kitchen-sink example runs with zero services linked
  and must keep running that way. (One scoped exception: its *web*
  build declares `.pkg`, because a web app without identity no longer
  builds — the card mandate, [services.md](../services.md) — and that
  links package_info alone; the native kitchen sink stays at zero.)
- **A permission a user answers is never derived silently.** Every
  permission nokre derived before `notification` was normal and
  install-time — invisible at runtime, so the emitter could add it
  without saying so anywhere a consumer reads
  ([packaging.zig](../../src/packaging/packaging.zig)'s BILLING row
  states that rule). A *dangerous* permission is not that: it is
  prompted, refusable and revocable, and it changes what the app's users
  see. A service that derives one states it in its consumer section, and
  models the answer as a tri-state — not-determined, granted, denied —
  because collapsing the first two makes "ask again" the app's most
  tempting bug (`notification`'s `Status`).
- **Web parity is part of the contract.** Each service defines its web
  behavior up front: a services.js implementation, an explicit "absent on
  web" (IAP), or an explicit weaker posture (secure storage → browser
  storage).
- **Injected, never installed.** A new service is a field on
  `Services` ([services.zig](../../src/services/services.zig)):
  define `Service = if (builtin.is_test) Mock else PlatformService`
  (`services.Stateless` where the release half holds nothing, as
  clipboard, clock, haptic and open_url do — writing your own `init`/
  `deinit` pair is then how a service says it *does* keep state, which
  is secure_store's shape: its release half carries the `CountCache`),
  give the mock a `mock(config)` constructor plus `init(gpa)`/`deinit`
  that own its heap state, and wire both into `Services.init`/`deinit`
  — the state lives on the App, applied before `build` runs. The mock
  is nokre's canonical fake: it journals what the app did (the
  clipboard's `copies()`, the store's `journal()`) and takes seeds,
  handlers, and knobs from its config — consumers configure it, they
  never implement transport semantics. HarnessApp integration follows
  (an assertion or settle verb, an `InitOptions` mapping if the config
  is boot state). A module-global `var` is a bug — the design rule in
  [architecture.md](architecture.md). Finally, state the service's
  packaging footprint in
  [packaging.zig](../../src/packaging/packaging.zig) — what manifest
  entries, permissions, or entitlements linking it implies per platform.
  "Emits nothing" is stated in a comment on `Services`, never implied by
  silence, and the manifest goldens
  ([packaging_test.zig](../../src/packaging/packaging_test.zig)) must
  show the derivation as a reviewable diff of the actual artifact.

Any proposal to add intelligence to a shell gets redirected to a service;
any proposal to add rendering or input to a service is rejected the same
way. The shell's complete job description is in
[platform-shells.md](platform-shells.md).

## What nokre tests for itself

All gates run through `zig build test` — see [testing.md](../testing.md)
for the full list. The ones that don't have a `docs/testing.md` page:

- **The contract** — two records held to `revision`:
  [src/public_surface.txt](../../src/public_surface.txt) (library) and
  [src/build_surface.txt](../../src/build_surface.txt) (build API).
  Neither refreshes while the number stands still.
- **The l10n checker's own rules** — [src/l10n/check](../../src/l10n/check/check_test.zig)
  derives its sets from nokre's declarations (not a hand-written list),
  so a nokre that grows one is a compile error in the checker.
- **Shipped JavaScript** — four files from
  [src/render/dom](../../src/render/dom) ride into every consumer's site
  verbatim; Zig only copies them. Each is parsed by node with a goal
  (`node --check` on a bare `.js` passes neither-CJS-nor-ESM files,
  so the check copies under `.mjs`/`.cjs` first). node missing from
  PATH **fails** the build. `-Djs-parse=false` declines it out loud.
- **One transport on a real socket** —
  [native_test.zig](../../src/services/http/native_test.zig) binds a
  loopback origin, puts all six verbs through the native http transport.
  Every other service is proven against its mock (a mock answers
  whatever it is asked).
- **The desktop link** — `zig build test -Dskia`: examples are built,
  not just installed. Kitchen sink links zero services; hello links
  only those that need identity.
- **secure_store outside `zig test`** —
  [tests/dev_store.zig](../../tests/dev_store.zig): a real `App`
  driving four verbs through the dev file store on a macOS or Linux host.
- **The transport's threads** —
  [tests/http_stress.zig](../../tests/http_stress.zig): two `App`s in
  one process, 1920 requests at a loopback origin. Restoring the async
  pool it refuses ([http.md](http.md#no-pool-under-the-native-transport))
  crashes the process on every run.
- **Windowless artifacts** —
  [tests/capture.zig](../../tests/capture.zig): a `DriverApp`-driven app
  writing a step trace and a real RGB PNG; the PNG read back by
  `std.compress.flate` rather than by the encoder that wrote it.
- **The three web-only service legs, executed** —
  [tests/web_services.zig](../../tests/web_services.zig): a real wasm
  app built into a site and booted by node against
  [tests/web_browser.mjs](../../tests/web_browser.mjs). Every assertion
  reads back what the wasm app recorded through probe exports.
- **A real parse of the shipped JavaScript** — same gate as above.

Goldens are byte-exact. CI never creates goldens ([testing.md](../testing.md)
has the workflow).
