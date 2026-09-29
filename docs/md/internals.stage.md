# The stage, inside

How a recorded play gets from a scenario's run to another app's screen
([elements.md](../elements.md#stage) is what a consumer sees;
[testing.md](../testing.md#and-as-a-play-inside-an-app) is how a play is
recorded and shown).

## The recording

`core/recorded_play.zig` is the format, both halves: the `Writer` the
recorder (`testing/recorder.zig`) fills while a scenario runs, and
`read`. The recorder hears the run on the film sink's seam
(`trace.StepObserver`) and keeps the same timeline the film keeps
(`core/timeline.zig`), so the two decide the same shots; where the film
draws each shot on the app as it stands, the recorder takes the app as
it stands — each scene once, while it is on screen, which is the only
moment it exists.

A scene is the tree — every element whole, in document order, each
distinct element encoded once in a table and a scene being its nodes'
parents and rows — and `SceneState`: the facts outside the tree that
drawing reads. An action is kept as which of its functions were bound,
and comes back bound to a function that does nothing, because drawing
reads `wired()` and nothing else. A node reference (`named_by`, focus,
the emphasized bar) is its ordinal. The window's scroll is the node at
the window's top and how far into it the top stood: the host lays the
scene out with its own width and measurer, where an offset would show
whatever moved to it. Icon names come first after the stamp, so the
build's gathering tool, which links no nokre, can read them.

The codec is generic over the element set, and so is the stamp's
digest (`shapeDigest`): a field added anywhere in `Element`,
`SceneState` or the timeline's types changes it, and a reader refuses
any other stamp. `IconName` and `PlayName` are digested by name alone —
icons travel by name, and a recording holds no stage.

## Standing a scene up

A stage keeps a `Player` per node on the App (`App.staging`): the
recording read once into an arena of its own, freed when the stage
leaves the tree, and a scene app (`App.internal.initScene`) — an
App with no services, no routes and no input — into which
`recorded_play.stand` restores a scene (`Tree.internal.restore`, past
the construction rules, since the tree was one the played app built)
and dresses it in the host's look, appearance, medium and measurer.
The renderer lays it out at the stage's window width and draws it
through the canvas's window pair (`openWindow`/`closeWindow`, a CPU
raster of its own composited pixel for pixel, on a GPU frame too), so
its page ground, lamp and frost know only the window. Marks resolve
against the scene as laid out: a place is a recorded ordinal and
thousandths of that node's box, looked up through the ordinal table the
restore answered, which chrome the host's layout adds (a folded row's
`more`) cannot shift. Every cache here is exact: a scene stands again
when the shot's scene or the width changes, and the resolved points go
with the width.

## Time

Core keeps no clock. `stage.wantsTicks` answers whether a stage plays,
and shell.h's `wants_ticks` / `on_tick` carry the frame clock each shell
already runs its frames and the band's recall on (the pair's comment in
shell.h is the contract); the web runs animation frames while
`nokre_dom_wants_ticks` answers yes. A tick counts film frames at the
timeline's rate, with the remainder carried in thousandths of a frame,
and a late tick counts at most `stage.max_tick_ms`. A frame is owed only
where the shot changed.

## Loading

A player is in one of four phases (`stage.Phase`). Where its recording
is embedded it is read when the stage is first synced, and is loaded or
failed at once. Where it is fetched (`shown_plays.on_demand`), it waits
until layout has given the stage a box, then asks: `stage.takeAsks`
hands the substrate each file under a ticket, and the substrate answers
with `arrive` (the bytes, copied into the player's arena and read there)
or `fail`. An answer under a ticket no stage still holds — the language
changed, or Retry asked again — is dropped. Core fetches nothing itself,
as it keeps no clock.

On the web the live driver takes the asks after each layout and writes
the ticket on the figure (`data-ask`); live.js fetches the file relative
to the module's own URL once an `IntersectionObserver` sees the figure,
and hands the bytes back through `nokre_dom_play_scratch` and
`nokre_dom_play_arrived`, or reports `nokre_dom_play_failed`. A refused
recording is said on the console by name (`nokre_log_refusal`). While a
stage waits its window and its step carry `data-waiting`, and live.js's
patch keeps whatever children the document holds there, so the first
frame over a written page does not wipe the scene the page was written
with; an empty waiting window is the sheet's stand-in.

## The build

`AppOptions.shows` names plays by their recordings and names.
`src/emit_shown_plays.zig` gathers, per play, the recording in each
language the app's catalogs declare as `plays/<digest>.nokreplay` — the
first 64 bits of the bytes' SHA-256 — beside a generated module
(`nokre_shown_plays`, read through `core/shown_plays.zig`) that lists
each by that name with the stamp, the icons and the window its head
states, and embeds its bytes unless the app fetches them (a web app,
`addWebApp`; its site copies the files and lists them in
`site.manifest`). It lists the icons for the icon face's scan too. The
stamp is checked where the library is compiled (`core/stage.zig`) and
again where a fetched recording is read, and the glyphs where the
renderer is (`render/stage_glyphs.zig`). A tool built on
`App.tool_nokre` embeds them on every target: it writes a stage's first
scene into a page at build time.

A recording is made by a runner with no Skia (`recordPlays`), whose app
declares the plays it shows by name alone: the names stand so the app
compiles, and no recording is embedded, since the recordings a stage in
it would show are the ones that run makes. An app may so show its own
plays — the kitchen sink does.
