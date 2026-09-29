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
recording read once, and a scene app (`App.internal.initScene`) — an
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

## The build

`AppOptions.shows` names plays by their recordings and names.
`src/emit_shown_plays.zig` gathers, per play, the recording in each
language the app's catalogs declare into a directory beside a generated
module (`nokre_shown_plays`, read through `core/shown_plays.zig`), and
lists their icons for the icon face's scan. The stamp is checked where
the library is compiled (`core/stage.zig`), and the glyphs where the
renderer is (`render/stage_glyphs.zig`).

A recording is made by a runner with no Skia (`recordPlays`), whose app
declares the plays it shows by name alone: the names stand so the app
compiles, and no recording is embedded, since the recordings a stage in
it would show are the ones that run makes. An app may so show its own
plays — the kitchen sink does.
