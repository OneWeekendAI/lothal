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

## The smallest window `project.godot` will let a builder make (`window/size/min_size`). Anything
## the shell draws has to fit THIS, not the size it opens at — the finder's height defect was
## invisible at 1280x720 on a three-facet shelf and unmissable here on a four-facet one.
const MIN_WINDOW := Vector2i(1024, 600)


## One key press, for the Escape path. Built here rather than pushed through `Input` because the
## shell's handler is `_unhandled_key_input` and the dummy display server delivers nothing.
static func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event


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
	results.append(_the_way_back_is_on_the_page_bar(shell))

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
	results.append(_the_dock_leaves_the_overlay_trays_band_alone(shell))
	# The inspector is a page now: open one so the clearance is measured against a panel on screen.
	shell.open_row(&"motors")
	for i in SETTLE_FRAMES:
		await tree.process_frame
	results.append(_the_dock_clears_the_inspector(shell))
	shell.back_to_drone()
	for i in SETTLE_FRAMES:
		await tree.process_frame

	# AND THE LONGEST THING THE DOCK CAN BE ASKED TO SAY. Not a hypothetical: `_on_mount_stl_requested`
	# writes `"Wrote %s"` with an absolute globalized path into this same label, so the length of a
	# builder's home directory is an input to the width of a centred control.
	shell._status_label.text = "Wrote /Users/%s/exports/mount.stl" % "d".repeat(4000)
	for i in SETTLE_FRAMES:
		await tree.process_frame
	results.append(_the_status_readout_cannot_widen_the_dock(shell, settled))

	# -----------------------------------------------------------------------
	# F10 — THE FIELD ROOM'S THREE PANELS FIT THE SHIPPING WINDOW.
	#
	# Here rather than in `tests/test_field_room.gd` for this file's stated reason: a `Container`
	# reports a combined minimum size of (0, 0) until a frame has been processed, so the same check
	# written in a frameless suite compares zeroes and passes forever.
	#
	# What it would catch is not hypothetical. The room's three panels sit in a column inside an
	# `HBoxContainer`, and a Container expands to its combined minimum WHATEVER its offsets say —
	# the fact this file's header names about the Power room's column and `dock.gd`'s header names
	# about the status readout. So one panel asking for more width than the window has left pushes
	# all three off the right-hand edge rather than squashing or scrolling them.
	# -----------------------------------------------------------------------
	shell.select_system_by_name("Field")
	# The Field room is the page of Field's rows now (lab dock design §4).
	shell.open_row(&"course")
	for i in SETTLE_FRAMES:
		await tree.process_frame

	results.append(_the_field_rooms_panels_fit_the_window(shell))
	results.append(_the_field_rooms_panels_do_not_overlap(shell))
	results.append(_the_field_room_leaves_the_site_something_to_be_seen_in(shell))
	# ONE CHECK PER PANEL, not a loop over the three: a looping check fails once and names the
	# loop rather than the panel whose rows went off the bottom.
	for title in FieldSystem.PANEL_TITLES:
		results.append(_every_row_a_panel_declares_is_drawn_inside_it(shell, str(title)))
	results.append(_the_course_panels_warnings_are_drawn_inside_it(shell))
	results.append(_the_field_rooms_column_stays_out_of_the_bottom_keepout(shell))
	# F11 — the three sliders, and the rail's typed fields. One check each, per the rule above.
	for which in ["Height", "Heading", "Radius"]:
		results.append(_a_course_panel_slider_is_drawn_inside_it(shell, which))
	results.append(_the_rails_own_controls_are_drawn_inside_it(shell))
	results.append(_the_rail_itself_stays_out_of_the_bottom_keepout(shell, WINDOW))
	results.append(_the_panels_column_stays_out_of_the_bottom_keepout(shell, WINDOW))
	results.append(_the_field_room_has_room_for_what_must_stay_visible(shell, WINDOW))

	# -----------------------------------------------------------------------
	# F11 FIX 1 — THE SAME ROOM AT THE SMALLEST WINDOW `project.godot` ALLOWS.
	#
	# **Every Field check above this point is taken at 1280x720, and the room did not fit at
	# 1024x600.** Measured before the repair: the room's row stood 579 px tall in the 468 px the
	# smallest window leaves it, so the rail ran to y=635 against a keepout floor of 524 — 111 px
	# inside the strip the dock stands in and 35 px below the bottom of the window itself. Nothing
	# saw it: `MIN_WINDOW` appears three times in this file and all three are the finder's.
	#
	# One check per thing rather than a loop, per this file's own rule, and taken at BOTH sizes
	# rather than only at the small one — the two columns' minimums are sums of constants, and a
	# repair that fits 600 by making 720 worse is a repair this file should not accept quietly.
	# -----------------------------------------------------------------------
	frame.size = MIN_WINDOW
	for i in SETTLE_FRAMES:
		await tree.process_frame

	results.append(_the_rail_itself_stays_out_of_the_bottom_keepout(shell, MIN_WINDOW))
	results.append(_the_panels_column_stays_out_of_the_bottom_keepout(shell, MIN_WINDOW))
	results.append(_the_field_room_has_room_for_what_must_stay_visible(shell, MIN_WINDOW))
	results.append(await _every_rail_control_is_reachable_at_the_smallest_window(shell, tree))
	# Ruling 78, locally: the two Field-room scrollers have a grabber with pixels in it.
	results.append(_the_field_rooms_scrollbars_have_a_width(shell))

	frame.size = WINDOW
	for i in SETTLE_FRAMES:
		await tree.process_frame

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

	# THE PAGE, since the lab dock: the inspector is the body of a row's page, up only while one is
	# open, so it is asserted absent on the drone and present once the Motors row is clicked.
	results.append(_no_page_is_up_on_the_drone(shell))
	shell.section_list().row_opened.emit(&"motors")
	for i in SETTLE_FRAMES:
		await tree.process_frame
	results.append(_the_inspector_is_present_with_something_selected(shell))
	results.append(_the_inspector_is_no_wider_than_qc4_measured(shell))
	shell.back_to_drone()
	for i in SETTLE_FRAMES:
		await tree.process_frame

	# THE CLICK, driven through the Motors row's choice line — where the finder is summoned from
	# since the lab dock (§2), rather than a dock icon.
	shell.section_list().pick_requested.emit(&"motors")
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
	shell.section_list().pick_requested.emit(&"motors")
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

	# -----------------------------------------------------------------------
	# THE VISUAL PASS ON THE FINDER (the five defects in bugs/*.png, plus density and the × ).
	#
	# Power's shelf and NOT Propulsion's, deliberately: Power's rail filters on four facets where
	# Propulsion's filters on three, so its column is a row taller — and every height defect the
	# screenshots caught was on the taller one while the three-facet shelf looked fine. A check
	# written on Propulsion is a check written on the case that already passed.
	# -----------------------------------------------------------------------
	# THE INSPECTOR'S OWN CLIPPING, before the finder is opened over it. A value longer than the
	# panel is not hypothetical — `8 kHz (not modelled here)` and `0.16 °/s RMS` are real FC rows,
	# and both were cut off at the window's edge in `bugs/`. Forced to an extreme here so the check
	# does not depend on which spec happens to be the longest today.
	shell.select_system_by_name("Propulsion")
	shell.open_row(&"motors")
	for i in SETTLE_FRAMES:
		await tree.process_frame
	var stretched := _stretch_an_inspector_row(shell)
	for i in SETTLE_FRAMES:
		await tree.process_frame
	results.append(_the_inspector_wraps_rather_than_running_off_the_edge(shell, stretched))

	var power := _index_of("Power")
	shell._dock.system_chosen.emit(power)
	shell.section_list().pick_requested.emit(&"battery")
	for i in SETTLE_FRAMES:
		await tree.process_frame

	results.append(_the_finder_is_opaque(shell))
	results.append(_the_rows_clear_the_scrollbar(shell))
	results.append(_no_row_repeats_itself_in_a_tooltip(shell))
	results.append(_the_finder_is_denser_than_the_page_around_it(shell))

	# THE SMALLEST WINDOW THE APP CAN BE PUT IN, which is `project.godot`'s own floor and not a
	# number invented here. Everything above is measured at 1280x720; this is the case the
	# screenshots were taken in — a column whose height was a sum of constants, in a window with
	# less room than the sum.
	frame.size = MIN_WINDOW
	for i in SETTLE_FRAMES:
		await tree.process_frame
	shell.section_list().pick_requested.emit(&"battery")
	for i in SETTLE_FRAMES:
		await tree.process_frame
	results.append(_the_finder_fits_the_smallest_window(shell))
	results.append(_the_squeezed_list_is_still_a_list(shell))

	# THE WAY OUT, BOTH PATHS, AND WHAT NEITHER OF THEM MAY DO. Back at the shipping window so the
	# finder is not being dismissed from its most cramped state.
	frame.size = WINDOW
	for i in SETTLE_FRAMES:
		await tree.process_frame
	var power_rail := shell._rail_for_system(power)
	var worn_before := str(power_rail.selected_part().get("part_id", "")) if power_rail != null else ""
	shell.section_list().pick_requested.emit(&"battery")
	for i in SETTLE_FRAMES:
		await tree.process_frame
	shell.finder().move_highlight(1)
	shell.finder().move_highlight(1)
	var previewed_onto := str(power_rail.selected_part().get("part_id", "")) if power_rail != null else ""
	shell.finder().press_close()
	for i in SETTLE_FRAMES:
		await tree.process_frame
	results.append(_the_close_button_dismisses_the_finder(shell))
	results.append(_closing_commits_nothing(
		shell, power_rail, worn_before, previewed_onto, "the × "))

	shell.section_list().pick_requested.emit(&"battery")
	for i in SETTLE_FRAMES:
		await tree.process_frame
	shell.finder().move_highlight(1)
	shell.finder().move_highlight(1)
	var escaped_onto := str(power_rail.selected_part().get("part_id", "")) if power_rail != null else ""
	shell._unhandled_key_input(_key(KEY_ESCAPE))
	for i in SETTLE_FRAMES:
		await tree.process_frame
	results.append(_escape_dismisses_the_finder(shell))
	results.append(_closing_commits_nothing(
		shell, power_rail, worn_before, escaped_onto, "Escape"))

	# THE LAB DOCK: the list, the pages, Back and Esc, collapse, and every row reaching its page.
	results.append_array(await LabDockChecks.run(shell, tree, WINDOW))
	results.append_array(await AirframePageChecks.run(shell, tree, WINDOW))
	results.append_array(await PropulsionPageChecks.run(shell, tree, WINDOW))
	results.append_array(await PowerPageChecks.run(shell, tree, WINDOW))
	results.append_array(await ControlPageChecks.run(shell, tree, WINDOW))
	results.append_array(await VideoPageChecks.run(shell, tree, WINDOW))
	results.append_array(await PrintedPageChecks.run(shell, tree, WINDOW))
	results.append_array(await ConfigPageChecks.run(shell, tree, WINDOW))
	results.append_array(await FieldPageChecks.run(shell, tree, WINDOW))

	# AND ESC OUT OF A PAGE. Asserted last: it leaves the stage on the drone.
	shell.open_row(&"motors")
	for i in SETTLE_FRAMES:
		await tree.process_frame
	var present_before := shell._inspector.visible
	shell._unhandled_key_input(_key(KEY_ESCAPE))
	for i in SETTLE_FRAMES:
		await tree.process_frame
	results.append(_the_inspector_is_absent_with_nothing_selected(shell, present_before))

	frame.queue_free()

	# -----------------------------------------------------------------------
	# AND WHAT BOOT ITSELF DOES TO THE DISK.
	#
	# Here rather than in `test_project_wiring.gd` for this file's own reason: the defect is in
	# `GlassShell._ready`, and `_ready` needs a tree and processed frames. The wiring suite drives
	# `ProjectLibrary` directly and is structurally unable to see it — which is exactly how the app
	# accumulated 465 untouched containers while every project suite stayed green.
	# -----------------------------------------------------------------------
	results.append_array(await _test_a_second_boot_writes_no_new_drone(tree))

	return results


# ---------------------------------------------------------------------------
# Boot resumes; it does not mint
# ---------------------------------------------------------------------------

## Every `.lothal` in `user://builds`, sorted. Names only — the comparison below is set-shaped and a
## full path would make the cleanup depend on how `globalize_path` spells things.
static func _lothal_files() -> Array:
	var absolute := ProjectSettings.globalize_path(ProjectLibrary.DIR)
	var found: Array = []
	if not DirAccess.dir_exists_absolute(absolute):
		return found
	for file in DirAccess.get_files_at(absolute):
		if file.ends_with(".%s" % ProjectContainer.EXTENSION):
			found.append(file)
	found.sort()
	return found


## LAUNCHING THE APP TWICE LEAVES ONE DRONE, NOT TWO.
##
## `_ready` used to call `adopt(container.project)` unconditionally, and `adopt` writes before it
## shows — so every launch put a fresh `Untitled build N` in `user://builds` whether or not the
## builder touched anything. The folder reached 465 files and the next default name, which counts
## what is on disk, read "Untitled build 422" to somebody who had saved nothing.
##
## ## The two checks are a pair, and neither one alone is the rule
##
## **File count alone** passes against a boot that resumes nothing and writes nothing — which is the
## other way to make the number stop growing, and it is the version that loses work, because a
## document with no path cannot autosave (`ProjectLibrary`'s own header). So the second check
## asserts the second shell came up ON the first one's container, by path.
##
## **Path alone** passes against a boot that opens the last drone and then writes a new file beside
## it. So the first check asserts the count did not move.
##
## ## Why it does not need an empty builds folder to be meaningful
##
## If the builder already has drones, the FIRST shell here resumes one too and writes nothing; both
## checks still hold, and under the old code both still fail, because the old code wrote on every
## boot regardless of what was there. The check is about the delta across the second boot, which is
## the quantity the defect is made of.
##
## Anything this check caused to be written is removed afterwards — and only that: the `before`
## snapshot is what protects the builder's own files from the cleanup.
static func _test_a_second_boot_writes_no_new_drone(tree: SceneTree) -> Array:
	ProjectLibrary.ensure_dir()
	var absolute := ProjectSettings.globalize_path(ProjectLibrary.DIR)
	var before := _lothal_files()

	var first_frame := SubViewport.new()
	first_frame.size = WINDOW
	tree.root.add_child(first_frame)
	var first := GlassShell.new()
	first_frame.add_child(first)
	for i in SETTLE_FRAMES:
		await tree.process_frame
	var first_path: String = first.container.path
	var after_first := _lothal_files()
	# The first shell is taken down before the second comes up, so the two are a relaunch rather
	# than two copies running at once — and so its autosave timer cannot write underneath the
	# snapshot the second boot is being measured against.
	first_frame.queue_free()
	for i in SETTLE_FRAMES:
		await tree.process_frame

	var second_frame := SubViewport.new()
	second_frame.size = WINDOW
	tree.root.add_child(second_frame)
	var second := GlassShell.new()
	second_frame.add_child(second)
	for i in SETTLE_FRAMES:
		await tree.process_frame
	var second_path: String = second.container.path
	var after_second := _lothal_files()
	second_frame.queue_free()
	for i in SETTLE_FRAMES:
		await tree.process_frame

	for file in after_second:
		if not before.has(file):
			DirAccess.remove_absolute("%s/%s" % [absolute, file])

	var grew: int = after_second.size() - after_first.size()
	return [
		{
			"name": "a second boot writes no new drone",
			"passed": grew == 0,
			"detail": "builds/ held %d containers after the first launch and %d after the second"
				% [after_first.size(), after_second.size()],
		},
		{
			"name": "a second boot comes up on the drone the first one left",
			"passed": second_path != "" and second_path == first_path,
			"detail": "first launch opened %s, second opened %s"
				% [first_path if first_path != "" else "(nothing)",
					second_path if second_path != "" else "(nothing)"],
		},
	]


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
	#
	# RE-MEASURED AT THE LAB DOCK: 976 x 572 at 1280x720. Wider (the band runs to the section list,
	# not to a measured inspector) and 8 px shorter (the top bar is flush and full width, and the
	# band keeps the viewport's tool buttons' corner clear). Recorded, not derived, as before.
	var tall_enough: bool = band.size.y >= 572.0 and band.size.x >= 976.0
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
static func _the_way_back_is_on_the_page_bar(shell: GlassShell) -> TestResult:
	# A ROOM IS A PAGE (lab dock design §2): the way out is "← Back to drone" on the page bar above
	# it, not a button carrying offsets over a room whose height it does not know. Asserted as a
	# parent AND as an edge: the bar ends where the room begins.
	var button: Button = shell._back_button
	var bar: Control = shell._page_bar
	var in_the_bar: bool = bar != null and button != null and bar.is_ancestor_of(button)
	var up: bool = bar.is_visible_in_tree() and shell.blade_room().visible
	var clear: bool = bar.get_global_rect().end.y <= shell.blade_room().get_global_rect().position.y
	return TestResult.new(
		"the way back from the blade room is on the page bar above it, and is up while the room is",
		in_the_bar and up and clear,
		"in the page bar: %s; room up %s, bar up %s, bar ends y=%.0f, room starts y=%.0f" % [
			in_the_bar, shell.blade_room().visible, bar.visible, bar.get_global_rect().end.y,
			shell.blade_room().get_global_rect().position.y])


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
static func _no_page_is_up_on_the_drone(shell: GlassShell) -> TestResult:
	return TestResult.new(
		"with Propulsion selected and no row open, no page is up — the drone has the stage",
		not shell._inspector.visible and not shell.page_open(),
		"page body visible %s, page %s" % [shell._inspector.visible, shell.open_page()])


static func _the_inspector_is_present_with_something_selected(shell: GlassShell) -> TestResult:
	var rect: Rect2 = shell._inspector.get_global_rect()
	return TestResult.new(
		"with the Motors row open the page body is on screen",
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
			rect.size.x, shell._inspector_content_width(shell._page_panel_titles()),
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
		"clicking the Motors row's choice line opens the finder on Propulsion's Motor shelf",
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
	# SINCE THE LAB DOCK the finder is summoned from a row of the LIST, over the drone, and the list
	# is the one thing that must stay readable while a choice is made — it shows the row being
	# decided. So the dim stops below the list (draw order, the mechanism) and above the canvas.
	var dim: int = shell._dim.get_index()
	var list: int = shell.section_list().get_index()
	var canvas: int = shell.rooms.get_index()
	return TestResult.new(
		"the finder dims the canvas, and the dim stops below the section list",
		shell.canvas_dimmed() and list > dim and canvas < dim and shell.section_list().visible,
		"dim is child %d (up %s), the list child %d (visible %s), the canvas child %d" % [
			dim, shell.canvas_dimmed(), list, shell.section_list().visible, canvas])


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
		"Esc takes the page away, leaves the drone, and the page was there before",
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
		shell._finder_glass.visible and glass.size.x >= PartFinder.PANEL_WIDTH
			and glass.size.y >= 300.0,
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


## THE FINDER IS OPAQUE, and this is the defect that made two panels share one set of pixels.
##
## `GLASS_ALPHA` is right for a panel over the MODEL and wrong for a panel over another panel: at
## 0.86 the FC inspector's "Processor F40", "Gyro MPU-600" and two amber warning paragraphs read
## straight through the list of flight controllers, and the charger's "1356 of 1500 mAh" read
## through the battery shelf. Both are in `bugs/`.
##
## The border and the shadow are asserted with the alpha, because "make it opaque" done carelessly
## is a flat rectangle with no edge — the panel would stop being see-through and stop reading as
## being in front of anything.
##
## MUTATION CONFIRMED RED: drop the `add_theme_stylebox_override` from `_build_finder_glass` so the
## finder goes back to the shared glass box — alpha reads 0.86.
static func _the_finder_is_opaque(shell: GlassShell) -> TestResult:
	var box := shell._finder_glass.get_theme_stylebox("panel") as StyleBoxFlat
	var alpha: float = box.bg_color.a if box != null else 0.0
	var border: int = box.border_width_left if box != null else 0
	var shadow: int = box.shadow_size if box != null else 0
	return TestResult.new(
		"the finder's panel is opaque, with an edge and a shadow to sit in front of",
		alpha >= 0.99 and border >= 1 and shadow > 0,
		"bg alpha %.2f, border %d px, shadow %d px" % [alpha, border, shadow])


## AND THE ROWS ARE NOT UNDER THE SCROLLBAR. QC5 widened the bar from zero so it could be seen and
## left the rows where they were, so the grabber was drawn on top of `GEPRC SPEEDX2 2107.5
## 1960KV  30 g`. Measured off the row's real rect against the list's real width, both of which
## exist only after a layout pass — which is why this check is in this file.
##
## MUTATION CONFIRMED RED: delete `list_box.content_margin_right = ROW_GUTTER` from
## `PartFinder._init` — the row runs to x=296 of a 300 px list with an 8 px bar over it.
static func _the_rows_clear_the_scrollbar(shell: GlassShell) -> TestResult:
	var finder: PartFinder = shell.finder()
	var list: ItemList = finder._list
	var row: Rect2 = list.get_item_rect(0)
	var bar: float = finder.scrollbar_width()
	return TestResult.new(
		"a row's right-hand edge stops before the scrollbar rather than running under it",
		row.end.x + bar <= list.size.x,
		"the row ends at x=%.0f, the %.0f px bar starts at x=%.0f of a %.0f px list" % [
			row.end.x, bar, list.size.x - bar, list.size.x])


## AND NO ROW CARRIES A FLOATING COPY OF ITSELF. `ItemList` falls back to an item's own text when no
## tooltip is set, and the engine draws that popup on the row the cursor is on — `2.5" Micro Whoop
## 28 g` over the row reading `2.5" Micro Whoop   28 g`, in two of the screenshots.
##
## Asserted here as well as in `tests/test_part_finder.gd` because the truncation rule is measured
## against the list's FONT, and outside the tree that is the engine's fallback font rather than the
## app's — a suppression that worked on the fallback metrics and not on the shipping ones would be
## green there and wrong here.
##
## MUTATION CONFIRMED RED: delete the `set_item_tooltip_enabled(...)` line from `PartFinder._refresh`
## — every row on the shelf repeats itself.
static func _no_row_repeats_itself_in_a_tooltip(shell: GlassShell) -> TestResult:
	var finder: PartFinder = shell.finder()
	var repeats: Array = []
	for i in finder.row_count():
		if finder.row_tooltip(i) == finder.row_text(i) and finder.row_text(i) != "":
			repeats.append(finder.row_text(i))
	return TestResult.new(
		"no row in the finder shows a tooltip that only repeats the row",
		repeats.is_empty(),
		"%d of %d rows repeat themselves, e.g. %s" % [
			repeats.size(), finder.row_count(), repeats.slice(0, 2)])


## AND IT READS AS A PICKER. The type in the finder and in the inspector beside it is set one step
## below the shell's body scale; the column is narrower than the 368 px QC5 gave it.
##
## The inspector is measured in the SAME check as the finder, because "bring them into the same
## scale" is a relation between two panels and a check on either one alone is satisfied by
## shrinking that one.
##
## MUTATION CONFIRMED RED: `PartFinder`'s list font override back to `FONT_SIZE_BODY` — the rows
## report 13 px against a body of 13.
static func _the_finder_is_denser_than_the_page_around_it(shell: GlassShell) -> TestResult:
	var finder: PartFinder = shell.finder()
	var rows: int = finder._list.get_theme_font_size("font_size")
	var title: int = finder._header.get_theme_font_size("font_size")
	var glass: Rect2 = shell._finder_glass.get_global_rect()
	# The inspector's own rows, found through the panel that is on screen for this system.
	var spec_size := 0
	for panel in _spec_panels(shell):
		for pair in (panel as SpecPanel)._row_labels:
			spec_size = maxi(spec_size, (pair[0] as Label).get_theme_font_size("font_size"))
	return TestResult.new(
		"the finder and the inspector beside it are set below the shell's body scale",
		rows < LothalTheme.FONT_SIZE_BODY and rows >= LothalTheme.FONT_SIZE_SMALL
			and title <= LothalTheme.FONT_SIZE_SUBTITLE
			and spec_size > 0 and spec_size < LothalTheme.FONT_SIZE_BODY
			and glass.size.x <= 340.0,
		"finder rows %d px, title %d px, inspector rows %d px, the panel is %.0f px wide" % [
			rows, title, spec_size, glass.size.x])


## THE HEIGHT DEFECT, AT THE SIZE IT SHOWS AT. 1024x600 is `project.godot`'s own minimum window, and
## Power's four-facet shelf is the tall one: the column asked for 483 px in a window with about 448
## to give, a `PanelContainer` obliged its child's minimum, and a `Control` does not clip — so the
## last rows, the bottom of the scrollbar and both authoring buttons were painted through the
## bottom of the window and under the dock, which rides its own CanvasLayer and draws over them.
##
## Every child is walked rather than trusting the glass's rect, for the reason
## `_the_finder_fits_the_window_and_clears_the_dock` gives: the panel sizes itself to what its child
## ASKS for, and the sliver proved those are two numbers.
##
## MUTATION CONFIRMED RED: delete the `_fit_finder()` call from `GlassShell.open_finder` — the
## authoring row's bottom edge lands below the dock's top.
static func _the_finder_fits_the_smallest_window(shell: GlassShell) -> TestResult:
	var glass: Rect2 = shell._finder_glass.get_global_rect()
	var window := Vector2(MIN_WINDOW)
	var dock_top: float = shell._dock.get_global_rect().position.y
	var lowest := glass.end.y
	for child in shell.finder().get_children():
		if child is Control:
			lowest = maxf(lowest, (child as Control).get_global_rect().end.y)
	return TestResult.new(
		"the finder fits the smallest window the app allows and still clears the dock",
		glass.position.y >= 0.0 and lowest <= window.y and lowest <= dock_top,
		"the glass runs y=%.0f-%.0f, its lowest drawn edge is y=%.0f, the dock starts at y=%.0f" % [
			glass.position.y, glass.end.y, lowest, dock_top])


## AND WHAT GAVE WAY WAS THE LIST. The fit above is satisfiable by a finder that dropped its
## authoring row or its facet chips off the bottom, which is the repair doing the damage the defect
## did; this names what was allowed to shrink and checks the rest is still there.
##
## MUTATION CONFIRMED RED: `PartFinder.fit_to_height` returning `LIST_HEIGHT` unconditionally — the
## list is still 232 px in a window that cannot hold it.
static func _the_squeezed_list_is_still_a_list(shell: GlassShell) -> TestResult:
	var finder: PartFinder = shell.finder()
	var height: float = finder.list_height()
	# SINCE THE LAB DOCK the bottom row is 40 px where the dock's keepout was 76, and at 1024x600 the
	# finder now fits at its full list height — so "the list shrank" is no longer the case here, and
	# asserting it would be asserting the old chrome. What must still hold is the other half: the
	# list is never squeezed below its floor or past its full height, and the facets and authoring
	# row are all there. `_the_finder_fits_the_smallest_window` keeps the fit's teeth.
	return TestResult.new(
		"the list gives way only within its bounds, and the header and authoring row survive",
		height <= PartFinder.LIST_HEIGHT and height >= PartFinder.LIST_HEIGHT_MIN
			and finder.action_labels().size() == 2
			and finder.facet_labels().size() == 4,
		"the list is %.0f px (full %.0f, floor %.0f), %d facets and %d actions remain" % [
			height, PartFinder.LIST_HEIGHT, PartFinder.LIST_HEIGHT_MIN,
			finder.facet_labels().size(), finder.action_labels().size()])


## THE × TAKES THE OVERLAY DOWN. Before this the finder could only be dismissed by a key nobody was
## told about: there was no control on the panel at all, in any of the five screenshots.
##
## The dim is asserted with it for `_escape_takes_the_overlay_and_the_dim_down_together`'s reason —
## a sheet of dim left over a live app with no overlay on it is an app that has stopped responding.
##
## MUTATION CONFIRMED RED: remove the `_finder.close_requested.connect(close_finder)` line from
## `GlassShell.open_finder` — the button emits and nothing happens.
static func _the_close_button_dismisses_the_finder(shell: GlassShell) -> TestResult:
	return TestResult.new(
		"the × in the finder's corner closes it, and takes the dim with it",
		not shell.finder_open() and not shell._finder_glass.visible and not shell._dim.visible,
		"open %s, glass %s, dim %s" % [
			shell.finder_open(), shell._finder_glass.visible, shell._dim.visible])


## AND SO DOES ESCAPE, through the shell's own key handler rather than by calling `close_finder`.
##
## MUTATION CONFIRMED RED: remove the `KEY_ESCAPE` branch from `GlassShell._unhandled_key_input` —
## the overlay stays up.
static func _escape_dismisses_the_finder(shell: GlassShell) -> TestResult:
	return TestResult.new(
		"Escape closes the finder through the shell's key handler",
		not shell.finder_open() and not shell._finder_glass.visible and not shell._dim.visible,
		"open %s, glass %s, dim %s" % [
			shell.finder_open(), shell._finder_glass.visible, shell._dim.visible])


## AND NEITHER WAY OUT CHOOSES ANYTHING. Both paths run through `PartFinder.cancel()`, so the build
## goes back to the pack it was wearing when the finder opened — after two previews that really did
## reach it.
##
## `previewed_onto` is asserted to be a DIFFERENT pack from the one worn before, and that is what
## stops this passing for the wrong reason: if the previews never reached the rail, "the fit is
## unchanged" is trivially true and a close that committed would look identical.
##
## MUTATION CONFIRMED RED: `GlassShell.close_finder` calling `_finder.accept()` instead of
## `_finder.cancel()` — the rail keeps the previewed pack.
static func _closing_commits_nothing(shell: GlassShell, rail: PartPicker, worn_before: String,
		previewed_onto: String, how: String) -> TestResult:
	var worn_now := str(rail.selected_part().get("part_id", "")) if rail != null else ""
	return TestResult.new(
		"closing with %s leaves the build wearing the part it had, not the one previewed" % how,
		worn_now == worn_before and previewed_onto != worn_before and not shell.finder_open(),
		"wore %s, previewed onto %s, wears %s" % [worn_before, previewed_onto, worn_now])


## Every SpecPanel in the shell, found by walking the tree.
##
## Walked rather than read off `lab.panels.get_children()`: the inspector's panels are nested
## inside the tab machinery on some systems and direct children on others, and a check that read
## one level found ZERO rows on Power and reported the inspector's type scale as 0 px — a number
## that satisfies "smaller than body" while measuring nothing at all.
static func _spec_panels(node: Node) -> Array:
	var out: Array = []
	if node is SpecPanel:
		out.append(node)
	for child in node.get_children():
		out.append_array(_spec_panels(child))
	return out


## Puts a value longer than any panel into the first row of every on-screen inspector, and returns
## how many it reached. Returned rather than assumed: a check that stretched nothing would then
## measure an inspector holding its ordinary short values and pass without exercising anything.
static func _stretch_an_inspector_row(shell: GlassShell) -> int:
	var touched := 0
	for panel in _spec_panels(shell):
		var spec: SpecPanel = panel
		if not spec.is_visible_in_tree() or spec._row_labels.is_empty():
			continue
		(spec._row_labels[0][1] as Label).text = \
			"8 kHz (not modelled here, and this is what a long one looks like)"
		touched += 1
	return touched


## THE INSPECTOR WRAPS RATHER THAN RUNNING OFF THE RIGHT-HAND EDGE.
##
## The shell clamps this panel at 45% of the window, and a clamp is only half an answer: a Label
## that may not wrap keeps its full minimum width, the grid keeps it, and the row is painted past
## the panel and past the window with it. `bugs/` shows four rows of the FC inspector ending
## mid-word at the screen edge — `8 kHz (not modelled`, `0.16 °/s RM`, `109 km/`, `11.3 :`. The
## ScrollContainer that was supposed to be the escape hatch could not be reached, because the
## theme's scrollbars report zero width and paint nothing.
##
## Measured against the PANEL's inner edge and the window's, and against every row rather than the
## stretched one: a wrap rule applied to one Label and not to the grid is the repair half-done.
##
## MUTATION CONFIRMED RED: delete `value_label.autowrap_mode = ...` from `SpecPanel._add_row` — the
## stretched row's label runs past both edges.
static func _the_inspector_wraps_rather_than_running_off_the_edge(
		shell: GlassShell, stretched: int) -> TestResult:
	var panel_right: float = shell._inspector.get_global_rect().end.x
	var window := Vector2(WINDOW)
	var worst := 0.0
	var offender := ""
	for panel in _spec_panels(shell):
		var spec: SpecPanel = panel
		if not spec.is_visible_in_tree():
			continue
		for pair in spec._row_labels:
			for label in pair:
				var rect: Rect2 = (label as Label).get_global_rect()
				var over := rect.end.x - minf(panel_right, window.x)
				if over > worst:
					worst = over
					offender = (label as Label).text
	return TestResult.new(
		"a long inspector value wraps inside the panel instead of running off the window",
		stretched > 0 and worst <= 0.0,
		"%d row(s) stretched, worst overhang %.0f px (%s), panel ends at x=%.0f of %d" % [
			stretched, worst, offender.substr(0, 28), panel_right, WINDOW.x])


## F10 — every one of the Field room's three panels is drawn inside the window.
##
## Measured against the WINDOW and not against the room, deliberately. A panel pushed past the
## room's own right edge is still off the screen if the room ends at the screen edge, and this room
## does: it runs to `CLUSTER_MARGIN` because it brings its own inspector.
##
## MUTATION CONFIRMED RED: raise one panel's `custom_minimum_size.x` past the budget (2000 on the
## Conditions panel) — all three panels are reported ending at x=2216 of a 1280 window.
##
## **THAT MUTATION IS POSITION-SENSITIVE, AND WRITING IT IN THE WRONG PLACE LOOKS EXACTLY LIKE THIS
## CHECK BEING UNABLE TO FAIL.** `SpecPanel._init` assigns `custom_minimum_size` itself, so the
## same line written BEFORE the `super([...])` call in a panel's `_init` is silently overwritten,
## the layout is unchanged, and the suite comes back 0/48 — a green run that reads as "the check
## did not notice", and is actually "the mutation never happened". It has to go AFTER `super()`.
## The general rule, worth more than this one case: when a mutation produces zero failures, prove
## the mutation took effect before concluding anything about the check.
static func _the_field_rooms_panels_fit_the_window(shell: GlassShell) -> TestResult:
	var room := shell.field_room()
	var window := Vector2(WINDOW)
	var worst := 0.0
	var offender := ""
	var measured := 0
	# On a Lab dock page only the page's own panel is up (FieldSystem.set_dock_page), so the one
	# drawn is the one measured; the other two are off the page, not somewhere off the window.
	for title in FieldSystem.PANEL_TITLES:
		var panel: SpecPanel = room.panel(str(title))
		if panel == null or not panel.is_visible_in_tree():
			continue
		measured += 1
		var rect := panel.get_global_rect()
		var over: float = maxf(rect.end.x - window.x, -rect.position.x)
		over = maxf(over, rect.end.y - window.y)
		if over > worst:
			worst = over
			offender = str(title)
	# GUARDED ON HAVING MEASURED ALL THREE. With no panels found, `worst` is 0.0 and the check
	# passes while nothing at all was looked at — the shape of "two missing rows compare equal".
	return TestResult.new(
		"the Field page's own panel is drawn inside the 1280x720 window",
		measured == 1 and worst <= 0.0,
		"%d panel(s) up, worst overhang %.0f px (%s)" % [
			measured, worst, offender if offender != "" else "—"])


## And none of the three is drawn on top of another.
##
## Separate from the fit check because they fail for different reasons and a builder needs to know
## which: a column that overflows the window is a width budget, and two panels sharing pixels is a
## container that stopped laying them out.
static func _the_field_rooms_panels_do_not_overlap(shell: GlassShell) -> TestResult:
	# On a dock page the page's panel shares a column with the page's settings (set_dock_page), so
	# the clash that matters is the panel against those controls and against the site.
	var room := shell.field_room()
	var panel: SpecPanel = room.panel(str(FieldSystem.DOCK_PANELS.get(room.dock_page, "")))
	if panel == null:
		return TestResult.new("and the page's panel shares no pixel with its settings or the site",
			false, "no dock page up (%s)" % room.dock_page)
	var rect := panel.get_global_rect()
	var clashes: Array = []
	for control in room.rail_controls_for(room.dock_page):
		if (control as Control).get_global_rect().intersects(rect):
			clashes.append(str(control.name))
	if room.viewport_container.get_global_rect().intersects(rect):
		clashes.append("site view")
	return TestResult.new(
		"and the page's panel shares no pixel with its settings or the site, and is no sliver",
		clashes.is_empty() and rect.size.x >= 100.0 and rect.size.y >= 40.0,
		"panel %s · clashes %s" % [rect, clashes])


## And the site — the thing the room exists to show — still has a viewport to be drawn in.
##
## The honest other half of a width budget: three panels that fit perfectly while leaving the
## viewport four pixels wide have satisfied every clearance and deleted the room.
static func _the_field_room_leaves_the_site_something_to_be_seen_in(
		shell: GlassShell) -> TestResult:
	var view := shell.field_room().viewport_container
	var width := 0.0 if view == null else view.get_global_rect().size.x
	return TestResult.new(
		"and the site itself keeps most of the window — the panels did not eat the viewport",
		view != null and width >= 500.0,
		"the site view is %.0f px wide in a %d px window" % [width, WINDOW.x])


## F10 FIX 1 — EVERY ROW A PANEL DECLARES IS DRAWN INSIDE THAT PANEL'S RECT.
##
## **This is the check that geometry could not see, and the defect it exists for shipped.** The
## three checks above measure where the PANELS are: inside the window, not overlapping, not having
## eaten the viewport. All three passed at 1280x720 while the Course panel's warning list was
## sliced in half and the Conditions panel's Temperature row was not on screen at all — because a
## panel that fits perfectly can still clip its own contents, and both of those rows are ones
## design §5.2 mandates.
##
## Two halves, and the second is what makes the first mean anything:
##
## 1. **Declared equals drawn.** `SpecPanel.spec_rows` is what the panel says it shows and
##    `_row_labels` is what it built; a panel that quietly stopped building a row would otherwise
##    satisfy every geometric assertion by having one fewer thing to place.
## 2. **Every one of those labels is inside the panel.** Measured against the panel's own global
##    rect, because that is the thing whose edge the text disappears at.
##
## The rect a clipped label reports is its UNCLIPPED position — a `ScrollContainer` paints inside
## its own bounds but the child still lives where the layout put it — so a row scrolled out of
## sight reports a rect below the panel and this goes red. That is measured behaviour on this repo,
## not an assumption: it is what the mutation below produces.
##
## MUTATION CONFIRMED RED: drop the `fit_to_content()` / `SIZE_FILL` pair in
## `FieldSystem._build_panels` and put `SIZE_EXPAND_FILL` back — the arrangement that shipped in
## `37adf4f`. See the report for the [FAIL] lines.
##
## ITS ONE BLIND SPOT, STATED SO IT IS NOT REDISCOVERED: this compares `Rect2`s, so it catches a
## row that ended up OUTSIDE the panel and not a row that is inside it and unreadable. A label
## allocated the panel's full width whose text is truncated to an ellipsis still reports a rect
## the panel `encloses`, and still passes. That is the same class of defect this check was written
## for, one level down — vertical overflow is covered, horizontal truncation is not.
static func _every_row_a_panel_declares_is_drawn_inside_it(
		shell: GlassShell, title: String) -> TestResult:
	var panel: SpecPanel = shell.field_room().panel(title)
	# GUARDED ON THE PANEL EXISTING AND DECLARING SOMETHING, before any rect is compared. A null
	# panel and an empty row list both make "nothing is outside" true, which is the shape of check
	# this project keeps re-inventing.
	if panel == null or panel.spec_rows.is_empty():
		return TestResult.new(
			"the Field room's %s panel declares rows to be checked" % title,
			false,
			"panel %s · %d rows declared" % [
				panel != null, 0 if panel == null else panel.spec_rows.size()])

	var panel_rect := panel.get_global_rect()
	var declared: int = panel.spec_rows.size()
	var built: int = panel._row_labels.size()
	var outside: Array = []
	for pair in panel._row_labels:
		for label in pair:
			var rect: Rect2 = (label as Label).get_global_rect()
			if not panel_rect.encloses(rect):
				outside.append("%s (%.0f..%.0f of %.0f..%.0f)" % [
					(label as Label).text.substr(0, 20), rect.position.y, rect.end.y,
					panel_rect.position.y, panel_rect.end.y])
	return TestResult.new(
		"every row the Field room's %s panel declares is drawn inside it" % title,
		built == declared and outside.is_empty(),
		"%d declared, %d built, %d outside: %s" % [
			declared, built, outside.size(), outside])


## And the Course panel's WARNINGS, which §5.2 mandates and which are not a spec row.
##
## Separate from the row check because they are a separate promise and they failed separately: the
## rows above the warning list all fitted in the shipped arrangement and the list underneath them
## was the thing cut in half.
static func _the_course_panels_warnings_are_drawn_inside_it(shell: GlassShell) -> TestResult:
	var panel := shell.field_room().panel("Course") as FieldSystem.CoursePanel
	if panel == null or panel.warnings == null:
		return TestResult.new(
			"the Field room's Course panel carries the course's warnings",
			false, "panel %s · warnings %s" % [panel != null, panel != null and panel.warnings != null])
	var panel_rect := panel.get_global_rect()
	var list_rect := panel.warnings.get_global_rect()
	# A ZERO-HEIGHT LIST IS ENCLOSED BY EVERYTHING, so its own size is asserted too — otherwise a
	# warning list that had stopped rendering would pass this by being nowhere.
	return TestResult.new(
		"and the warning list §5.2 mandates is drawn inside the Course panel, not sliced by its edge",
		panel_rect.encloses(list_rect) and list_rect.size.y > 0.0,
		"warnings %.0f..%.0f of panel %.0f..%.0f, %.0f px tall" % [
			list_rect.position.y, list_rect.end.y, panel_rect.position.y, panel_rect.end.y,
			list_rect.size.y])


## And the column of panels stays out of the strip the dock stands in.
##
## The window check above is not this check. `BOTTOM_KEEPOUT` is 76 px and the window is 720, so a
## column that runs to y=715 is inside the window and standing in the dock's strip — at 1280 the
## dock is centred and narrow enough that nothing visibly collides, and at `project.godot`'s 1024 px
## minimum the dock is clamped to the full width and it does.
static func _the_field_rooms_column_stays_out_of_the_bottom_keepout(
		shell: GlassShell) -> TestResult:
	var floor_y: float = WINDOW.y - GlassShell.BOTTOM_KEEPOUT
	var lowest := 0.0
	var offender := ""
	var measured := 0
	for title in FieldSystem.PANEL_TITLES:
		var panel: SpecPanel = shell.field_room().panel(str(title))
		if panel == null or not panel.is_visible_in_tree():
			continue
		measured += 1
		var bottom := panel.get_global_rect().end.y
		if bottom > lowest:
			lowest = bottom
			offender = str(title)
	return TestResult.new(
		"and the Field page's panel stays above the strip the dock stands in",
		measured == 1 and lowest <= floor_y,
		"%d panels, lowest edge y=%.0f (%s) against a floor of %.0f" % [
			measured, lowest, offender if offender != "" else "—", floor_y])


## F11 — THE THREE SLIDERS, AND THE NUMBERS BESIDE THEM, ARE DRAWN INSIDE THE COURSE PANEL.
##
## The row check above reads `SpecPanel.spec_rows`, which is the panel's declared GRID. The
## sliders are footer content, so not one of the five Field checks above looks at them — and F10's
## finding was precisely that: a panel can fit the window, not overlap anything, keep the viewport
## its width, and still clip the thing §5.2 mandates. The warning list got a check of its own for
## that reason and the sliders get three.
##
## THE VALUE LABEL IS ASSERTED AS WELL AS THE SLIDER, and the label is the half that goes first:
## the slider is a wide expanding control that a narrow column squashes, while the number beside it
## is the one that falls off the right-hand edge or wraps to a second line and pushes the warnings
## down. `encloses` on an empty rect is true of everything, so the control's own size is asserted.
static func _a_course_panel_slider_is_drawn_inside_it(
		shell: GlassShell, which: String) -> TestResult:
	var panel := shell.field_room().panel("Course") as FieldSystem.CoursePanel
	var slider: HSlider = null
	var value: Label = null
	if panel != null:
		match which:
			"Height":
				slider = panel.height_slider
				value = panel.height_value
			"Heading":
				slider = panel.heading_slider
				value = panel.heading_value
			"Radius":
				slider = panel.radius_slider
				value = panel.radius_value
	# GUARDED ON BOTH CONTROLS EXISTING before any rect is compared — a missing slider and a
	# clipped one would otherwise both report "nothing outside the panel".
	if slider == null or value == null:
		return TestResult.new(
			"the Field room's Course panel carries a %s slider and its readout" % which.to_lower(),
			false, "slider %s · value label %s" % [slider != null, value != null])

	var panel_rect := panel.get_global_rect()
	var slider_rect := slider.get_global_rect()
	var value_rect := value.get_global_rect()
	var reads := value.text.strip_edges()
	return TestResult.new(
		"the Field room's %s slider and the number beside it are drawn inside the Course panel"
			% which.to_lower(),
		panel_rect.encloses(slider_rect) and panel_rect.encloses(value_rect)
			and slider_rect.size.x > 40.0 and value_rect.size.y > 0.0 and reads != "",
		"slider %.0f..%.0f x, value \"%s\" at %.0f..%.0f x / %.0f..%.0f y, panel %.0f..%.0f x / %.0f..%.0f y" % [
			slider_rect.position.x, slider_rect.end.x, reads,
			value_rect.position.x, value_rect.end.x, value_rect.position.y, value_rect.end.y,
			panel_rect.position.x, panel_rect.end.x, panel_rect.position.y, panel_rect.end.y])


## F11 — AND THE RAIL'S OWN CONTROLS ARE DRAWN INSIDE THE RAIL.
##
## The rail took the five typed fields, the course name, and the four gate buttons this slice added
## — several of them because the Course panel had no room. That trade is only honest if the rail
## does have the room, and nothing measured it before: every Field check in this file is about the
## panel column on the other side of the window.
##
## Walked off the LIVE tree rather than from a list of members, so a control added to the rail
## later is covered without anybody remembering to name it here.
static func _the_rails_own_controls_are_drawn_inside_it(shell: GlassShell) -> TestResult:
	var room := shell.field_room()
	var rail: Control = room.rail_panel()
	if rail == null:
		return TestResult.new(
			"the Field room has a rail to measure", false, "no rail found above the Sites list")

	var rail_rect := rail.get_global_rect()
	var column := room.site_list.get_parent() as Control
	var outside: Array = []
	var measured := 0
	for child in column.get_children():
		var control := child as Control
		if control == null or not control.visible:
			continue
		measured += 1
		var rect := control.get_global_rect()
		if not rail_rect.encloses(rect):
			outside.append("%s (%.0f..%.0f of %.0f..%.0f)" % [
				control.name, rect.position.y, rect.end.y,
				rail_rect.position.y, rail_rect.end.y])
	# GUARDED ON HAVING MEASURED THE CONTROLS THIS SLICE PUT THERE. Two lists, two titles, a name
	# field, a button row, a GATE title and row, a THE FIELD title and five field rows, and a guess
	# label — an empty column would satisfy "nothing is outside it" with nothing in it.
	return TestResult.new(
		"every control in the Field room's rail is drawn inside the rail, not past its bottom edge",
		measured == room.rail_controls_for(room.dock_page).size() + 1 and measured >= 5
			and outside.is_empty(),
		"%d controls measured, %d outside: %s" % [measured, outside.size(), outside])


## F11 — AND THE RAIL ITSELF STAYS OUT OF THE DOCK'S STRIP.
##
## **THIS CHECK EXISTS BECAUSE THE SCREENSHOT FOUND WHAT THE CHECK ABOVE COULD NOT.** Every control
## in the rail was drawn inside the rail, and the rail had grown 46 px past the bottom of the room
## to hold them — an `HBoxContainer` expands to its combined minimum WHATEVER its offsets say, the
## fact this file's header names twice already, so `_field.offset_bottom = -BOTTOM_KEEPOUT` did not
## bound it. Measured at 1280x720: the "Gust settle" field sat at y=655..677 against a floor of
## 644, and at `project.godot`'s 1024 px minimum the dock is clamped to the full width and would
## have been drawn over it.
##
## Against the WINDOW's keepout rather than against the room, for `_the_field_rooms_column_stays_
## out_of_the_bottom_keepout`'s reason: the room's own rect is the thing that turned out not to
## bound its contents, so a check measured against it would have passed the defect it is for.
## TAKEN AT WHATEVER WINDOW THE CALLER IS AT, and the window is a parameter rather than `WINDOW`
## because the size this defect lived at is the one no Field check was ever taken at. See the
## `frame.size = MIN_WINDOW` block in `run()`.
static func _the_rail_itself_stays_out_of_the_bottom_keepout(
		shell: GlassShell, window: Vector2i) -> TestResult:
	var room := shell.field_room()
	var rail: Control = room.rail_panel()
	if rail == null:
		return TestResult.new(
			"the Field room has a rail to measure against the keepout", false, "no rail found")
	var floor_y: float = window.y - GlassShell.BOTTOM_KEEPOUT
	var rect := rail.get_global_rect()
	# A ZERO-HEIGHT RAIL IS ABOVE EVERY FLOOR, so its size is asserted too.
	return TestResult.new(
		"the Field room's rail stays above the strip the dock stands in at %dx%d, contents and all"
			% [window.x, window.y],
		rect.end.y <= floor_y and rect.size.y > 200.0 and rect.size.x > 100.0,
		"the rail is %.0f..%.0f y (%.0f x %.0f px) against a floor of %.0f" % [
			rect.position.y, rect.end.y, rect.size.x, rect.size.y, floor_y])


## THE OTHER COLUMN, AND IT IS A SEPARATE CHECK BECAUSE IT IS A SEPARATE SUM. The three panels
## come to 579 px of content where the rail's controls come to 472, so the panel column is the
## taller of the two and the one that decided how far the row overflowed — but the overflow was
## drawn on the RAIL's side of the window, which is how a defect in this column has twice been
## read as a defect in that one (see `_build_panels`'s own separation comment).
##
## Measured against the column's SCROLLER rather than against the three panels' rects, and the
## difference matters at the small window: a `ScrollContainer` clips what it cannot show, so a
## panel whose rect runs past the floor is not drawn past the floor once the column scrolls. The
## scroller's rect is what is painted; `_the_field_rooms_column_stays_out_of_the_bottom_keepout`
## above keeps the stricter "every panel, whole, no scrolling" rule at the shipping window.
static func _the_panels_column_stays_out_of_the_bottom_keepout(
		shell: GlassShell, window: Vector2i) -> TestResult:
	var room := shell.field_room()
	var scroller: Control = room.panels_scroll()
	if scroller == null:
		return TestResult.new(
			"the Field room has a panel column to measure against the keepout", false,
			"no panel scroller found")
	var floor_y: float = window.y - GlassShell.BOTTOM_KEEPOUT
	var rect := scroller.get_global_rect()
	return TestResult.new(
		"the Field room's panel column stays above the dock's strip at %dx%d" % [window.x, window.y],
		rect.end.y <= floor_y and rect.size.y > 200.0 and rect.size.x > 100.0,
		"the column is %.0f..%.0f y (%.0f x %.0f px) against a floor of %.0f" % [
			rect.position.y, rect.end.y, rect.size.x, rect.size.y, floor_y])


## HOW MUCH SLACK THE ROOM HAS, WHICH IS THE QUANTITY THAT OVERFLOWED — and it is asserted with a
## MARGIN rather than with `<=`.
##
## **Why the margin is not on the rects above.** The rail's drawn rect ends exactly on the keepout
## floor at both window sizes, and it does so BY CONSTRUCTION: `glass_shell._build_field` sets
## `_field.offset_bottom = -BOTTOM_KEEPOUT`, so a room that fits at all fits flush. `rect.end.y <=
## floor_y` on that rect is therefore a pass-at-exactly-equal by design and no margin can be put on
## it without moving the room off the floor it was laid out against. The number with real slack in
## it is the one underneath: the row's combined MINIMUM against the height the room has to give it.
## That is the sum that was 579 px in 468 before the two columns scrolled.
##
## **WHAT THIS MARGIN GUARDS NOW IS NOT WHAT RULING 69 WAS ABOUT, and saying otherwise would be
## claiming a mechanism this code no longer has.** Once each column sits in a `ScrollContainer`,
## the row's combined minimum is no longer a sum of row heights — it is `RAIL_VISIBLE_FLOOR` and
## `PANELS_VISIBLE_FLOOR`, 240 px each, and it reads 256 px at both window sizes whatever the rows
## inside do. Font or DPI drift in the rail's actual rows now moves the SCROLL RANGE instead: the
## room scrolls a little sooner and overlaps nothing. So Ruling 69's hazard — a row height drifting
## until the room is drawn over the dock — is closed STRUCTURALLY by the scrollers, not by this
## number, and that is a better outcome than the ruling asked for rather than a substitute for it.
##
## What the margin still does is guard the floors themselves: it is what fails if somebody raises
## `RAIL_VISIBLE_FLOOR` or `PANELS_VISIBLE_FLOOR` to a value the smallest window cannot give,
## reporting it as "the room does not fit" 24 px before the rect checks report it as an overlap.
## Demonstrated, not assumed: raising `RAIL_VISIBLE_FLOOR` to 560 reddens this check alone at
## 1280x720, at slack 12 against a wanted 24, with both rect checks still green.
##
## **The margin is 24 px, and it is chosen by eye.** It is one rail row and a bit — the room's
## rows measure 17 px (a title), 20 (the guess label) and 28 (a field row) — so a floor raised to
## within one row of the window is reported rather than shipped. Nothing derives it; if the rows
## are ever re-measured this moves with them.
const FIELD_KEEPOUT_MARGIN := 24.0


static func _the_field_room_has_room_for_what_must_stay_visible(
		shell: GlassShell, window: Vector2i) -> TestResult:
	var room := shell.field_room()
	var rail: Control = room.rail_panel()
	if rail == null or rail.get_parent() == null:
		return TestResult.new(
			"the Field room has a row to measure", false, "no rail, so no row above it")
	var row: Control = rail.get_parent() as Control
	var floor_y: float = window.y - GlassShell.BOTTOM_KEEPOUT
	var needed: float = row.get_combined_minimum_size().y
	var available: float = floor_y - row.get_global_rect().position.y
	# GUARDED ON THE ROW ASKING FOR SOMETHING. A row with a zero minimum fits every window, and it
	# is also what an empty room looks like — the two visible floors are what it must not be below.
	var floors: float = minf(FieldSystem.RAIL_VISIBLE_FLOOR, FieldSystem.PANELS_VISIBLE_FLOOR)
	return TestResult.new(
		"the Field room's row fits the %dx%d window with a row of slack to spare"
			% [window.x, window.y],
		needed >= floors and needed + FIELD_KEEPOUT_MARGIN <= available,
		"the row needs %.0f px and has %.0f (slack %.0f, wanted %.0f; floors %.0f)" % [
			needed, available, available - needed, FIELD_KEEPOUT_MARGIN, floors])


## AND THE CONTROLS THE SMALL WINDOW CANNOT SHOW AT ONCE ARE STILL REACHABLE.
##
## `_the_rails_own_controls_are_drawn_inside_it` asks whether every control is drawn inside the
## rail, and at 1024x600 the honest answer is no — the rail's controls come to 472 px and the room
## has 468, so the last row is below the fold and the `ScrollContainer` clips it. This check is the
## one that says the clipped rows are still REACHABLE rather than merely gone.
##
## ## What this check is NOT for, established by two reviewers' mutations rather than by argument
##
## Its first draft claimed to catch "a scroller whose vertical mode is off". **It does not, and the
## claim was tested and found false.** Setting `vertical_scroll_mode` to `SCROLL_MODE_DISABLED`
## makes the scroller adopt its child's 488 px minimum, so the room grows past the keepout and the
## three geometry checks beside this one go red while this one stays green. That hazard belongs to
## them. The same draft also said nothing about whether the builder can reach the rows by hand: it
## drives the scroll by ASSIGNING `scroll_vertical`, so a rail nobody can touch reads identically.
##
## ## THE VACUITY PATH, WHICH IS WHY THE FIRST TWO ASSERTIONS EXIST
##
## As first written this check never asserted that anything WAS below the fold. On the day the
## rail's contents shrink enough to fit 1024x600 outright — one row removed, one font smaller —
## `scroll_vertical` becomes a no-op, both `encloses` calls succeed trivially, and the check passes
## while testing nothing at all. That is this project's core defect class, arriving by the back
## door, and it is the thing the geometry checks cannot notice on this check's behalf.
##
## So the premise is asserted before the conclusion: **something is below the fold, and there is a
## range to scroll.** Those two are also what make this check killable on its own — shrinking the
## rail's content until it fits reddens THIS check and leaves all three geometry checks green,
## because the rail's minimum is the 240 px floor either way.
##
## Then both ends, and not just the bottom: scrolling to the end and finding the last row proves
## the range can be spent, and scrolling back and finding the first row proves it is a range rather
## than a column shoved permanently upward.
static func _every_rail_control_is_reachable_at_the_smallest_window(
		shell: GlassShell, tree: SceneTree) -> TestResult:
	var room := shell.field_room()
	var scroller: ScrollContainer = room.rail_scroll()
	var column: Control = room.site_list.get_parent() as Control
	if scroller == null or column == null or column.get_child_count() < 14:
		return TestResult.new(
			"the Field room's rail scrolls, and every control in it can be reached", false,
			"scroller %s · column %s · %d controls" % [
				scroller != null, column != null,
				0 if column == null else column.get_child_count()])

	# THE PREMISE CHANGED WITH THE LAB DOCK, AND THIS IS SAID RATHER THAN HIDDEN: a Field page
	# carries only its own settings and panel (set_dock_page), and at 1024x600 that fits without a
	# scroll — measured: the Course page ends at y=524 in a box to 552. So "something is below the
	# fold" is no longer asserted; what stays asserted is the conclusion — the first and the last
	# control the page SHOWS are both inside the box, at the end of the scroll and at its top.
	var shown: Array = []
	for child in column.get_children():
		if (child as Control).visible:
			shown.append(child)
	var first: Control = shown[0] as Control
	var last: Control = shown[shown.size() - 1] as Control

	# THE PREMISE, BEFORE THE CONCLUSION. Read with the scroll still at rest, which is the state
	# the room opens in: the last control is NOT inside the box, and the bar has somewhere to go.
	# Without these two this check passes vacuously the day the rail fits — see the header.
	var box_at_rest := scroller.get_global_rect()
	var below_the_fold := not box_at_rest.encloses(last.get_global_rect())
	var bar := scroller.get_v_scroll_bar()
	var range_to_scroll: float = 0.0 if bar == null else bar.max_value - bar.page

	scroller.scroll_vertical = int(column.size.y) + 1000
	for i in SETTLE_FRAMES:
		await tree.process_frame
	var box := scroller.get_global_rect()
	var last_rect := last.get_global_rect()
	var last_reached := box.encloses(last_rect) and last_rect.size.y > 0.0
	# AND THE SCROLL ACTUALLY MOVED. `scroll_vertical` clamps to the range, so a scroller with no
	# range accepts the assignment above and reports 0 — the same reading a column that refused to
	# scroll would give.
	var scrolled_to: int = scroller.scroll_vertical

	scroller.scroll_vertical = 0
	for i in SETTLE_FRAMES:
		await tree.process_frame
	box = scroller.get_global_rect()
	var first_rect := first.get_global_rect()
	var first_reached := box.encloses(first_rect) and first_rect.size.y > 0.0

	return TestResult.new(
		"the Field room's rail scrolls, and every control in it can be reached",
		shown.size() >= 5 and first != last and (not below_the_fold or scrolled_to > 0)
			and last_reached and first_reached,
		("below the fold at rest: %s · range to scroll: %.0f px (ended at %d) · "
			+ "scrolled to the end: %s (%s at %.0f..%.0f in %.0f..%.0f) · back to the top: %s (%s)")
			% [below_the_fold, range_to_scroll, scrolled_to,
			last_reached, last.name, last_rect.position.y, last_rect.end.y,
			box.position.y, box.end.y, first_reached, first.name])


## RULING 78, THE LOCAL HALF. `LothalTheme` styles a `VScrollBar` as a translucent grabber over a
## `StyleBoxEmpty` track, and neither stylebox carries a content margin. A `ScrollBar`'s minimum
## size IS its styleboxes' minimum size, so every scrollbar in this application reports a width of
## ZERO — live, wheel-scrollable, tracking correctly, painting nothing. F11 put two whole columns
## inside `ScrollContainer`s, and a panel column that silently ends mid-row reads as "that is all
## there is" rather than as "scroll" — on exactly the content §5.2 mandates.
##
## `FieldSystem._scroller()` applies `part_finder.gd`'s local workaround. This asserts it on the
## LIVE shell rather than by reading the source, because the number that matters is the one the
## bar reports after the theme has been applied to it — a `custom_minimum_size` set on a bar that
## was never built would pass a source scan and still paint nothing.
##
## THE THEME-LEVEL FIX STAYS PARKED, with its cost written down: a content margin on the grabber
## changes the minimum width of every `ScrollContainer` in the app, which needs re-measuring
## against the 1024x600 floors this file asserts. That is why this check names the Field room's
## two and not "every scrollbar".
static func _the_field_rooms_scrollbars_have_a_width(shell: GlassShell) -> TestResult:
	var room := shell.field_room()
	var rail: ScrollContainer = null if room == null else room.rail_scroll()
	var panels: ScrollContainer = null if room == null else room.panels_scroll()
	if rail == null or panels == null:
		return TestResult.new(
			"the Field room's two scrollbars are wide enough to see", false,
			"rail scroller %s · panel scroller %s" % [rail != null, panels != null])
	var rail_bar := rail.get_v_scroll_bar()
	var panel_bar := panels.get_v_scroll_bar()
	var rail_w: float = 0.0 if rail_bar == null else rail_bar.size.x
	var panel_w: float = 0.0 if panel_bar == null else panel_bar.size.x
	return TestResult.new(
		"the Field room's two scrollbars are wide enough to see (Ruling 78, locally)",
		rail_w >= FieldSystem.SCROLLBAR_WIDTH and panel_w >= FieldSystem.SCROLLBAR_WIDTH,
		"rail bar %.1f px, panel bar %.1f px, against the %.1f px this room asks for" % [
			rail_w, panel_w, FieldSystem.SCROLLBAR_WIDTH])
