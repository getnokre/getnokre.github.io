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
executor and a cut calls with `reach.make` ("Cutting a step"), so a
replay's cues and a film's come from the same code.

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

Beside the shots a recording keeps its steps (`recorded_play.Step`),
one per step the player counts, one per run of shots under one
caption: the opening, a said line, or an act, each with the waits
after it under its words. An act's
step is what the scenario named, not how it was reached: the gesture,
the target and a pair's second place as `reach.Target` parts on the
app's own nodes, and a drag's anchor — heard from the director before
its first move (`director.Cue.intent`). Its node is an app ordinal
(`recorded_play.appOrdinal`): document order without the nodes nokre
adds by size or look — the nav's children, a narrow desk's switcher,
every row's More, the rows of `accessibility_toggles` — so it names
one node at every size and in every look. A drag keeps its head
beside its anchor, so its path can be retraced. A step names its
scenes by number: `before`, the scene standing when the intent was
given; `during`, every state the act made in hand, each keystroke
included where the shots show one in two; and `after`, the act's
result then each wait's, with how the router moved to it, read off its
stack. The player plays each step cut again at its own size ("Cutting
a step"); the shots and the scenes a reach passes through stay recorded
for the test that holds a cut equal to them at the acted size.

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
its page ground, lamp and frost know only the window.

What stands is a standing of the current step's cut ("Cutting a
step"): a recorded scene at its recorded anchor, then either as many of
the step's reach moves made on it as the shot has come to, or brought
to the step's target. Marks resolve on the standing the cut made them on —
the shot's own, or for a finger lifting after a swipe the one it
landed on — by the place's ordinal (`place.Place`), which counts
neither another platform's store badge nor the rows
`accessibility_toggles` stands for the look, so a hand on a host in any
look is on the node the cut named. A place on a ranking's stop is
thousandths of that stop's box (`layout.RankingStop`): the ranking lays
its rows and controls out anew at every width, so a hand on a row or a
control stays on it. Every cache here is exact: the cuts are kept per
step under the window's size and the dress, and all cleared, their
arena emptied with its capacity kept, when either changes; the scene
stands again when the step or the standing changes; a resolved point is
kept under the step and the spot, and cleared with the cuts.

## Cutting a step

`core/stage_cut.zig` makes one step's shots again from what the step
named, at any size: its `before` scene stood in the scene app, the
intent rebuilt on it (`appNode` for the target and `then`, the gesture,
the anchor, the caption's words), and `director.show` walked with
`reach.make` as its executor into a timeline started at that scene's
number. The plan made on the scene at this size is the step's reach: a
scroll only where the target stands out of the window, a row's More
only where this layout folds the row, a region's chip only where the
desk hides the target's region. The act itself is never made: a typed
run's keystrokes are one `between` per `during` scene, a drag's hand is
retraced across its `during` scenes from the anchor's caret to the
head's in even shares, as the driver moved it, and each result is one
`step` onto its recorded scene. What a cut shot draws is a `Standing`:
a recorded scene and how many of the step's moves are made on it, each
slice of a scroll one, which only the step's `before` has; or a scene
the act made in hand or came to, aimed: brought to the step's target by
the reveal the driver acts after, where it still holds that target on
the same route (`stage_cut.Standing` has the rule), so a window a reach
scrolled does not jump back as the result appears. Standing one walks
the same moves again, so with the step, the size and the dress it is
the whole key of what stands, and a cache under it is exact.

A step whose target the plan refuses on its scene is shown unreached
(`Cutter.unreached`): its words over its `before` scene, then each
result, with no hand — what a reader under Reduce Motion is shown of
any step. It is never shown as the recording's own moves, which would
be a second way to show one step. Two kinds of step take it today: a
nav's destination, which a scene's empty roster refuses, and, on a desk
acted wide and shown narrow, a target in a region the scene holds no
switcher for.

At the size a play was acted at, a cut is held equal to the step's
recorded shots (`testing/stage_cut_test.zig`, every fixture play): the
same shots, frames, captions and marks, and each shot's standing the
recorded scene's tree and state, byte for byte as a recording encodes
them, and the window's offset. Where a scene holds a picture the
played app's points (`Place.pt`) are set aside, since a recorded
picture stands as its box (`layout.pictureRecordedSize`); a stage never
draws at them. Two kinds of step are named there as differing: a nav
destination, which a scene's empty roster refuses, and a scroll on a
page a recorded store badge's box makes longer.

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

Where a stage stands is a step, the recording's, and a shot inside
that step's cut, or none for the step's rest, its cut's last shot
(`Stage.played`). The count is one per step, the same at every size.
Previous and Next stop on rests; Next mid-step finishes the step. Play
runs through a step's shots and into the next step's, cut as it is
entered. A stage at rest, a page written at build time included, shows
its step's rest with no tick: the first step's, cut when it is first
drawn. A shot index means nothing in a cut made at another size or in
another dress, so when the window changes — the big screen opening or
closing, a reflow — or the dress does, a stage at rest or paused stands
on its step's rest at the new size, and a playing one plays its step
again from the first shot.

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
