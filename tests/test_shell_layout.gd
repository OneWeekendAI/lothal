class_name TestShellLayout
extends RefCounted
## THE ONE SUITE THAT WAITS FOR A LAYOUT PASS.
##
## Every other suite in this project is deliberately synchronous, and `tests/run_tests.gd` renders
## no frames. That is the right default — it keeps the suite fast and it keeps it honest, because a
## check written against a rect that layout has not produced yet passes or fails for reasons that
## have nothing to do with the code (`test_glass_shell.gd` documents the `current_tab` version of
## this, and `test_overlay_tray.gd` the `size == (0, 0)` version).
##
## But there is a class of defect that is INVISIBLE without a layout pass, and this project has now
## shipped two of them in the same room:
##
##   1. "Close blade designer" floated over the top-right corner of the viewport at the height the
##      blade room starts at, sitting on the right-hand end of the room's own toolbar with the
##      pitch spinbox and the rpm slider behind it.
##   2. The repair for (1) reserved a strip above the room to put the button in, and the room does
##      not have 54 px to spare: its content ends 2 px above its own bottom edge at 1280x720. A
##      `Control` does not clip its children, so the shortfall neither scrolled nor squashed — the
##      mount profile and the status line drew through the bottom of the room and under the
##      Lab/Sim/Rooms cluster.
##
## Both are answered by one question — does what the room draws stay inside the room — and that
## question has no answer until a container has run. `Control.get_combined_minimum_size()` returns
## (0, 0) for these containers both inside and outside the tree until a frame has been processed;
## measured, not assumed, before this file was written. A first draft of these checks lived in
## `test_propulsion_room.gd` and asserted against that (0, 0) — it reported "content needs 16 px"
## and could not have failed.
##
## So this suite takes a `SceneTree`, puts a real shell in it, and waits three frames before it
## measures anything. It is the only suite that does, and it should stay that way: a check belongs
## here only if it is about where something ENDED UP on screen.


## Three frames, matching `tests/capture_blade_room.gd`'s own count and for its reason: the first
## places the containers, and the panels inside them do not have their own size until the frame
## after that. Two is enough for the checks below and three costs nothing.
const SETTLE_FRAMES := 3

## The window `project.godot` opens at. Every clearance below is measured against this and only
## this: a room that fits a maximised window and not the default one is a room that is broken for
## every builder's first run.
const WINDOW := Vector2i(1280, 720)


static func run(tree: SceneTree) -> Array:
	var results: Array = []

	# 1280x720 is what `project.godot` opens at, so the shell under test is the shipping window.
	#
	# THE SHELL IS LAID OUT IN A VIEWPORT OF EXACTLY THAT SIZE, and the difference is the whole
	# check. Under `--headless` the dummy display server accepts `window_set_size` and the root
	# viewport keeps whatever size it had — the first version of this suite ran at 1280x1280 and
	# reported comfortable clearances for a window nobody opens. A `SubViewport` of exactly that
	# size is what gives the containers a coordinate space to lay out in that IS the shipping
	# window, with no dependence on what the display server did with the request.
	var frame := SubViewport.new()
	frame.size = WINDOW
	tree.root.add_child(frame)
	var shell := GlassShell.new()
	frame.add_child(shell)
	for i in SETTLE_FRAMES:
		await tree.process_frame

	shell.select_system_by_name("Propulsion")
	shell.set_blade_room_open(true)
	for i in SETTLE_FRAMES:
		await tree.process_frame

	results.append(_content_stays_inside_the_room(shell))
	results.append(_nothing_reaches_the_bottom_cluster(shell))
	results.append(_the_close_button_is_in_the_top_bar(shell))

	# PW5's room, on the same window. Opened after the blade room's checks rather than instead of
	# them, because `set_power_room_open` retracts every other room on its way in — which is itself
	# part of what is being measured.
	shell.set_blade_room_open(false)
	shell.select_system_by_name("Power")
	shell.set_power_room_open(true)
	for i in SETTLE_FRAMES:
		await tree.process_frame

	results.append(_the_power_room_fits_the_window(shell))
	results.append(_the_power_rooms_two_columns_do_not_overlap(shell))

	frame.queue_free()
	return results


## THE ROOM FITS THE WINDOW THE APP OPENS AT — W0.7's rule, applied to the room PW5 adds.
##
## W0.7 laid five Propulsion charts out to 1428 px against a 1280-wide window whose inspector
## started at 904, because a COUNT had been fixed and a WIDTH had never been measured. So this
## measures the width, off the chrome actually on screen: the room's own rect after layout, against
## what its content column asks for.
##
## Both axes, because the same room can fail either — the blade room failed the vertical one two px
## at a time and the frame room failed the horizontal one by 148.
##
## MUTATION CONFIRMED RED: `HarnessInspector.COLUMN_WIDTH` 320 -> 840. **The plan's own figure for
## this row — "widen one column by 200 px" — does NOT turn it red, and that is a fact about the
## room rather than a weakness in the check.** The room is 1256 px wide at 1280x720 and its content
## wants 748, so there are 508 px of genuine slack: at +200 the content wants 948 and fits, which
## it really does. The boundary is at +492, and +520 was the widening confirmed red — content
## wanting 1268 against the 1240 the room's gutters leave.
static func _the_power_room_fits_the_window(shell: GlassShell) -> TestResult:
	var room: Control = shell.power_room()
	var column: Control = null
	for child in room.get_children():
		if child is VBoxContainer:
			column = child as VBoxContainer
			break
	var wanted: Vector2 = column.get_combined_minimum_size() if column != null else Vector2.INF
	# MEASURED AGAINST THE ROOM'S RECT LESS ITS INSETS — never against the column's own rect, and
	# that distinction is a check that could not fail. A `Container` in Godot expands its rect to its
	# combined minimum whatever its anchors say, so `column.get_combined_minimum_size() <=
	# column.get_global_rect().size` is a tautology: the first draft here asserted exactly that and
	# passed a 520 px widening that ran 32 px past the window. The room's rect is set by the SHELL's
	# offsets and does not grow, which is what makes it a bound.
	var have: Vector2 = room.get_global_rect().size - Vector2.ONE * PowerWorkbench.GUTTER * 2.0
	return TestResult.new(
		"the Power room's content fits the window the app opens at (1280x720)",
		column != null and wanted.x <= have.x and wanted.y <= have.y,
		"the room is %.0fx%.0f px, leaving %.0fx%.0f inside its gutters, and its content wants %.0fx%.0f" % [
			room.get_global_rect().size.x, room.get_global_rect().size.y, have.x, have.y,
			wanted.x, wanted.y])


## And the two columns inside it do not meet. The schematic is the subject of the room and the
## inspector is the only way to change what it draws, so an overlap is not a cosmetic fault: it is
## one of the two things a builder came here for, drawn over the other.
##
## Measured off the two panes' global rects rather than off their minimum-size constants, for the
## reason `test_glass_shell.gd`'s own 1280 row gives: those constants are floors, not widths.
static func _the_power_rooms_two_columns_do_not_overlap(shell: GlassShell) -> TestResult:
	var room: PowerWorkbench = shell.power_room()
	var drawing: Rect2 = room.schematic.get_global_rect()
	var inspector: Rect2 = room.inspector.get_global_rect()
	var gap: float = inspector.position.x - drawing.end.x
	# Against the ROOM's rect less its gutters, for the reason above: the body is a Container and its
	# rect grows to whatever its children demand, so measuring against it asserts nothing.
	var body: Rect2 = room.get_global_rect().grow(-PowerWorkbench.GUTTER)
	var inside: bool = drawing.position.x >= body.position.x and inspector.end.x <= body.end.x
	return TestResult.new(
		"the schematic and the inspector share the Power room without overlapping",
		drawing.size.x > 0.0 and gap >= 0.0 and inside,
		"the schematic is %.0f px wide and ends at x=%.0f, the inspector starts at x=%.0f (gap %.0f) and ends at x=%.0f inside a room whose gutter ends at x=%.0f" % [
			drawing.size.x, drawing.end.x, inspector.position.x, gap, inspector.end.x,
			body.end.x])


## Defect 2, stated as the rule it broke: the room's content column must fit in the room.
##
## The column is measured rather than the room's children one by one, because the column IS the
## overflow — a `VBoxContainer` given less height than its children's combined minimum lays them
## out at their minimums anyway and simply runs past its own bottom edge.
static func _content_stays_inside_the_room(shell: GlassShell) -> TestResult:
	var room: Control = shell.blade_room()
	# Child 0 is the opaque backdrop; child 1 is the content column. Fetched by type rather than by
	# index so inserting a second decoration does not silently start measuring the wrong node.
	var column: Control = null
	for child in room.get_children():
		if child is VBoxContainer:
			column = child as VBoxContainer
			break

	var room_bottom: float = room.get_global_rect().end.y
	var column_bottom: float = column.get_global_rect().end.y if column != null else INF
	return TestResult.new(
		"the blade room's content column stays inside the room at 1280x720",
		column != null and column_bottom <= room_bottom,
		"content ends at y=%.0f, the room ends at y=%.0f" % [column_bottom, room_bottom])


## The same defect from the side the screenshot showed it from, and it is NOT a restatement.
##
## The check above would still pass if the room itself were made tall enough to reach the bottom of
## the window — the content would be inside the room, and the room would be over the toggle. What
## the builder actually lost was the Lab/Sim/Rooms cluster and the mount profile's own caption
## fighting for the same fifty pixels, so the cluster is what this measures against.
static func _nothing_reaches_the_bottom_cluster(shell: GlassShell) -> TestResult:
	var room: Control = shell.blade_room()
	var lowest := room.get_global_rect().end.y
	for child in room.get_children():
		if child is Control:
			lowest = maxf(lowest, (child as Control).get_global_rect().end.y)

	var cluster_top: float = shell._bottom_right_glass.get_global_rect().position.y
	return TestResult.new(
		"nothing the blade room draws reaches the Lab/Sim/Rooms cluster",
		lowest <= cluster_top,
		"the room's lowest edge is y=%.0f, the cluster starts at y=%.0f" % [lowest, cluster_top])


## Defect 1. Asserted as a parent rather than as a coordinate: a close button anywhere but the top
## bar is a button carrying hand-written offsets over a room whose height it does not know, which is
## the shape the original bug had. `_room_door` — the way IN to the same room — is in that bar, and
## the two belonging together is the arrangement, not a pair of numbers that happen to agree today.
static func _the_close_button_is_in_the_top_bar(shell: GlassShell) -> TestResult:
	var bar: Control = shell._top_bar
	# Fetched out of the glass rather than off a named member: there are two of these buttons now
	# (PW5 added the harness designer's), they are built by one function, and a member per room is
	# the shape that lets a third room ship without one.
	var button: Button = shell._blade_room_close_glass.get_child(0) as Button
	var in_the_bar: bool = bar != null and button != null and bar.is_ancestor_of(button)
	# And it is on screen, or "in the bar" is satisfied by a button nobody can reach.
	var up: bool = shell._blade_room_close_glass.visible and shell.blade_room().visible
	return TestResult.new(
		"the close button lives in the top bar, and is up while the room is",
		in_the_bar and up,
		"in the top bar: %s; room up %s, button up %s" % [
			in_the_bar, shell.blade_room().visible, shell._blade_room_close_glass.visible])
