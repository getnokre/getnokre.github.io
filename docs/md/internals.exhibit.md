# The exhibit, inside

An exhibit is an app that shows another app's recordings: one
[`raree`](../elements.md#raree) per step of each, then the plays on
[stages](../elements.md#stage). It is served from one directory, the
**exhibit root**, which holds the recordings and the manifest that
names them, and it fetches both over `http` from its own origin
(`nokre-serve` lists no directory, so the manifest is what it reads
first). How a recording is made and what it holds is
[stage.md](stage.md#the-recording).

## The root

```
<root>/
  exhibit.json
  scenarios/<scenario>/<tag>.nokreplay
  plays/<play>/<tag>.nokreplay
```

- `scenarios/` is written by `testing.RecordingSink` on a driver run's
  trace — a seeded walk, a journey, a store flow
  ([testing.md](../testing.md#step-traces)). Each run is its own
  process and writes its own file.
- `plays/` is `Plays.recordings` from `addPlays`, installed under the
  root as it is: the plays runner already writes
  `<play>/<tag>.nokreplay`.
- `exhibit.json` is written by `nokre-exhibit-index`
  (`src/exhibit/index_main.zig`) over the two.

Nothing else is indexed. A file that is not a `.nokreplay` is passed
over without a word; a `.nokreplay` at any other place — at the root,
directly under `scenarios/`, a directory deeper, under a third
directory — is listed as refused by its path
(`RecordingIsOutsideTheExhibitLayout`), since a recording nobody can
reach is a mistake somebody made.

## The manifest

`exhibit.json` is `exhibit.ExhibitIndex` (`src/exhibit/index.zig`)
written by `std.json`, and read back by the same type's `parse`: the
writer and the reader are one declaration.

```json
{"revision":203,"app":"Demo","recordings":[{"kind":"scenario","name":"settings_walk","locale":"en","viewport":{"w":440,"h":956},"steps":4,"file":"scenarios/settings_walk/en.nokreplay"}],"refused":[{"file":"plays/ballot/fa.nokreplay","error":"RecordedPlayStampDiffers"}]}
```

| Field | Source |
| --- | --- |
| `revision` | the stamp revision of the nokre that wrote the index (`recorded_play.stamp`); `parse` refuses any other (`error.ExhibitManifestRevisionDiffers`), since a recording it names would be refused too |
| `app` | the exhibited app's name, the tool's `--app` |
| `kind` | the directory under the root: `scenario` or `play` |
| `name` | the scenario's or play's directory name |
| `locale` | the recording's own locale, read by `recorded_play.read` |
| `viewport` | the window the run was acted at, read the same way |
| `steps` | the recording's step count: what a raree counts and a stage counts as one |
| `file` | the path under the root, `/`-separated on every host, which is the URL the exhibit fetches |
| `refused` | each `.nokreplay` that `read` refused, or that stands outside the layout, by path and the error's name; `Refused.format` writes it as a line (The tool, below) |

Recordings are sorted scenarios first, then by name, then by locale;
refusals by path. The bytes are a function of the root.

**No sidecar and no merge.** Every recording already names its own
locale and viewport, and the step count is the recording's. A file
written beside each recording would be a second statement of facts the
recording holds, and a merge of per-run fragments would be a second
writer of one file. The index is read off the recordings, whole, every
time.

**Read the way the exhibit reads.** A recording is admitted by the
same `read` a raree calls, so a file the index lists is one the exhibit
can show and a refusal is the one it would meet. That includes the
mark rule: a recording whose scenes draw an app's mark is read only by
a nokre whose face holds that mark (stage.md, "What a recording
holds"). The tool must therefore be built over the nokre the exhibit is
built over; nokre's own `zig build exhibit-index` is built over a face
holding no marks, and refuses such a recording by
`RecordedPlayDrawsAnotherAppsMark`.

## The tool

```
zig build exhibit-index -- --app <name> <root>
```

On success it prints `✓ exhibit.json: N recordings, 0 refused` and
exits 0. Each refused file is one `✗ <file> — <words> (<error>)` line
(`Refused.format`): `ExhibitIndex.refusalWords` says what the refusal
means and what cures it — a stale stamp reads "recorded at another
nokre revision or shape; record it again", a cure that names no
consumer's command, since nokre does not know which one recorded the
file — and an error it has no words for is written by its name alone,
`✗ <file> — <error>`, never under a sentence that could be wrong. A
refusal is reported, never fatal: the manifest lists it under
`refused`, the summary is printed under `✗`, and the exit is 0 —
including when every recording was refused, since the page says so
and a consumer that wants a refusal for an empty exhibit makes its
own. The exit is 1 only when the tool could not index, each with its
`✗` line, writing no manifest: a root it cannot open (`✗ cannot open
<root>: <error>`, a missing path or one that is not a directory), a
root holding no `.nokreplay` at all (`✗ no recordings under <root>`,
`error.ExhibitRootHoldsNoRecording`), a walk or read that failed
(`✗ cannot index <root>: <error>`), or a manifest it cannot write
(`✗ cannot write exhibit.json under <root>: <error>`).
`indexRootForTool` is the run and `ToolOutcome` its exit;
`src/exhibit/index_test.zig` pins the exit for each case.

**It is not run per driver run.** Driver runs are separate processes,
often run side by side; each one rewriting a shared index would race,
and the last writer would drop the others' recordings. The index is
written once, over the whole root, by whatever serves it.

## The build half

`addExhibit(b, nokre_dep, .{ .app, .target, .optimize, .plays,
.install_dir, .port, .root_url })` builds the exhibit of one app and
hands back `Exhibit{ app, install, serve }`. It takes the consumer's
builder for `addPlays`' reason: what it installs lands in their prefix,
at `<prefix>/<install_dir>`, which is the root.

**The root's directory.** `.install_dir` defaults to `"exhibit"`, so an
exhibit shares a prefix with the app it shows. `"."` is the prefix
itself: a build that gives each app's exhibit a prefix of its own
(`--prefix build/exhibit/<app>`) would otherwise find its root at
`build/exhibit/<app>/exhibit`, the word doubled and every driver
writing into the nested path. The install, the plays, the index and the
serve all read the one value. It is relative and stays under the
prefix; `addExhibit` refuses an empty path
(`error.InstallDirEmpty`, since `"."` is the one spelling of the
prefix), an absolute one (`error.InstallDirAbsolute`) and one with a
`..` component (`error.InstallDirLeavesPrefix`), by name, when the
build is configured (`index_names.checkInstallDir`).

**A declaration, never sources.** The exhibit is nokre's own app,
`src/exhibit/main.zig`, built by `addAppTo` from a declaration derived
from the exhibited app's. Nothing of the exhibited app is compiled or
imported: its recordings are data, as a stage's are. Each field of the
derived declaration is what it is for one reason:

| Field | Value | Why |
| --- | --- | --- |
| `name` | `<name>-exhibit` | the artifact's name, beside the app's own in one prefix |
| `pkg` | `<pkg.name> exhibit`, `<pkg.id>.exhibit` | the web refuses a site with no identity; and the display name must differ from the app's, since `mark_face.recordedIn` refuses a display name held twice |
| `theme` | the app's | the exhibit opens in the look the app was declared in; the look picker moves it |
| `address_form` | `.fragment` | `nokre-serve` then has no `index.html` fallback, so a missing `exhibit.json` is a 404 and never a page read as a manifest |
| `l10n` | none | the exhibit's chrome is English and its own; a scene's words are the recording's |
| `mark` | none | the exhibit draws no mark of its own; the app's is a scene mark (below) |
| icons | the trees `appIcons` scans for the app, and `src/exhibit` | the scan only subsets glyphs, so the app's trees are read and none of them is compiled |
| services | none, and a local-network purpose (`packaging.Services.local_network_usage`) | on a phone the root is another machine on the network, and iOS asks the person first with this sentence; the `http` service is sockets, so no App Transport Security key rides beside it |

The name, the display name and the id are one on every target: an app
exhibited for the web, this machine and an iPhone in one build is three
exhibits of one derived app, `<pkg.name> exhibit` on the phone's home
screen as in the browser's tab, `<pkg.id>.exhibit` wherever an id is
asked. `addExhibit` refuses, when configured, a second exhibit of one app **for one
target** (the message names the target) and two apps of one name
under two ids.

The app is not required to declare `.pkg` for anything else, but
`addExhibit` refuses one that does not, by name, since the exhibit's
identity is derived from it.

**Scene marks.** A recording whose scenes draw an `app_mark` is read
only by a nokre whose mark face holds that mark under that app's display
name ([stage.md](stage.md), "What a recording holds"). The exhibit's
face is given the app's own mark, as `markOffer` offers it, and the
`offered_mark` of each app in its `.links_into`, through
`DeclaredOpts.scene_marks`: each is a glyph in the face and a member of
`MarkedApp` (`scene_0`, `scene_1`, …), named nowhere in the exhibit's
source and so drawn only inside scenes. The module's face and the
site's `fonts/marks.ttf` are written from one list (`declaredMarks`);
a site written from the exhibit's own mark alone ships no mark face,
and the page draws the app's mark as a missing glyph. A `LinkedApp` per mark was the
alternative and was not taken: it needs a `web_origin` and a link the
exhibit never writes. The derivation reaches `appDeclared`, `appIcons`
and `appServices` through `exhibit_derivations`, keyed by the derived
name and holding every target it was exhibited for, because no
`AppOptions` field may carry it without becoming every consumer's.

**The install.** `Exhibit.install` puts the site (web), the
executable (desktop) or what Xcode takes (iOS), and the plays:

- the site into `<prefix>/<install_dir>` as an **overlay** — not
  `addInstallExactDirectory`, which would prune the `scenarios/` the
  drivers wrote there;
- on iOS, the exhibit's static library (`lib/lib<name>-exhibit.a`),
  the Skia shim (`lib/libnokre_skia.a`) and the `pkg` tree **exactly**
  into `<prefix>/pkg`, as an iOS app's build installs its own (On an
  iPhone, below);
- `.plays`, `Plays.recordings` from `addPlays`, **exactly** into
  `<prefix>/<install_dir>/plays`, so a play the app stopped declaring is gone.

The drivers write `scenarios/` themselves, each run its own process,
with `RecordingSink.write(io, .cwd(), "zig-out/exhibit")` under the
default.

**The serve step.** `Exhibit.serve` depends on the install, runs
`nokre-exhibit-index --app <pkg.name>` over the root, then serves it
with `nokre-serve` on `.port` in the fragment form. The index tool is
built over the exhibit's own `tool_nokre`, so it reads every recording
with the exhibit's mark face (Read the way the exhibit reads, above).
The serve depends on the tool's exit and nothing else, so it fails
only where the tool does (The tool, above); a refused recording is
listed at the foot of the exhibit's page in the tool's own line,
words and error name.

**The root URL.** `.root_url` is baked into the build. Null means the
page's own origin on the web — every fetch is relative, `exhibit.json`
and then each `file` the manifest names — and
`http://127.0.0.1:<port>/` on a native target, which has no origin. A
native exhibit is built the same way and fetches from the serve step.
Since the web fetches only its own origin, the page's `connect-src
'self'` admits it and no CSP is widened
([dom-substrate.md](dom-substrate.md)). Each request takes a
`max_body` of 64 MiB, `nokre-serve`'s own `max_file_bytes`.

**On an iPhone.** nokre ships one Xcode project for every app's
exhibit, `src/exhibit/ios/Exhibit.xcodeproj`, and a consumer never
copies it: it is the kitchen sink's project with everything the
consumer owns turned into a build setting given on the `xcodebuild`
line.

| Setting | Meaning |
| --- | --- |
| `NOKRE_EXHIBIT_PACKAGE_DIR` | the package whose `zig build` installs the exhibit; the script runs there. Required |
| `NOKRE_EXHIBIT_STEP` | the step whose dependency is `Exhibit.install` for the target the script passes (`-Dtarget=aarch64-ios`, or `-simulator`); default `exhibit-ios` |
| `NOKRE_EXHIBIT_PREFIX` | the `-p` the script passes, and where the app target reads `lib/` and `pkg/ios` from; default `$(BUILT_PRODUCTS_DIR)/NokreExhibit` |
| `NOKRE_EXHIBIT_LIB` | the library's name, `<name>-exhibit`. Required |
| `PRODUCT_BUNDLE_IDENTIFIER` | `<pkg.id>.exhibit`; the app target's first phase refuses any other, reading the generated `Info.plist` |
| `NOKRE_ZIG_FLAGS`, `NOKRE_OPTIMIZE` | as in the kitchen sink's project ([getting-started.md](../getting-started.md), Part 13) |
| `DEVELOPMENT_TEAM` | signing is automatic, under the team the line names |

The root URL is baked by the consumer's own build (`.root_url`), so it
reaches the phone as one of the consumer's `-D` options in
`NOKRE_ZIG_FLAGS` and the project carries none. A phone has no
loopback to the Mac: the URL names the Mac as the phone resolves it,
and `Exhibit.serve` cannot answer it, since `nokre-serve` listens on
loopback alone. The
scheme's pre-action runs the same step before signing is planned, so
the entitlements are current, and logs to
`$(BUILT_PRODUCTS_DIR)/exhibit-pre-build.log`. The asset catalog and
privacy manifest are mirrored to `$(BUILT_PRODUCTS_DIR)/NokreExhibitResources`,
since a file reference expands no build setting, and nothing is written
into nokre's checkout. The project compiles `shell.m` and no service
source: the exhibit links none. `NOKRE_RASTER` is the kitchen sink's
override of nokre's own `-Dgpu` and is not carried: the exhibit's raster
derives from the app's theme, as any app's does.

nokre proves it on the kitchen sink: `zig build -Dtarget=aarch64-ios
exhibit-ios` is the step the project names, `zig build
exhibit-ios-smoke` builds and installs it for a device from a host
build and reads the five installed files back, and `zig build test`
holds the install to the library, the shim and the `pkg` tree on the
graph and the derived `Info.plist` to its id and local-network purpose.

**What it shows.** A top bar of three selects: the language (the
locales the manifest's recordings carry — named as text, "Language: en",
when the root holds one language, since a select needs two options —
opening on the exhibited app's template language — its template
catalog's `@@locale`, read when `addExhibit` is configured and handed to the page as
`exhibit_options.template_locale` — where the root holds a recording in
it, else on the first recording's), the look (`eink`, `depth`,
`lamp`, through `setTheme`) and the device: "This window", the
default, then the exhibit's own presets (`src/exhibit/viewports.zig`:
small phone, phone, large phone, tablet, laptop, desktop, each said
with its logical size, "Phone, 390×844"). The presets are not the
store's device families and are not read from the app's `.store`: a
family is a size a listing is uploaded at, and a reader looking at a
run wants a laptop as much as a phone. Nor is the size a run was acted
at offered, since a recording keeps no size a reader defers to. Then,
per scenario recorded in the chosen language, its name and one `raree`
per step at the device's viewport, `.window` for "This window" — the
exhibit's own window, re-laid on every resize, so a card is that window
in miniature and a peep stands it at 1:1 — in one row that wraps them as many to a line as
their cells allow (`layout.metrics.raree_cell_w`: three to a page at its
cap, one to a phone's); then each play on a `stage` on `.data`; then
the refusals. A failed fetch is written in words where its recording
would stand, never a panic.

**Asking again.** A manifest that failed to arrive is said in words
with a "Try again" button under it; recordings that failed are counted
under the bar ("2 recordings could not be fetched.") with the same
button, which asks again for every one that failed and for nothing
that arrived. The same retry runs on its own when the app comes back
in front (`App.setResumeHandler`), and that is the automatic retry
rather than one after a delay, because nokre has no timer (the clock
service's refusals): on an iPhone the first fetch races iOS's
local-network prompt and fails, and answering the prompt is the app
coming back. A recording that arrived and that the raree refuses to
read ("This play could not be loaded.", recorded at another revision
or shape) is not a failed fetch and is not asked for again; the
manifest's refusals say the same of a file the index refused.

**The icon risk, stated rather than closed.** A stage's icons are
checked at the host's build (`render/stage_glyphs.zig`) because its
plays are declared. An exhibit's recordings are fetched, so no build
sees them, and there is no refusal at run time: a recording that draws
an icon the exhibit's face lacks draws a hole where the icon would be.
The face is the app's own scan, so a recording of that app draws what
its sources spell; an icon reached only some other way is the gap.
