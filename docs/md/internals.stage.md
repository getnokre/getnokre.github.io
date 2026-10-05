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

What the film and the recorder hear of a reach — the scrolls in
slices, each hand and where it lands — is told by one routine,
`core/director.zig`, which the driver calls with real input as its
executor. A stage's player is meant to call it with `reach.make` to
generate a step's shots at its own size, so a replay's cues and a
film's come from the same code.

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
any other stamp. `IconName`, `PlayName` and `PictureName` are digested
by name alone — icons travel by name, a recording holds no stage, and a
picture travels as its description, destination and own size, stood up
with `Picture.held.recorded` set so it draws its box.

## Standing a scene up

A stage keeps a `Player` per node on the App (`App.staging`): the
recording read once into an arena of its own, freed when the stage
leaves the tree, and a scene app (`App.internal.initScene`) — an
App with no services, no routes and no input — into which
`recorded_play.stand` restores a scene (`Tree.internal.restore`, past
the construction rules, since the tree was one the played app built)
and dresses it in the host's look, appearance, medium and measurer.
A stand leaves the scene app holding that scene and nothing else:
each App field is declared stood from the recording, dropped, or kept
as the scene app's own (`recorded_play.on_stand`, a field left out is a
compile error), so a More sheet or picker a made move opened on the
last scene goes with its tree, while a picker the scene itself holds
stands with its recorded owner.
The renderer lays it out at the stage's window size, width and height
both, and draws it
through the canvas's window pair (`openWindow`/`closeWindow`, a CPU
raster of its own composited pixel for pixel, on a GPU frame too), so
its page ground, lamp and frost know only the window. Marks resolve
against the scene as laid out: a place is a recorded ordinal and
thousandths of that node's box, looked up through the ordinal table the
restore answered, which chrome the host's layout adds (a folded row's
`more`) cannot shift. On a ranking a place also names the stop the hand
was on (`layout.RankingStop`), and its thousandths are of that stop's
box: the ranking lays its rows and controls out anew at every width,
so a hand on a row or a control stays on it, and a stop the scene does
not stand resolves to nothing. The window's anchor alone can leave the place a
hand is about to act on outside a window shorter or narrower than the
recording's, so a shot whose mark is on a node of the scene it draws
stands that scene brought to it, by the scroll the driver made before
the act (`input.actRevealWalk`, innermost region first, on a ranking
the place's stop): where the play was recorded that scroll is
already made and nothing moves. The bar the recording emphasized stays
the one drawn. A step is a run of shots saying one caption, and may
put a hand down more than once: a folded action's More, then the action
on the sheet it opened, or a region's chip, then the target in the
region it showed (`timeline.Timeline.follow`), each hand on its own
scene and the second doing whatever gesture the act's would — a long
press, a pair, a drag whose every slice is a hand on the field, or a
scroll. A step stands on its first target from its first shot to its
rest (`stage.aimsOf`, read once beside the rests): a shot with no mark
on a node — none, or a swipe on the glass — borrows the next marked
shot's target in its step, else the last one's. A later hand's scene
stands carried from the first target, as a rest is below, then brought
to its own target — each row of a pair to its own stop, each slice of
a drag to the field — and the shots after it carry from the first target
alone: the page under the sheet stays where the first hand left it. A scroll that follows
a press stands every shot from its lead to the rest as a scroll step's
does, its swipes included, which are on a region it moves or on the
glass. A step with no hand on
a node, a scroll to one, stands on the place its scroll's beat keeps
(`timeline.Beat.at`): the driver tells a scroll's act after its
slices, so that place is on the scene the last slice left. On the
target's own scene the place is brought in. On another,
usually the rest after the act, no place is resolved again, since a
place is thousandths of a box the act may have grown: the scene stands
at its own anchor, with the played app's own scroll in it, and is
scrolled on by as much as the stage scrolled the target's scene to
bring the place in, so nothing jumps as the result appears. That
carry needs both scenes on one route and the target's ordinal naming
an element of one kind on both; otherwise the anchor alone. A spot on
another scene — a finger lifting from the screen it landed on — is
resolved on that scene brought to it the same way, which is how it was
drawn when it landed. Every cache here is exact: a scene stands again
when the shot's scene, its aim (the target's scene and place among
it), the width, the height or the look changes, and a resolved point is kept
under the scene as it stood, at the size.

## The big screen

A stage on the big screen is the same node, never moved or copied:
`Stage.played.big` is set by `stage.openBig` and cleared by
`stage.closeBig`, and the play, its player and its controls are the
ones it has in the page. Its one node has two boxes: the page keeps the
stage's slot at its page height, so nothing beside it moves, and the
layer stands over the whole screen. The screen is the viewport, or
`App.staging.screen` where a substrate's viewport is narrower than the
reader's window (`layout.AppFacts.stage_screen`): the web's, whose
viewport is the page's column ([dom-substrate.md](dom-substrate.md#a-stage-on-the-big-screen)
has how the browser presents it).
`layout.bigStageGeometry` is the rule: the stage's rect is the screen;
the frame stands the page's padding in from its edges and the window
is as wide as that leaves; the controls stand under the frame from the
window's leading edge and end the padding above `safe_bottom`; the
window takes the height left, with no floor, since a pane cannot
scroll, so a screen too short for it has a window of nothing and no
scene stands. These are screen points, written by the last pass of
layout (`placeBigStage`) after the page, its rows, a desk's regions
and the sheet have placed everything, and the window's shift passes
over them. Its role stays content, so a big
stage is a modal layer by state, not by role: `layout.topModalLayer`
ranks it under the sheet — over it when the stage stands in that
sheet, so Esc closes the big screen first — and over the notices
pane. Everything that takes the layer from there — the focus scope,
Esc, a press outside it, the root scroll's and the edge Back's gates,
the driver's reachable walk, the audit's jurisdiction — learned the big
stage by that one change. What sorts the page from what floats over it
by role does not, so each such place asks `layout.inBigStage` (or
`bigStage`) beside `Role.isChromeLayer`: hit clipping
(`input.clippedRect`), the screen column's cut and the window's reveal
(`input.inChrome`), the reveal walk (`input.RevealWalk.next`), the
window's shift (`App.shiftWindow`) and the renderer's page pass. A new
place that partitions by role asks too, or a big stage is page there.
The notices pane does not expand while a stage is big
(`notices.openNoticesPane`): it ranks under it, and a substrate that
paints chrome last would stand it over it. It has no scrim: a press
beside it does nothing, and Esc or its control closes it. Closing reveals nothing, so the page
beneath stands where it stood. A rebuild makes the node again at
rest, so a navigation or a reload takes a stage off the big screen by
itself.

The renderer draws it as a layer in `topModalLayer`'s order
(`renderer.drawBigStage`): the page's pass skips the stage, leaving
its slot empty, and after the bar, the banner and the notices pane the
pane is filled with the page's own ground through `safe_bottom` and
`drawStage` draws the stage on it, the one drawing a stage has, at its
screen boxes and under none of the page's clips; a sheet and a picker
follow, unless the stage stands in that sheet. Under lamp dark the
pane's plates take only the edges of the layers drawn over it
(`LampFrame.over_big_screen`), never the bar's or the banner's, which
it covers.

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
stage waits its window and its words carry `data-waiting`, and live.js's
patch keeps whatever children the document holds there, so the first
frame over a written page does not wipe the scene the page was written
with; an empty waiting window is the sheet's stand-in.

## The build

`AppOptions.shows` names plays by their recordings and names.
`src/emit_shown_plays.zig` gathers, per play, the recording in each
language the app's catalogs declare as `plays/<digest>.nokreplay` — the
first 64 bits of the bytes' SHA-256 — beside a generated module
(`nokre_shown_plays`, read through `core/shown_plays.zig`) that lists
each by that name with the stamp and the icons its head states, and
embeds its bytes unless the app fetches them (a web app,
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
