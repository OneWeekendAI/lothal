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
	results.append(_nothing_reaches_the_dock(shell))
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
	results.append(_the_power_rooms_three_columns_do_not_overlap(shell))

	# QC3'S ROOM, WHICH IS THE WHOLE WINDOW. Every room is closed first and a system with both
	# columns up is chosen, because the dock's two neighbours are the inspector and the overlay
	# tray's band — and a room being open hides the inspector, which would make the clearance check
	# below pass against a panel that was not on screen.
	shell.set_power_room_open(false)
	shell.select_system_by_name("Propulsion")
	for i in SETTLE_FRAMES:
		await tree.process_frame

	var settled: Rect2 = shell._dock.get_global_rect()
	results.append(_the_dock_fits_the_shipping_window(shell))
	results.append(_the_dock_clears_the_inspector(shell))
	results.append(_the_dock_leaves_the_overlay_trays_band_alone(shell))

	# AND THE LONGEST THING THE DOCK CAN BE ASKED TO SAY. Not a hypothetical: `_on_mount_stl_requested`
	# writes `"Wrote %s"` with an absolute globalized path into this same label, so the length of a
	# builder's home directory is an input to the width of a centred control.
	shell._status_label.text = "Wrote /Users/%s/exports/mount.stl" % "d".repeat(4000)
	for i in SETTLE_FRAMES:
		await tree.process_frame
	results.append(_the_status_readout_cannot_widen_the_dock(shell, settled))

	# -----------------------------------------------------------------------
	# QC4 — the inspector gates on selection, and the finder is wired to the build.
	#
	# Here rather than in a suite of its own for the reason this file's header gives: every rule
	# below is about what ENDED UP on screen. Whether a panel is present, whether a sheet of dim
	# is over it and whether a preview reached the aircraft are all questions with no answer until
	# a container has run, and `tests/run_tests.gd` processes no frames anywhere else.
	#
	# The status label is left holding 4000 characters by the check above; `select_system_by_name`
	# re-runs `_refresh_status` on its way through, which puts it back.
	# -----------------------------------------------------------------------
	shell.select_system_by_name("Propulsion")
	for i in SETTLE_FRAMES:
		await tree.process_frame

	var propulsion := _index_of("Propulsion")
	var rail: PartPicker = shell._rail_for_system(propulsion)
	# What the aircraft is wearing BEFORE the finder is summoned, which is the record Escape has to
	# put back. Read off the rail rather than off the finder, because the finder does not exist yet
	# — a snapshot taken from the object under test would agree with it whatever it did.
	var fitted_at_open := str(rail.selected_part().get("part_id", "")) if rail != null else ""

	results.append(_the_inspector_is_present_with_something_selected(shell))
	results.append(_the_inspector_is_no_wider_than_qc4_measured(shell))

	# THE CLICK, driven through the dock's own signal. Calling `open_finder` here would prove the
	# function works and say nothing about whether any icon reaches it — which is the half of this
	# slice that QC1 and QC2 deliberately left undone.
	shell._dock.system_chosen.emit(propulsion)
	for i in SETTLE_FRAMES:
		await tree.process_frame

	results.append(_the_dock_icon_opens_the_finder_on_its_own_system(shell))

	# -----------------------------------------------------------------------
	# QC5 — the rail is retired, and NOTHING IT OFFERED WENT WITH IT.
	#
	# The risk in this slice is silent capability loss, so every one of these asserts BY NAME
	# against the live rail's own surface rather than against a literal. A shelf, a facet or an
	# authoring button that stops being drawn takes one of these red with the missing word printed.
	# -----------------------------------------------------------------------
	results.append(_the_rail_column_is_off_the_screen(shell))
	results.append(_the_viewport_got_the_rails_space(shell))
	results.append(_the_finder_carries_every_facet_the_rail_filtered_by(shell, rail))
	results.append(_the_finder_reaches_every_shelf_the_system_owns(shell, propulsion))
	results.append(_the_custom_part_actions_came_off_the_rail_with_it(shell, rail))
	results.append(_the_finder_opens_on_the_part_the_build_is_wearing(shell, fitted_at_open))
	results.append(_the_canvas_is_dimmed_and_the_inspector_is_not(shell))
	results.append(_the_finder_is_a_real_panel_and_not_a_sliver(shell))
	results.append(_the_finder_fits_the_window_and_clears_the_dock(shell))

	# THREE PREVIEWS AND THEN ESCAPE. Three and not one, for the reason
	# `tests/test_part_finder.gd`'s header gives: with a single preview, "restore the original" and
	# "restore the last thing previewed" are the same value, so a one-preview check passes against
	# the implementation nearest to hand.
	var finder: PartFinder = shell.finder()
	finder.move_highlight(1)
	finder.move_highlight(1)
	finder.move_highlight(1)
	for i in SETTLE_FRAMES:
		await tree.process_frame
	# Read BEFORE the escape: this is the evidence that the previews reached the real aircraft at
	# all, and without it the restore check below is satisfied by an adapter that does nothing.
	var after_previews := str(rail.selected_part().get("part_id", "")) if rail != null else ""
	results.append(_previewing_fits_the_part_on_the_real_build(fitted_at_open, after_previews))

	shell.close_finder()
	for i in SETTLE_FRAMES:
		await tree.process_frame
	results.append(_escape_restores_the_original_after_several_previews(
		shell, rail, fitted_at_open, after_previews))
	results.append(_escape_takes_the_overlay_and_the_dim_down_together(shell))

	# QC5: THE ROWS BELOW THE FOLD. The motor shelf has 18 entries and about 13 rows of room, and
	# the finder is re-summoned here rather than reusing the one above because the escape check
	# closed it. Arrowed 30 times, which clamps at the last row (§4.1, "clamps at both ends").
	shell._dock.system_chosen.emit(propulsion)
	for i in SETTLE_FRAMES:
		await tree.process_frame
	for i in 30:
		shell.finder().move_highlight(1)
	for i in SETTLE_FRAMES:
		await tree.process_frame
	results.append(_the_last_row_is_reachable(shell))
	results.append(_the_list_has_a_scroll_affordance_you_can_see(shell))
	shell.close_finder()
	for i in SETTLE_FRAMES:
		await tree.process_frame

	# AND THE STATE THE WHOLE SLICE EXISTS FOR. Asserted last because it is destructive: nothing
	# after this point has a focused system.
	var present_before := shell._inspector.visible
	shell.clear_selection()
	for i in SETTLE_FRAMES:
		await tree.process_frame
	results.append(_the_inspector_is_absent_with_nothing_selected(shell, present_before))

	frame.queue_free()
	return results


## QC5's headline, and the one line that is the slice: the column Quiet Canvas exists to remove is
## not on screen for a system the finder covers.
##
## `lab.rails()` is asserted as well as the glass around it, because hiding the frame and leaving
## the content inside it visible is a real way to get this half-right — the pickers are deliberately
## kept ALIVE in the tree as the model behind the finder, so "it still exists" is true by design
## and cannot be the thing being checked.
##
## MUTATION CONFIRMED RED: `_select_system`'s `_rail_glass.visible = modelled and not
## column_titles.is_empty()` restored to `has_rails or not modelled`.
static func _the_rail_column_is_off_the_screen(shell: GlassShell) -> TestResult:
	return TestResult.new(
		"with Propulsion focused the parts rail is off the screen, glass and content both",
		not shell._rail_glass.visible and not shell.lab.rails().visible,
		"the rail glass is visible=%s and Lab's rail column visible=%s" % [
			shell._rail_glass.visible, shell.lab.rails().visible])


## AND THE SPACE WENT TO THE DRONE. §1's claim is a measurement — the viewport goes from 46% of the
## window to about 78% — so this is a measurement and not a relation.
##
## Measured on the overlay tray's band, which is the shell's own answer to "what is left of the
## window once the chrome has taken its share" and is computed from the nodes on screen rather than
## from the constants. The number below is what it MEASURED at 1280x720 after the rail came down,
## recorded here rather than recomputed, for `_the_dock_leaves_the_overlay_trays_band_alone`'s
## reason: a bound derived from the same constants the shell derives the band from would agree with
## itself whatever either said.
##
## MUTATION CONFIRMED RED: as above — restore `_rail_glass.visible = has_rails or not modelled` and
## the band loses the rail's width, dropping to 538 px.
static func _the_viewport_got_the_rails_space(shell: GlassShell) -> TestResult:
	var band: Rect2 = shell._overlay_band()
	var fraction := band.size.x / float(WINDOW.x)
	return TestResult.new(
		"the space the rail held went to the canvas — the band is at least 850 px wide at 1280",
		band.size.x >= 850.0,
		"the band is %.0f px wide, %.0f%% of a %d px window" % [
			band.size.x, fraction * 100.0, WINDOW.x])


## THE THREE FACETS. The rail carried three dropdowns — Stator, KV and For — derived from the JSON,
## and §4 says they become chips in the finder's header. This compares the chips ACTUALLY DRAWN
## against the live rail's own `filter_keys`, so a facet dropped in the move is named in the
## failure rather than merely missing.
##
## `facet_labels()` reads the grid on screen and not `filter_keys`, which is what stops this being
## a helper that agrees with itself — see its own header.
##
## MUTATION CONFIRMED RED: delete `_facet_grid.add_child(label)` from `PartFinder._init` — the
## finder draws three dropdowns with nothing naming them and this reports `missing [Stator, KV,
## For]`.
static func _the_finder_carries_every_facet_the_rail_filtered_by(
		shell: GlassShell, rail: PartPicker) -> TestResult:
	var drawn: PackedStringArray = shell.finder().facet_labels()
	var missing: Array = []
	for entry in rail.filter_keys:
		if not drawn.has(str(entry["label"])):
			missing.append(str(entry["label"]))
	return TestResult.new(
		"every facet the rail filtered by is a named chip in the finder",
		missing.is_empty() and drawn.size() == rail.filter_keys.size(),
		"the rail filtered by %d facet(s), the finder draws %s, missing %s" % [
			rail.filter_keys.size(), drawn, missing])


## EVERY SHELF, NOT JUST THE FIRST. This is the capability the retirement was most likely to eat
## without anyone noticing: the rail column showed Motor AND Prop as tabs, `open_finder` opens on
## `rails[0]`, and every other check in this file opens on the first shelf — so a finder that could
## only ever reach Motor would have been green everywhere while propellers, ESCs and receivers left
## the app.
##
## Compared against `SYSTEMS[index]["rails"]` by name, which is the list the rail column was built
## from, rather than against a literal `["Motor", "Prop"]`.
##
## MUTATION CONFIRMED RED: `_finder_categories`'s loop `for i in titles.size()` narrowed to
## `for i in 1` — the header draws one segment and this reports `missing [Prop]`.
static func _the_finder_reaches_every_shelf_the_system_owns(
		shell: GlassShell, index: int) -> TestResult:
	var drawn: PackedStringArray = shell.finder().category_labels()
	var missing: Array = []
	for title in GlassShell.SYSTEMS[index].get("rails", []):
		if not drawn.has(str(title)):
			missing.append(str(title))
	return TestResult.new(
		"the finder's header reaches every shelf the focused system owns, by name",
		missing.is_empty(),
		"%s owns %s, the finder offers %s, missing %s" % [
			GlassShell.SYSTEMS[index]["name"], GlassShell.SYSTEMS[index].get("rails", []),
			drawn, missing])


## THE AUTHORING PATH, WHICH IS THE ONE NOBODY WOULD HAVE MISSED UNTIL THEY NEEDED IT.
##
## `New custom motor…` and `Delete` sat under the rail's list and nothing else in the app mentions
## them: no menu entry, no keystroke, no second screen. A layout slice that removed the column
## would have removed the only way to write or delete a custom part, and every existing check —
## including `tests/test_custom_parts_ui.gd`, which drives the picker directly — would have stayed
## green, because the picker still works. What stopped working is reaching it.
##
## Asserted against the RAIL'S OWN BUTTONS, by their text, rather than against the two strings: the
## words come off the picker in `open_finder` precisely so there is one spelling of them, and a
## check that hardcoded "New custom motor…" would pass a finder whose button said something else.
##
## MUTATION CONFIRMED RED: delete the `_delete_button` half of `PartFinder.set_actions` — the
## finder draws one button and this reports `missing [Delete]`.
static func _the_custom_part_actions_came_off_the_rail_with_it(
		shell: GlassShell, rail: PartPicker) -> TestResult:
	var offered: PackedStringArray = shell.finder().action_labels()
	var expected := PackedStringArray()
	for button in GlassShell._rail_action_buttons(rail):
		expected.append((button as Button).text)
	var missing: Array = []
	for text in expected:
		if not offered.has(text):
			missing.append(text)
	return TestResult.new(
		"every authoring action the rail offered is in the finder, by name",
		missing.is_empty() and expected.size() == 2,
		"the rail offered %s, the finder offers %s, missing %s" % [
			expected, offered, missing])


## THE EIGHTEENTH MOTOR. `ItemList.select()` moves the selection and leaves the viewport alone, so
## arrowing past the last visible row previewed motors on the aircraft with no row lit anywhere on
## screen — the model changing under a list that appeared to have stopped.
##
## The count is asserted as well as the position, and that is what stops this passing for the wrong
## reason: "the highlighted row is in view" is trivially true of a list short enough to fit, and
## would stay green if the catalog shrank to ten motors or if the list stopped filtering at all.
##
## MUTATION CONFIRMED RED: delete `_list.ensure_current_is_visible()` from `PartFinder._select_row`
## — the highlight lands on row 17 while the viewport is still showing rows 0 to 12.
static func _the_last_row_is_reachable(shell: GlassShell) -> TestResult:
	var finder: PartFinder = shell.finder()
	var rows: int = finder.row_count()
	var highlight: int = finder.highlighted_index()
	return TestResult.new(
		"arrowing to the end of a shelf longer than the list scrolls the highlight into view",
		rows > 13 and highlight == rows - 1 and finder.highlighted_row_is_in_view(),
		"the shelf has %d rows, the highlight is on %d, in view %s" % [
			rows, highlight, finder.highlighted_row_is_in_view()])


## AND A BUILDER WHO IS NOT USING THE ARROW KEYS CAN SEE THAT THERE IS MORE.
##
## `LothalTheme` styles a scrollbar as a translucent grabber over an empty track, and neither
## stylebox carries a content margin — so every `VScrollBar` in this app reports a minimum width of
## ZERO. It tracks, the wheel moves it, and it paints nothing: the screenshot that prompted this
## check showed a list of 18 motors that stopped at 13 with no indication that it had.
##
## Asserted on the WIDTH and not on `visible`, because `visible` was already true the whole time.
##
## MUTATION CONFIRMED RED: delete the `get_v_scroll_bar().custom_minimum_size.x = 8.0` line from
## `PartFinder._init` — the width goes to 0 and the bar is invisible again.
static func _the_list_has_a_scroll_affordance_you_can_see(shell: GlassShell) -> TestResult:
	var width: float = shell.finder().scrollbar_width()
	return TestResult.new(
		"the finder's list draws a scrollbar wide enough to see and to grab",
		width >= 4.0,
		"the list's scrollbar is %.0f px wide" % width)


## The index of a system by name, so no check below carries a literal 2 that a tenth system
## inserted above Propulsion would quietly repoint.
static func _index_of(system_name: String) -> int:
	for i in GlassShell.SYSTEMS.size():
		if str(GlassShell.SYSTEMS[i]["name"]) == system_name:
			return i
	return -1


## THE DOCK FITS THE WINDOW THE APP OPENS AT. QC3's own "done when", measured.
##
## Both edges and both axes. A centred control that is too wide does not clip — it hangs off BOTH
## sides equally, so the systems at one end and Sim at the other go off-screen together and the
## middle of the row still looks perfectly fine in a screenshot.
##
## Measured off the global rect after layout rather than off `get_combined_minimum_size()`, for the
## reason the Power room's row gives about constants: the minimum is what the row asked for and the
## rect is what it got, and `layout_in` clamps between the two.
##
## MUTATION CONFIRMED RED: `Dock.STATUS_WIDTH` 232 -> 900. The dock runs x=-64 to x=1344 against a
## 1280 window — off both edges, exactly as described.
static func _the_dock_fits_the_shipping_window(shell: GlassShell) -> TestResult:
	var dock: Rect2 = shell._dock.get_global_rect()
	var window := Vector2(WINDOW)
	var inside: bool = dock.position.x >= 0.0 and dock.end.x <= window.x \
		and dock.position.y >= 0.0 and dock.end.y <= window.y
	# And it is a real control, not a collapsed one. Without this the check is satisfied by a dock
	# of zero size, which is what a `visible = false` regression or a failed build would produce —
	# and "it fits" would be the line reporting the dock had vanished.
	var real: bool = dock.size.x > 200.0 and dock.size.y > 20.0
	return TestResult.new(
		"the dock fits the window the app opens at (1280x720)",
		inside and real,
		"the dock is %.0fx%.0f px, running x=%.0f to x=%.0f and y=%.0f to y=%.0f" % [
			dock.size.x, dock.size.y, dock.position.x, dock.end.x, dock.position.y, dock.end.y])


## THE DOCK AND THE INSPECTOR DO NOT MEET.
##
## This is the collision the old arrangement could not have: the bottom-right cluster was anchored
## to the right edge under a panel that stopped at `BOTTOM_KEEPOUT`, so the two could not reach each
## other whatever either one measured. A CENTRED dock grows sideways from the middle, and the
## inspector is measured to its content and grows leftwards from the edge — two controls sized by
## two different strings, moving towards each other.
##
## The inspector's visibility is asserted as well, because an overlap check against a hidden panel
## is the cheapest test-that-cannot-fail in this file: `get_global_rect()` still returns a rect for
## a hidden Control, and it is the rect it would occupy.
##
## MUTATION CONFIRMED RED: `GlassShell.BOTTOM_KEEPOUT` 76 -> 30, which lifts the inspector's bottom
## edge to y=690 and drops the dock's top to y=678 — they overlap by 12 px over the dock's whole
## right-hand end.
static func _the_dock_clears_the_inspector(shell: GlassShell) -> TestResult:
	var dock: Rect2 = shell._dock.get_global_rect()
	var inspector: Rect2 = shell._inspector.get_global_rect()
	var overlap: Rect2 = dock.intersection(inspector)
	return TestResult.new(
		"the dock and the inspector do not overlap",
		shell._inspector.visible and overlap.size.x <= 0.0 and overlap.size.y <= 0.0,
		"the dock runs x=%.0f-%.0f y=%.0f-%.0f, the inspector x=%.0f-%.0f y=%.0f-%.0f (visible %s), overlap %.0fx%.0f" % [
			dock.position.x, dock.end.x, dock.position.y, dock.end.y,
			inspector.position.x, inspector.end.x, inspector.position.y, inspector.end.y,
			shell._inspector.visible, overlap.size.x, overlap.size.y])


## THE OVERLAY TRAY'S BAND SURVIVED THE DOCK, AND IT IS STILL A BAND.
##
## W0.7's whole fix was that the tray measures its band off the chrome actually on screen, so a
## slice that moves chrome has to answer to it. The danger in writing this check is the one the task
## names: "the dock does not overlap the band" is ALSO satisfied by a band that has shrunk to
## nothing, and a tray measuring zero passes every non-overlap assertion ever written against it.
##
## So this asserts three things and the last two are the teeth:
##
##   1. the band's bottom edge stops at or above the dock's top edge — the non-overlap;
##   2. the band is **580 px tall and 866 px wide** at 1280x720, which is a NUMBER and not a
##      relation, and is what it measured before this slice touched anything — `_overlay_band()` is
##      a function of the rail, the inspector, `TOP_BAR_HEIGHT` and `BOTTOM_KEEPOUT`, and QC3
##      changed none of the four;
##   3. `OverlayTray.capacity` still returns at least `DEFAULT_CHOSEN.size()` — the tray can still
##      draw what a fresh shell ticks. A band that collapsed would fail (2) and (3) together while
##      passing (1) with room to spare.
##
## The floor in (2) is a floor rather than an equality because the inspector is measured to its
## content and a wider panel would legitimately narrow the band. What must not happen is it getting
## SMALLER than the band the tray was designed against.
##
## RE-MEASURED AT QC5 AND IT GREW: **538 -> 866 px wide**, 580 tall, and 6 cards fit where 3 did.
## That is not drift, it is the slice — QC5 takes the parts rail off the screen, and `_overlay_band`
## measures its left edge from the chrome actually standing, so the 328 px the column held went to
## the band the moment it came down. The width here is the number that was MEASURED after the
## change, recorded rather than derived: a bound computed from the same constants the shell
## computes the band from would agree with itself whatever either said.
##
## The 538 still had teeth when it was written — QC4 ran `INSPECTOR_WIDTH` up to 520 and this line
## went red at a 380 px band — and 866 keeps them for the same reason.
##
## MUTATION CONFIRMED RED: give the dock its own content-sized top edge —
## `Dock.layout_in`'s `offset_top = -(keepout - margin)` replaced by
## `offset_top = -maxf(keepout - margin, wanted.y + 120.0)`. The dock's top rises to y=518 while the
## band still ends at y=644, and clause (1) fails by 126 px.
static func _the_dock_leaves_the_overlay_trays_band_alone(shell: GlassShell) -> TestResult:
	var band: Rect2 = shell._overlay_band()
	var dock: Rect2 = shell._dock.get_global_rect()
	var fits: int = OverlayTray.capacity(band)
	var clears: bool = band.end.y <= dock.position.y
	# The numbers this project shipped W0.7 against. Named here rather than recomputed from the
	# constants, because a band derived from the same constants the shell derives it from would
	# agree with itself no matter what either said.
	var tall_enough: bool = band.size.y >= 580.0 and band.size.x >= 866.0
	return TestResult.new(
		"the overlay tray's band is untouched by the dock, and still holds what a fresh shell ticks",
		clears and tall_enough and fits >= OverlayTray.DEFAULT_CHOSEN.size(),
		"the band is %.0fx%.0f px ending at y=%.0f, the dock starts at y=%.0f, and %d card(s) fit against %d ticked" % [
			band.size.x, band.size.y, band.end.y, dock.position.y, fits,
			OverlayTray.DEFAULT_CHOSEN.size()])


## A STATUS READOUT CANNOT PUSH LAB AND SIM OFF THE SCREEN.
##
## The readout is prose and prose has no width — `"Wrote /Users/<home>/exports/mount.stl"` is an
## absolute path, and a `Label` in an `HBoxContainer` reports its text width as its minimum size. So
## the length of a builder's home directory was, for one draft of `dock.gd`, an input to whether the
## Sim button was on screen.
##
## Asserted as "the dock did not get wider", against the width measured before the long string went
## in, rather than against a constant — the dock's natural width is a function of a font and would
## rot the moment the theme changed.
##
## MUTATION CONFIRMED RED, AND IT TOOK THREE EDITS AT ONCE, which is worth stating rather than
## hiding: `dock.gd` holds three independently sufficient guards on this label — `clip_text`,
## `OVERRUN_TRIM_ELLIPSIS` and the `clip_contents` wrapper — and removing any ONE of them leaves
## this check green, because either of the other two still floors the Label's minimum at zero. All
## three removed together takes the dock from 1050 px to **28220 px** and this line goes red.
##
## So what this check actually guarantees is the OUTCOME and not any one mechanism, which is the
## right thing for it to guarantee: a future restyle that swaps the Label for something else keeps
## the assertion meaningful, and the three single-edit mutations are recorded here so nobody reads
## a green run as proof that each guard is load-bearing on its own.
static func _the_status_readout_cannot_widen_the_dock(shell: GlassShell, before: Rect2) -> TestResult:
	var after: Rect2 = shell._dock.get_global_rect()
	return TestResult.new(
		"a 4000-character status line does not widen the dock",
		after.size.x <= before.size.x and before.size.x > 200.0,
		"the dock was %.0f px wide and is %.0f px wide holding %d characters" % [
			before.size.x, after.size.x, shell._status_label.text.length()])


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


## And the THREE columns inside it do not meet. The schematic and the pack view are the two things
## a builder came here for and the inspector is the only way to change what the first of them draws,
## so an overlap is not a cosmetic fault: it is one of them drawn over another.
##
## PW6 is what makes this check earn its keep. PW5 had 468 px of slack between its two columns and
## nothing to spend it on; the pack view is now the claimant, and a column that grew past its share
## would land on a neighbour rather than on empty room.
##
## Measured off the panes' global rects rather than off their minimum-size constants, for the reason
## `test_glass_shell.gd`'s own 1280 row gives: those constants are floors, not widths. And the
## PACK VIEW is measured rather than the VBox it sits in, because the drawing is what would be
## covered.
##
## WHICH CLAUSE BELOW ACTUALLY HAS TEETH, because three of them do not and it would be dishonest to
## let the name suggest otherwise. The body is an `HBoxContainer`: it lays its children out in order
## at a fixed separation, so `gaps` is ALWAYS that separation and the schematic ALWAYS starts at the
## body's left edge, whatever the columns ask for. Two panes of a horizontal box cannot be made to
## overlap each other, and `pack.size.x > 0.0` is floored by `PackView`'s own minimum. What an
## over-wide column actually does is push the row PAST THE ROOM — so `inspector.end.x <= body.end.x`
## is the assertion, and the rest are numbers in the message. The mutation below was run and it
## failed exactly there: the inspector ended at x=1376 against a room ending at x=1260, while both
## gaps stayed at 8.
##
## MUTATION CONFIRMED RED: raise `PackView`'s `custom_minimum_size.x` to 600 — the inspector is
## pushed to x=1376 against a body ending at x=1260 (and the room's fit check above goes red too,
## with the content wanting 1356 px inside 1240).
static func _the_power_rooms_three_columns_do_not_overlap(shell: GlassShell) -> TestResult:
	var room: PowerWorkbench = shell.power_room()
	var drawing: Rect2 = room.schematic.get_global_rect()
	var pack: Rect2 = room.pack_view.get_global_rect()
	var inspector: Rect2 = room.inspector.get_global_rect()
	# Against the ROOM's rect less its gutters, for the reason above: the body is a Container and its
	# rect grows to whatever its children demand, so measuring against it asserts nothing.
	var body: Rect2 = room.get_global_rect().grow(-PowerWorkbench.GUTTER)
	var gaps := [pack.position.x - drawing.end.x, inspector.position.x - pack.end.x]
	var inside: bool = drawing.position.x >= body.position.x and inspector.end.x <= body.end.x
	var clear: bool = float(gaps[0]) >= 0.0 and float(gaps[1]) >= 0.0
	return TestResult.new(
		"the schematic, the pack view and the inspector share the Power room without overlapping",
		drawing.size.x > 0.0 and pack.size.x > 0.0 and clear and inside,
		"the schematic is %.0f px and ends at x=%.0f, the pack view is %.0f px from x=%.0f to x=%.0f (gaps %.0f and %.0f), the inspector runs x=%.0f to x=%.0f, inside a room whose gutters run x=%.0f to x=%.0f" % [
			drawing.size.x, drawing.end.x, pack.size.x, pack.position.x, pack.end.x,
			gaps[0], gaps[1], inspector.position.x, inspector.end.x,
			body.position.x, body.end.x])


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
static func _nothing_reaches_the_dock(shell: GlassShell) -> TestResult:
	var room: Control = shell.blade_room()
	var lowest := room.get_global_rect().end.y
	for child in room.get_children():
		if child is Control:
			lowest = maxf(lowest, (child as Control).get_global_rect().end.y)

	# THE DOCK, since QC3 — and the check means the same thing it meant before, which is the point
	# of measuring it off the node rather than off `BOTTOM_KEEPOUT`. The Lab/Sim cluster stood in
	# that keepout strip and the dock stands in the same strip, so the number this compares against
	# is unchanged (y=656 at 1280x720) and the room still clears it by 12 px. If the dock had grown
	# its own top edge upward this would have gone red, which is exactly what it is for.
	#
	# `_dock` and not `_bottom_right_glass`: the latter is now a group INSIDE the dock, and an
	# HBoxContainer's rect is set by the row that holds it — measuring it would be measuring the
	# dock's padding and calling it the dock.
	var cluster_top: float = shell._dock.get_global_rect().position.y
	return TestResult.new(
		"nothing the blade room draws reaches the dock",
		lowest <= cluster_top and cluster_top > 0.0,
		"the room's lowest edge is y=%.0f, the dock starts at y=%.0f" % [lowest, cluster_top])


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


# ---------------------------------------------------------------------------
# QC4 — §5 of plans/2026-09-19-quiet-canvas-design.md, and §4's "Opening"
# ---------------------------------------------------------------------------

## THE INSPECTOR IS THERE WHEN SOMETHING IS SELECTED — the half of the gate that is easy to forget
## to assert, and without which the absence check below is satisfied by an inspector that never
## appears at all.
##
## `visible` AND a real rect. A panel can be `visible` and 0x0 — that is what a Control reports
## before it has been laid out — so "the inspector is present" has to mean present on screen.
##
## MUTATION CONFIRMED RED: `_select_system`'s `_inspector.visible = not in_airframe` replaced by
## `_inspector.visible = false`.
static func _the_inspector_is_present_with_something_selected(shell: GlassShell) -> TestResult:
	var rect: Rect2 = shell._inspector.get_global_rect()
	return TestResult.new(
		"with Propulsion selected the inspector is on screen",
		shell._inspector.visible and rect.size.x > 200.0 and rect.size.y > 200.0,
		"visible %s, %.0fx%.0f px at x=%.0f" % [
			shell._inspector.visible, rect.size.x, rect.size.y, rect.position.x])


## AND IT IS NARROW. QC4's own "done when", measured.
##
## **What this check can and cannot claim, stated plainly because the constant alone would
## overclaim.** `INSPECTOR_WIDTH` is a FLOOR and `_fit_columns` grows the panel to whatever its
## rows want; measured at 1280x720 every system's content already wants more than 320 px, so
## lowering the constant from 348 moved nothing on screen. The panel at Propulsion is 378 px wide
## because its rows are 362 px wide, and it will stay 378 until the rows themselves shrink — which
## is §5's "it stops repeating what the rail showed", a content change QC4 did not make.
##
## So the bound below is the MEASURED width and not the constant: it is the number a future slice
## that widens the rows, or restores the old floor, has to answer to. 378 px at 1280x720.
##
## MUTATION CONFIRMED RED: `GlassShell.INSPECTOR_WIDTH` 320 -> 520. The floor becomes binding, the
## panel is laid out at 520 px, and this goes red by 142.
static func _the_inspector_is_no_wider_than_qc4_measured(shell: GlassShell) -> TestResult:
	var rect: Rect2 = shell._inspector.get_global_rect()
	return TestResult.new(
		"the Propulsion inspector is no wider than the 378 px QC4 measured at 1280x720",
		shell._inspector.visible and rect.size.x <= 378.0 and rect.size.x > 0.0,
		"the inspector is %.0f px wide, over content wanting %.0f px, against a %.0f px floor" % [
			rect.size.x, shell._inspector_content_width(shell._focused_panel_titles()),
			GlassShell.INSPECTOR_WIDTH])


## THE ICON OPENS THE FINDER ON ITS OWN SYSTEM — §4's "Opening", and the wiring QC1/QC2 left out.
##
## Asserted on the HEADER TEXT and not only on the category, because the header is the sentence a
## beginner reads to know what they are choosing ("the rail's title used to say that and the
## information must survive the rail"), and a finder built on the right category under the wrong
## system name would satisfy every structural assertion and still say `Drone · Motor`.
##
## Driven through `_dock.system_chosen` in `run()` above, so what this measures is a click.
##
## MUTATION CONFIRMED RED: `_on_system_chosen`'s `open_finder(index)` replaced by
## `open_finder(0)` — the finder opens `Drone · Frame` off the frame rail.
static func _the_dock_icon_opens_the_finder_on_its_own_system(shell: GlassShell) -> TestResult:
	var finder: PartFinder = shell.finder()
	var header := str(finder._header.text) if finder != null else "<no finder>"
	var category := str(finder.category) if finder != null else ""
	return TestResult.new(
		"clicking the Propulsion icon opens the finder on Propulsion's first category",
		shell.finder_open() and header == "Propulsion · Motor" and category == "motor",
		"open %s, header \"%s\", category \"%s\"" % [shell.finder_open(), header, category])


## AND IT OPENS ON THE BUILD, not on row 0 (§4.1). The fitted id is read off the rail before the
## finder exists, so the two sides of this comparison come from different objects.
##
## The fixture makes this able to fail: the reference build wears `motor_2207_1960kv`, which is row
## 8 of 18 in the motor catalog. A finder that opened on row 0 would land on a different motor.
##
## MUTATION CONFIRMED RED: `open_finder`'s `_finder.open_on(str(rail.selected_part()...))` replaced
## by `_finder.open_on("")` — the highlight falls to row 0.
static func _the_finder_opens_on_the_part_the_build_is_wearing(
		shell: GlassShell, fitted_at_open: String) -> TestResult:
	var finder: PartFinder = shell.finder()
	var highlighted := str(finder.highlighted_part().get("part_id", "")) if finder != null else ""
	return TestResult.new(
		"the finder opens highlighted on the motor the build is already wearing",
		fitted_at_open != "" and highlighted == fitted_at_open,
		"the build wears \"%s\"; the finder is on \"%s\" (row %d of %d)" % [
			fitted_at_open, highlighted,
			finder.highlighted_index() if finder != null else -1,
			finder.visible_parts().size() if finder != null else 0])


## THE CANVAS IS DIM AND THE INSPECTOR IS NOT — §5, "it is the one thing that should be readable
## while the finder is open, so the inspector is not dimmed with the canvas".
##
## **Asserted on DRAW ORDER, which is the mechanism, rather than on a colour.** The dim is one
## full-rect `ColorRect` and Godot draws siblings in tree order, so "not dimmed" means precisely
## "later in the shell's children than the dim". A check that read a modulate would pass against a
## dim placed on top of everything with the inspector's modulate hand-corrected back — which is the
## two-places-to-remember shape this project keeps finding.
##
## Three clauses, and the third is on purpose: without it, "the inspector is above the dim" is also
## satisfied by a dim that is above nothing at all.
##
## THE THIRD CLAUSE USED TO BE THE RAIL, and QC5 took the rail off the screen — a hidden panel's
## index says nothing about what is dimmed. `rooms` is the node the dim exists to cover: it holds
## the 3D canvas, and "the canvas is dim" is exactly the claim being made. It is also the FIRST
## child added in `_init`, so a dim that drifted to the bottom of the tree fails here.
##
## MUTATION CONFIRMED RED: move the `_build_dim()` call in `_init` from above `_build_inspector()`
## to below it. The dim's index goes from 11 to 12 and the inspector's from 12 to 11.
static func _the_canvas_is_dimmed_and_the_inspector_is_not(shell: GlassShell) -> TestResult:
	var dim: int = shell._dim.get_index()
	var inspector: int = shell._inspector.get_index()
	var canvas: int = shell.rooms.get_index()
	return TestResult.new(
		"the finder dims the canvas, and the dim stops below the inspector",
		shell.canvas_dimmed() and inspector > dim and canvas < dim and shell._inspector.visible,
		"dim is child %d (up %s), the inspector child %d (visible %s), the canvas child %d" % [
			dim, shell.canvas_dimmed(), inspector, shell._inspector.visible, canvas])


## THE PREVIEW REACHES THE REAL AIRCRAFT, through `RailFitter` and not through the suite's spy.
##
## This is the check that gives the restore check below its teeth. `TestPartFinder` already proves
## the finder CALLS `preview_part`; what nothing proved until here is that the shell's adapter turns
## that call into a fitted part. An adapter whose three methods were empty passes every existing
## test in the project and fails this one line.
##
## MUTATION CONFIRMED RED: `RailFitter.preview_part` emptied to `pass` — the build still wears the
## motor it opened on after three arrow-downs.
static func _previewing_fits_the_part_on_the_real_build(
		fitted_at_open: String, after_previews: String) -> TestResult:
	return TestResult.new(
		"arrowing three rows down fits a different motor on the real build",
		after_previews != "" and after_previews != fitted_at_open,
		"opened wearing \"%s\", wearing \"%s\" after three previews" % [
			fitted_at_open, after_previews])


## ESCAPE RESTORES THE ORIGINAL, after several previews, through the real adapter (§4, QC2).
##
## The third clause is what stops this being a test that cannot fail. "The build wears the original"
## is trivially true of a finder that never previewed anything, so the previewed id is passed in and
## asserted to have been a DIFFERENT motor — the check knows the build had genuinely moved before
## it was put back.
##
## MUTATION CONFIRMED RED: `RailFitter.restore_part` emptied to `pass` — the build is left wearing
## `motor_speedx_gr2306_2450kv`, the last thing previewed, which is exactly the part the builder
## just declined.
static func _escape_restores_the_original_after_several_previews(
		shell: GlassShell, rail: PartPicker, fitted_at_open: String,
		after_previews: String) -> TestResult:
	var now := str(rail.selected_part().get("part_id", "")) if rail != null else ""
	return TestResult.new(
		"Escape puts back the motor that was fitted when the finder opened, after three previews",
		now == fitted_at_open and fitted_at_open != "" and after_previews != fitted_at_open
			and not shell.finder_open(),
		"opened on \"%s\", previewed to \"%s\", Escape left \"%s\"" % [
			fitted_at_open, after_previews, now])


## And the overlay and the dim come down TOGETHER. Separate from the restore because they are
## separate failures: a finder that restores the fit and stays up is a modal with no exit, and a
## dim left behind is a screen the builder can neither read nor click.
##
## MUTATION CONFIRMED RED: `_retract_finder`'s `_dim.visible = false` deleted — the fit is restored,
## the overlay is down, and the canvas stays dark.
static func _escape_takes_the_overlay_and_the_dim_down_together(shell: GlassShell) -> TestResult:
	return TestResult.new(
		"Escape takes the finder and the dim down together",
		not shell.finder_open() and not shell._finder_glass.visible and not shell.canvas_dimmed(),
		"finder open %s, glass up %s, canvas dimmed %s" % [
			shell.finder_open(), shell._finder_glass.visible, shell.canvas_dimmed()])


## THE GATE: no selection, no inspector (§5, "appears only when something is selected").
##
## `present_before` is passed in and asserted, and it is the difference between this check and one
## that cannot fail. `not visible` is true of a shell whose inspector is broken, of one that never
## built it, and of one where the whole thing failed to load — so the check has to state that the
## panel WAS on screen a moment ago and went away because the selection did.
##
## THE CANVAS IS ASSERTED BACK, and this clause replaces the rail one QC5 made toothless — the rail
## column is now down in every state, so "the rail is down" here would have been a line that cannot
## fail. The resting state is the drone with nothing over it, so the thing worth asserting is that
## the drone is there: `_deselect` switches the viewport container back on after Airframe's room
## switched it off.
##
## MUTATION CONFIRMED RED: `_deselect`'s `_inspector.visible = false` deleted — the panel stays up
## describing a system nothing is focused on.
static func _the_inspector_is_absent_with_nothing_selected(
		shell: GlassShell, present_before: bool) -> TestResult:
	var canvas: Control = shell.lab.viewport().get_parent() as Control
	var canvas_up: bool = canvas != null and canvas.visible
	return TestResult.new(
		"clearing the selection takes the inspector away, leaves the drone, and it was there before",
		present_before and not shell._inspector.visible and canvas_up,
		"present before %s, visible now %s, canvas up %s, focused index %d" % [
			present_before, shell._inspector.visible, canvas_up, shell._focused_index])


## THE FINDER IS A PANEL AND NOT A SLIVER — the defect the first screenshot of this slice showed,
## written down as the check that should have caught it.
##
## `PartFinder` is a plain `Control` holding a `VBoxContainer`, and a Control neither lays its
## children out nor counts them in `get_combined_minimum_size()`. So the finder asks for
## `(368, 0)`, the `PanelContainer` around it obliged, and the glass came out **384x16** — a sliver
## behind the header with eighteen motor rows drawing below it, through the bottom of the window
## and under the dock. Every assertion in this file was green while that was on screen, because
## none of them measured the overlay.
##
## The height bound is the ItemList's own 320 px floor plus the header, the query field and the
## column's separations. Stated as "at least 380" rather than as an exact number for the reason
## the band's floor is a floor: a filter chip row added later legitimately makes it taller, and
## what must not happen is it collapsing again.
##
## QC5 REPAIRED IT AT SOURCE. `PartFinder` is a `VBoxContainer` now: it lays its own column out and
## reports its own height, and `GlassShell._size_the_finder()` — which measured the child column
## from outside and pushed the answer back — is deleted.
##
## MUTATION CONFIRMED RED: `part_finder.gd`'s `extends VBoxContainer` put back to `extends Control`
## — the glass is 384x16 again and this goes red by 364 px, exactly as it was before the repair.
static func _the_finder_is_a_real_panel_and_not_a_sliver(shell: GlassShell) -> TestResult:
	var glass: Rect2 = shell._finder_glass.get_global_rect()
	return TestResult.new(
		"the finder's glass is a real panel, not the 16 px sliver its Control root asked for",
		shell._finder_glass.visible and glass.size.x >= 368.0 and glass.size.y >= 380.0,
		"the finder's glass is %.0fx%.0f px at (%.0f, %.0f)" % [
			glass.size.x, glass.size.y, glass.position.x, glass.position.y])


## AND IT STAYS ON SCREEN, clear of the dock. The same rule §7 applies to every room, applied to
## the one control this slice adds: the window is 1280x720 and anything that grows vertically is
## charged against it.
##
## The dock rides its own `CanvasLayer` and therefore draws OVER the finder, which is why this is
## not cosmetic — an overlay that reached the dock would have its last rows hidden behind Lab/Sim
## rather than merely touching them, and the sliver above is what that looked like.
##
## MUTATION CONFIRMED RED: `PartFinder`'s list back to its pre-QC5 `Vector2(348, 320)` — the column
## measures 620 px, the glass runs y=50 to y=670 against a dock whose top is 656, and the last rows
## and both authoring buttons are behind Lab/Sim. That is the mutation that bites here rather than
## the `extends Control` one the check above uses: with a bare `Control` root NOTHING is laid out,
## so the rows report no rect at all and the glass shrinks INSIDE the window — the sliver check is
## the one that catches that, and these two are a pair.
static func _the_finder_fits_the_window_and_clears_the_dock(shell: GlassShell) -> TestResult:
	var glass: Rect2 = shell._finder_glass.get_global_rect()
	var window := Vector2(WINDOW)
	var dock_top: float = shell._dock.get_global_rect().position.y
	# Every Control the finder draws, measured individually rather than through the finder's own
	# rect — the glass sizes itself to what its child ASKS for, and the sliver proved those are two
	# numbers. With a bare `Control` root the rows keep their own global rects while the root
	# reports none, so this is the walk that sees them.
	var lowest := glass.end.y
	for child in shell.finder().get_children():
		if child is Control:
			lowest = maxf(lowest, (child as Control).get_global_rect().end.y)
	var inside: bool = glass.position.x >= 0.0 and glass.end.x <= window.x \
		and glass.position.y >= 0.0 and lowest <= window.y
	return TestResult.new(
		"the finder fits 1280x720 and nothing it draws reaches the dock",
		inside and lowest <= dock_top,
		"the glass runs x=%.0f-%.0f y=%.0f-%.0f, its lowest drawn edge is y=%.0f, the dock starts at y=%.0f" % [
			glass.position.x, glass.end.x, glass.position.y, glass.end.y, lowest, dock_top])
