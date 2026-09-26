class_name OverlayTray
extends RefCounted
## Which analysis overlays are up, and where they sit — the two decisions P10e's five overlays got
## wrong, extracted from `GlassShell` so they can be checked.
##
## ## Why this file exists rather than five more lines in the shell
##
## Both defects below shipped in a shell that no headless test can build (`GlassShell` wires itself
## in `_ready()`, which needs a tree, a rendered frame and a catalog — `test_glass_shell.gd` says
## so about itself and tests a static function for the same reason). So both were invisible until
## somebody ran the app and looked. The rule that a check must be able to fail cuts the other way
## here: the decisions have to leave the shell before anything can check them.
##
## ## Defect 1 — an overlay stayed up over a room it is not about
##
## Every path that retracts the chrome has to take the overlays with it, and there were three:
## `_on_room_changed` (a bench, Studio, the field, Sim), `set_blade_room_open` (Propulsion's own
## room) and `_select_system` (the Airframe room). The first two called the sync. **The third did
## not**, so choosing Airframe hid the tool cluster — the overlays' own toggle — and left five
## Propulsion charts floating over a frame editor with no way to dismiss them.
##
## Three callers were three chances to forget a term, and one of them took it. So `allowed()` takes
## the whole screen state rather than a bool each caller computes for itself: a fourth retraction
## path cannot omit a term it does not pass.
##
## ## Defect 2 — the cards did not fit the window they were drawn in
##
## The five were placed at fixed absolute offsets, three columns of 360 px starting at the rail:
## the grid's right edge landed at `RAIL_WIDTH + 4·margin + 1080 = 1428 px`. The window ships at
## 1280 wide with a 1024 minimum, and the inspector's left edge sits near `width − 376`. So at the
## shipping size the SECOND column already lay under the inspector and the third was off-screen
## entirely — which is the "a line off the canvas is a warning the builder never gets" failure the
## overlays' own header names, one level up and about the cards instead of the curves.
##
## The header knew: *"Three 360 px charts plus the rail already reach 1380 px; five would run off a
## laptop screen"* — and answered it with a second ROW, which fixes the count and not the width.
##
## So the geometry is computed against a measured band instead. The band is what is left of the
## viewport once the rail, the inspector, the top bar and the tool cluster have taken theirs, and it
## is handed in — this file measures nothing and reads no node, which is what lets a test hand it
## the 1280-wide case that shipped broken.
##
## ## And the honest half: a card that does not fit is not drawn small, it is refused
##
## `capacity()` is what the chooser asks before it lets a fifth chart be ticked. Packing five into a
## band that holds two by shrinking them is the same failure as drawing them off-screen with an
## extra step — a chart too small to read is a chart the builder does not get. The refusal names
## the window, because that is the thing the builder can change.


## The five, in the order they are offered and packed. `id` is what the shell keys its nodes by;
## `title` is what the chooser lists and what the card draws as its own heading, so the tick and the
## chart carry ONE name — a chooser reading "Vibration" over a card reading "What the pad lets
## through" would be two names for one thing in a corner already accused of being a menu.
const ENTRIES := [
	{"id": "thrust", "title": "Thrust along the blade"},
	{"id": "campbell", "title": "Where this airframe rings"},
	{"id": "vibration", "title": "What the pad lets through"},
	{"id": "spin_up", "title": "How fast the motor arrives"},
	{"id": "prop_disc", "title": "What the props sweep"},
]

## What is ticked on a fresh shell, and it is two rather than five or zero.
##
## Zero would make the Overlays button open an empty tray, which is a feature that looks broken on
## first use. Five is what shipped and is what this file exists because of. These two are the pair
## §0 of the design doc rates as clearing its own bar outright — nothing else in Lothal answers
## *where on the blade the lift comes from*, or draws the orders against each other — and they are
## the two the doc says are read together, left to right.
const DEFAULT_CHOSEN := ["thrust", "campbell"]

## What a card wants, and the least it will accept before the tray stops taking cards instead.
##
## The preferred size is P10e's own 360×210, unchanged — the five `_draw()` implementations were
## laid out against it and their axis labels fit it. The minimum is the point at which the shell
## gains a column on a 1280 window; below it the captions collide, which is a judgement about a
## font and is stated as one rather than dressed as a limit.
const CARD_PREFERRED := Vector2(360.0, 210.0)
const CARD_MINIMUM := Vector2(288.0, 176.0)
## Between cards, and between a card and the edge of its band. `GlassShell.CLUSTER_MARGIN`'s value,
## not a reference to it, because this file is deliberately node-free and shell-free.
const CARD_GAP := 12.0


## Whether an overlay may be on screen at all, given everything about the screen that decides it.
##
## Every term is a room in the sense that matters — something covering the viewport the chart floats
## over — and each is passed rather than inferred, so the call site reads as the claim it is making.
##
## `in_lab` is false for Sim, a bench, Studio and the field editor: the chart is about the aircraft
## in the garage, and over a course it would describe a drone that is not the subject of the screen.
## `blade_room_open` is Propulsion's own room, where a chart about the FITTED blade would float over
## the blade being drawn. `system_covers_viewport` is Airframe, whose plan editor takes the whole
## viewport — and it is the term that was missing.
static func allowed(in_lab: bool, blade_room_open: bool, system_covers_viewport: bool) -> bool:
	return in_lab and not blade_room_open and not system_covers_viewport


## How many cards this band can hold at a size worth reading.
##
## Counted at the MINIMUM card size, because that is what `layout` will fall back to — a capacity
## reported at the preferred size would refuse a card the tray could actually have drawn.
static func capacity(band: Rect2) -> int:
	var grid := _grid_for(band, CARD_MINIMUM)
	return int(grid.x) * int(grid.y)


## Where each card goes: `count` rects inside `band`, packed from the bottom-left corner, filling
## the bottom row left to right and then stacking upward.
##
## Bottom-left first because that is where the toggle that summons them is, and upward because the
## bottom of the window is the edge with the tool cluster on it — a tray that grew downward would
## grow into the one piece of chrome that is always there.
##
## Cards take the preferred size when that many fit at it, and the minimum otherwise; they are never
## stretched to fill the band, because five charts sharing one width is easier to compare than five
## charts each sized by how much room was left over.
##
## Clamped to `capacity(band)` rather than returning rects outside the band. The clamp should be
## unreachable — the chooser asks `capacity` before it lets anything be ticked — and it is written
## as a clamp anyway because the alternative to a clamp here is the defect this file is named after.
static func layout(band: Rect2, count: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if count <= 0:
		return out
	var card := CARD_PREFERRED
	var grid := _grid_for(band, card)
	if int(grid.x) * int(grid.y) < count:
		card = CARD_MINIMUM
		grid = _grid_for(band, card)
	var columns := int(grid.x)
	var rows := int(grid.y)
	if columns < 1 or rows < 1:
		return out

	var placed: int = mini(count, columns * rows)
	for index in placed:
		@warning_ignore("integer_division")
		var row := index / columns
		var column := index % columns
		# From the band's bottom edge upward, and its left edge rightward. `band.end.y` rather than
		# a window height, so a tray in a short window sits on the tool cluster and not under it.
		var left := band.position.x + float(column) * (card.x + CARD_GAP)
		var bottom := band.end.y - float(row) * (card.y + CARD_GAP)
		out.append(Rect2(Vector2(left, bottom - card.y), card))
	return out


## Says why a card cannot be ticked, in the terms of the thing the builder can change.
##
## "No room for a sixth chart" would be true and useless. The window is the variable, so the window
## is what the sentence names — and it names the count that DOES fit rather than only refusing,
## because a builder who has been told two fit knows to untick one.
static func refusal(band: Rect2) -> String:
	var fits := capacity(band)
	if fits <= 0:
		return "No room for a chart at this window size — widen the window."
	return "Room for %d chart%s at this window size — untick one, or widen the window." % [
		fits, "" if fits == 1 else "s"]


## Columns and rows of `card` that fit in `band`, gaps included, never negative.
##
## `n` cards of width `w` with `n − 1` gaps need `n·w + (n−1)·g`, so `n = (band + g) / (w + g)`.
static func _grid_for(band: Rect2, card: Vector2) -> Vector2:
	if band.size.x <= 0.0 or band.size.y <= 0.0:
		return Vector2.ZERO
	var columns := floorf((band.size.x + CARD_GAP) / (card.x + CARD_GAP))
	var rows := floorf((band.size.y + CARD_GAP) / (card.y + CARD_GAP))
	return Vector2(maxf(columns, 0.0), maxf(rows, 0.0))


## The title for an id, or "" — used by the shell to keep the chooser's label and the card's own
## heading reading off this one list.
static func title_of(id: String) -> String:
	for entry in ENTRIES:
		if str(entry["id"]) == id:
			return str(entry["title"])
	return ""
