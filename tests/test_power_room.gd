class_name TestPowerRoom
extends RefCounted
## The Power room — plans/2026-09-10-power-room-plan.md slice PW5, design §2.1.
##
## Every check below was shown to fail without its fix: the mutation named in each doc comment was
## inserted IN the source, the suite was run, the failure text was read, and the mutation was
## reverted — with the revert VERIFIED by `git diff` and a grep for the mutated string, because
## three of the four files this slice touches are new and `git checkout` silently no-ops on an
## untracked file.
##
## ---------------------------------------------------------------------------
## THE BUILD-FREE RULE, AND WHY IT TAKES TWO CHECKS RATHER THAN ONE
## ---------------------------------------------------------------------------
##
## The plan asks for "mutate the document without emitting; the view must be stale, not secretly
## right". Building it showed that sentence covers two different things, and only splitting them
## makes both testable:
##
##   - **The SHAPE is live.** `HarnessSchematic.geometry()` derives every point and every width
##     from `build.harness` on every call. It holds no polyline, no scale and no copy of a length.
##     That is the half P10d is about: `PropellerMesh` held its own copy of the chord law, so an
##     edited planform moved the physics and left the picture alone. A schematic that cached its
##     wires would be that defect. `_test_the_drawing_holds_no_copy_of_the_lengths` is that half,
##     and it is the one that would fail if a cache were introduced.
##
##   - **The COLOURS are announced.** Severity comes from `BuildWarning`s the ROOM computed and
##     handed over, never from the view running the checks itself. So a document mutated behind the
##     room's back is drawn at its new size in its OLD colour, and that staleness is the evidence
##     the view is not running a second copy of the ampacity check.
##     `_test_the_colours_are_stale_until_the_room_announces` is that half.
##
## Written the other way round — a view that re-derived its own warnings — the drawing would be
## "secretly right", which is the phrase the plan uses and the thing the second check refuses.
##
## ---------------------------------------------------------------------------
## WHAT IS NOT CHECKED HERE, SAID PLAINLY
## ---------------------------------------------------------------------------
##
##   - **Ctrl-Z.** A synthesised key needs a real window and a tree that processes frames.
##     `PropulsionWorkbench._unhandled_key_input` states the same constraint from the other side.
##     `undo()` and `redo()` are driven directly instead, which is everything below the key.
##   - **A real mouse click.** `_gui_input` needs the control to be in a tree with a size and an
##     event to be routed to it. `id_at()` is public for that reason and is the same path
##     `_gui_input` takes — driving it is not a parallel implementation.
##   - **Where the room's panes ended up on screen.** That has no answer until a container has run,
##     and it lives in `tests/test_shell_layout.gd` with the rest of the laid-out checks — including
##     PW5's 1280 row.
##
## The schematic is given an explicit `size` everywhere below. A `Control` that has never been laid
## out is (0, 0), `geometry()` correctly answers "nothing" for that, and a check written against it
## would pass because there was nothing to be wrong — `test_overlay_tray.gd` names that failure
## shape and this suite refuses it: every check asserts the geometry is non-empty first.

## The panel the schematic is measured in. Comfortably larger than its own 420x240 minimum, so the
## fit is doing arithmetic rather than clamping.
const PANEL := Vector2(640.0, 360.0)

## Millimetres round-trip through a px-per-mm fit, so the tolerance is float noise and not slack.
const EPS := 1.0e-6


static func run() -> Array:
	var results: Array = []

	results.append(_test_an_inspector_edit_changes_the_document_and_repaints())
	results.append(_test_the_drawing_holds_no_copy_of_the_lengths())
	results.append(_test_the_colours_are_stale_until_the_room_announces())
	results.append(_test_stroke_width_tracks_gauge())
	results.append(_test_drawn_length_tracks_length())
	results.append(_test_undo_steps_back_through_an_inspector_edit())
	results.append(_test_undo_twice_reaches_the_state_before_two_edits())
	results.append(_test_leaving_the_room_retracts_its_chrome())
	results.append(_test_every_overlay_room_is_in_the_retract_list())
	results.append(_test_a_click_selects_the_segment_under_it())
	results.append(_test_the_capacitor_is_a_part_and_not_a_segment())
	results.append(_test_default_restores_the_derived_value())
	results.append(_test_selecting_records_no_history())
	results.append(_test_the_panel_that_replaced_the_stub_carries_a_door())

	# PW6 — the pack view (design §2.2).
	results.append(_test_sliding_the_pack_aft_moves_the_marker_by_the_computed_amount())
	results.append(_test_the_marker_reads_airframe_properties_and_not_a_second_derivation())
	results.append(_test_the_marker_agrees_with_the_flight_centre_of_mass())
	results.append(_test_a_centred_pack_puts_the_marker_at_the_frames_own_centre())
	results.append(_test_the_drawn_pack_matches_battery_size_in_all_three_dimensions())
	results.append(_test_the_room_and_the_fit_panel_show_one_offset())
	results.append(_test_the_rooms_offset_slider_reaches_the_one_path_a_tweak_takes())

	return results


# ---------------------------------------------------------------------------
# The plan's row 1 — an edit reaches the document and the view
# ---------------------------------------------------------------------------

## The room's whole job in one line: something on the inspector moves, the harness changes, and the
## drawing is repainted against it — with `document_changed` said ONCE so the shell can rebuild the
## aircraft around a lead that just got longer.
##
## Driven through `inspector.value_edited` rather than by calling `_on_value_edited`, because the
## signal is the seam: a panel wired to nothing would pass a direct-call check forever.
##
## MUTATION CONFIRMED RED: move `document_changed.emit(build.harness)` out of
## `PowerWorkbench._refresh` and into `set_build`, so the room announces an OPEN and never an edit.
## Reported "announced 0 time(s)".
##
## Commenting the emit out entirely — the plan's wording — is not a usable mutation in GDScript:
## it orphans the signal, `gdscript/warnings/unused_variable=2` turns that into a load failure, and
## the suite reports a compile error rather than a red check. Moving it keeps the signal used and
## isolates exactly the behaviour under test.
static func _test_an_inspector_edit_changes_the_document_and_repaints() -> TestResult:
	var room := _room(ReferenceBuild.build())
	var announced := [0]
	room.document_changed.connect(func(_h: Harness) -> void: announced[0] += 1)

	room.schematic.select("main_lead")
	var before := _wire(room, "main_lead")
	room.inspector.value_edited.emit(Harness.MAIN_LEAD_LENGTH_MM, 240.0)
	var after := _wire(room, "main_lead")

	var stored := float(room.build.harness.value(Harness.MAIN_LEAD_LENGTH_MM, room.build))
	var moved: bool = not before.is_empty() and not after.is_empty() \
		and absf(float(after["length_mm"]) - float(before["length_mm"])) > EPS
	room.free()

	return TestResult.new(
		"an inspector edit changes the harness, repaints the view and announces once",
		absf(stored - 240.0) < EPS and moved and announced[0] == 1,
		"document reads %.1f mm, drawn length %.1f -> %.1f mm, announced %d time(s)" % [
			stored, float(before.get("length_mm", -1.0)), float(after.get("length_mm", -1.0)),
			announced[0]])


# ---------------------------------------------------------------------------
# The plan's row 2 — the Build-free rule, in its two halves
# ---------------------------------------------------------------------------

## THE P10d HALF. Nothing about the drawing's SHAPE is stored: the document is mutated with no call
## into the schematic at all — no `show_harness`, no `queue_redraw` — and the geometry that comes
## back is the new harness, because it was derived from the harness when it was asked for.
##
## A schematic that built its wires in `show_harness` and kept them would answer the OLD length
## here, which is exactly the shape `PropellerMesh` had: an editor for a thing the picture never
## caught up with.
##
## MUTATION CONFIRMED RED: cache the result of `geometry()` in `HarnessSchematic` on first call and
## return the cached dictionary thereafter.
static func _test_the_drawing_holds_no_copy_of_the_lengths() -> TestResult:
	var room := _room(ReferenceBuild.build())
	var before := _wire(room, "motor_lead")

	# Straight into the document, past the room. Nothing is told that anything happened.
	room.build.harness.set_value(Harness.MOTOR_LEAD_LENGTH_MM, 260.0)
	var after := _wire(room, "motor_lead")

	var followed: bool = not before.is_empty() and not after.is_empty() \
		and absf(float(after["length_mm"]) - 260.0) < EPS \
		and absf(float(before["length_mm"]) - 260.0) > EPS
	room.free()

	return TestResult.new(
		"the drawing derives its wires from the document rather than holding a copy",
		followed,
		"document set to 260 mm behind the room's back; drawing read %.1f mm before, %.1f mm after"
			% [float(before.get("length_mm", -1.0)), float(after.get("length_mm", -1.0))])


## THE OTHER HALF, and the one the plan words as "stale, not secretly right".
##
## Severity is `BuildWarning`'s, off warnings the ROOM ran and handed over — never re-derived in the
## view. So a document mutated with nothing announced draws its new geometry in its OLD colour, and
## that staleness is the proof the view is not running its own ampacity check. The instant the room
## announces, the colour moves.
##
## The fixture is the 10" on 6S for `test_harness_checks.gd`'s stated reason: it is the only build
## in the catalog whose sustained draw actually under-rates a thin motor lead, so 26 AWG here is a
## real LIMITING and not a decoration.
##
## MUTATION CONFIRMED RED: make `HarnessSchematic.severity_for` walk
## `HarnessChecks.warnings_for(_build)` instead of `_warnings`. The silently-edited document then
## read LIMITING where it must read CHARACTERISTIC — "secretly right", in the plan's own words.
static func _test_the_colours_are_stale_until_the_room_announces() -> TestResult:
	var room := _room(_six_s_cinelifter())
	var clean := room.schematic.severity_for("motor_lead")

	# 26 AWG on a build drawing 8 A per lead. The check will say so — once the room asks it.
	room.build.harness.set_value(Harness.MOTOR_LEAD_AWG, 26)
	var stale := room.schematic.severity_for("motor_lead")

	# And now through the room's own door, which is the only thing that recomputes the warnings.
	room.inspector.value_edited.emit(Harness.MOTOR_LEAD_AWG, 26)
	var announced := room.schematic.severity_for("motor_lead")
	room.free()

	return TestResult.new(
		"the drawing's colours are stale until the room announces, never secretly right",
		clean == BuildWarning.Severity.CHARACTERISTIC
			and stale == BuildWarning.Severity.CHARACTERISTIC
			and announced == BuildWarning.Severity.LIMITING,
		"severity clean=%d, after a silent edit=%d, after the room announced=%d" % [
			clean, stale, announced])


# ---------------------------------------------------------------------------
# The plan's row 3 — gauge is a width, length is a length
# ---------------------------------------------------------------------------

## The whole argument for this view existing (§2.1). Two segments at two gauges must be drawn at two
## widths, and the RATIO of those widths must be the ratio of the wires' real jacket diameters —
## which is what "to scale" means and what a constant, an exaggeration factor or a per-segment
## fudge would each break.
##
## Asserted as a ratio rather than as a px count because the fit is free to choose the scale; what
## it is not free to do is choose two of them.
##
## MUTATION CONFIRMED RED: in `HarnessSchematic.geometry`, replace `float(wire["od_mm"]) *
## px_per_mm` with a constant stroke width.
static func _test_stroke_width_tracks_gauge() -> TestResult:
	var room := _room(ReferenceBuild.build())
	room.inspector.value_edited.emit(Harness.MAIN_LEAD_AWG, 12)
	room.inspector.value_edited.emit(Harness.MOTOR_LEAD_AWG, 26)

	var main := _wire(room, "main_lead")
	var motor := _wire(room, "motor_lead")
	var drawn := float(main.get("stroke_px", 0.0)) / maxf(float(motor.get("stroke_px", 1.0)), EPS)
	# 5.0 mm of 12 AWG jacket over 1.7 mm of 26 AWG jacket, off the same table the mass and the
	# ampacity come from.
	var real := float(WireGauge.GAUGES[12][2]) / float(WireGauge.GAUGES[26][2])
	room.free()

	return TestResult.new(
		"stroke width is the wire's real jacket diameter, at one scale for the whole drawing",
		not main.is_empty() and absf(drawn - real) < 1.0e-4,
		"12 AWG over 26 AWG: drawn %.4f, real jacket ratio %.4f" % [drawn, real])


## And the other axis. A wire's drawn length divided by the drawing's own px-per-mm must come back
## as the millimetres in the document — not a fixed span, not a normalised one.
##
## This is what a topology diagram would fail: an icon schematic draws every run at whatever length
## makes the picture tidy, and the question a builder has is how much lead there is.
##
## MUTATION CONFIRMED RED: in `HarnessSchematic.geometry`, draw the main lead to a fixed span
## (`main_from + Vector2(100.0, 0.0)`) instead of `main_len`.
static func _test_drawn_length_tracks_length() -> TestResult:
	var room := _room(ReferenceBuild.build())
	room.inspector.value_edited.emit(Harness.MAIN_LEAD_LENGTH_MM, 175.0)

	var geometry := room.schematic.geometry()
	var main := _wire(room, "main_lead")
	var px_per_mm := float(geometry.get("scale", 0.0))
	var drawn_mm := (Vector2(main.get("to", Vector2.ZERO)) - Vector2(main.get("from", Vector2.ZERO)))\
		.length() / maxf(px_per_mm, EPS)
	room.free()

	return TestResult.new(
		"a wire is drawn at the length the document says it is",
		px_per_mm > 0.0 and absf(drawn_mm - 175.0) < 1.0e-3,
		"document 175.0 mm, drawn %.4f mm at %.4f px/mm" % [drawn_mm, px_per_mm])


# ---------------------------------------------------------------------------
# The plan's row 5 — undo is the ROOM's
# ---------------------------------------------------------------------------

## The reason the history is not in the canvas, as a check. NOTHING was dragged here: the edit came
## off the inspector's length box, and undo has to step back through it. A history owned by the
## schematic would have recorded selections and nothing else, and this would come back at 240 mm
## with the room reporting there was nothing to undo.
##
## MUTATION CONFIRMED RED: delete `history.record(build.harness.overrides())` from
## `PowerWorkbench._on_value_edited` — the "history in the canvas" shape, where only the drawing's
## own gestures are remembered.
static func _test_undo_steps_back_through_an_inspector_edit() -> TestResult:
	var build := ReferenceBuild.build()
	var was := float(build.harness.value(Harness.MAIN_LEAD_LENGTH_MM, build))
	var room := _room(build)

	room.inspector.value_edited.emit(Harness.MAIN_LEAD_LENGTH_MM, 240.0)
	var edited := float(room.build.harness.value(Harness.MAIN_LEAD_LENGTH_MM, room.build))
	var could := room.history.can_undo()
	room.undo()
	var back := float(room.build.harness.value(Harness.MAIN_LEAD_LENGTH_MM, room.build))
	room.free()

	return TestResult.new(
		"undo steps back through a field edit, not only through a drag",
		could and absf(edited - 240.0) < EPS and absf(back - was) < EPS,
		"%.1f mm -> %.1f mm -> undo -> %.1f mm (could undo: %s)" % [was, edited, back, could])


## TWICE, and `BladeHistory`'s header says why in one sentence: the room edits its harness in place,
## so a stack holding a live reference would rewrite its own memory on every later edit and the
## second undo would land nowhere. `HarnessHistory.record` duplicates for exactly this, and one undo
## cannot tell the two implementations apart.
##
## MUTATION CONFIRMED RED: drop the `.duplicate()` in `HarnessHistory.record`.
static func _test_undo_twice_reaches_the_state_before_two_edits() -> TestResult:
	var build := ReferenceBuild.build()
	var was := float(build.harness.value(Harness.MAIN_LEAD_LENGTH_MM, build))
	var room := _room(build)

	room.inspector.value_edited.emit(Harness.MAIN_LEAD_LENGTH_MM, 200.0)
	room.inspector.value_edited.emit(Harness.MAIN_LEAD_LENGTH_MM, 260.0)
	room.undo()
	var once := float(room.build.harness.value(Harness.MAIN_LEAD_LENGTH_MM, room.build))
	room.undo()
	var twice := float(room.build.harness.value(Harness.MAIN_LEAD_LENGTH_MM, room.build))
	room.free()

	return TestResult.new(
		"two edits undo to the two states that preceded them, in order",
		absf(once - 200.0) < EPS and absf(twice - was) < EPS,
		"%.1f -> 200 -> 260, undo -> %.1f, undo -> %.1f" % [was, once, twice])


# ---------------------------------------------------------------------------
# The plan's row 6 — the chrome retracts
# ---------------------------------------------------------------------------

## W0.7's defect family. Three paths retracted the shell's chrome and one omitted a term; the fix
## was to remove the argument a caller could omit, and here the whole list is removed from the
## caller's hands by `_retract_rooms`.
##
## Every path that has to end with no room on screen is walked: choosing another system, going to
## the field, deleting the project, and each room's own opener opening the OTHER room.
##
## MUTATION CONFIRMED RED: replace the `_retract_rooms()` call in `GlassShell._select_system` with
## the two lines it replaced (`_blade_room.visible = false` and its close glass) — the omission
## shape, where one room is put away and the one added later is not.
static func _test_leaving_the_room_retracts_its_chrome() -> TestResult:
	var shell := GlassShell.new()
	var failures: Array = []

	shell.select_system_by_name("Power")
	shell.set_power_room_open(true)
	if not shell.power_room().visible:
		failures.append("the room did not open")
	# The way out is the page bar's "← Back to drone" since the lab dock (design §2).
	if not shell._page_bar.visible:
		failures.append("the way out did not appear with it")

	# 1. Walking to another system.
	shell.set_power_room_open(true)
	shell.select_system_by_name("Propulsion")
	failures.append_array(_still_up(shell, "after choosing another system"))

	# 2. Opening the other room. Two opaque overlays and one close button is the state this refuses.
	shell.set_power_room_open(true)
	shell.set_blade_room_open(true)
	if shell.power_room().visible:
		failures.append("the harness designer stayed under the blade designer")

	# 3. Deleting the project.
	shell.set_blade_room_open(false)
	shell.set_power_room_open(true)
	shell._show_empty_state()
	failures.append_array(_still_up(shell, "after the project was closed"))

	# 4. Walking into another room entirely. The overlays are children of the SHELL, drawn over
	#    `rooms`, so this is the path that used to fly a course under a planform editor — the
	#    retraction was added here in PW5 and it went unnoticed because the way back always ends in
	#    `_select_system`, which retracts them. The room is only wrong while you are in the other
	#    one. Studio rather than Sim or a bench: it owns the window the same way and it starts no
	#    powertrain and no audio bus.
	shell.select_system_by_name("Power")
	shell.set_power_room_open(true)
	shell.rooms.show_studio()
	failures.append_array(_still_up(shell, "after walking into another room"))
	shell.rooms.show_lab()

	shell.free()
	return TestResult.new(
		"every path out of the Power room takes the room and its chrome with it",
		failures.is_empty(),
		"clean" if failures.is_empty() else "; ".join(failures))


## And the list itself. `_retract_rooms` walks `_overlay_rooms`, so a third room added as a child of
## the shell and forgotten here would be retracted by nothing — with no line of code missing
## anywhere to point at. Found by TYPE off the shell's own children rather than by a second
## hand-written list, which would be the same defect wearing a test's clothes.
static func _test_every_overlay_room_is_in_the_retract_list() -> TestResult:
	var shell := GlassShell.new()
	var registered: Array = []
	for entry in shell._overlay_rooms:
		registered.append(entry["room"])

	var missing: Array = []
	for child in shell.get_children():
		if (child is PropulsionWorkbench or child is PowerWorkbench) \
				and not registered.has(child):
			missing.append(child.get_script().resource_path.get_file())
	var count := shell._overlay_rooms.size()
	shell.free()

	return TestResult.new(
		"every overlay room the shell holds is in the list the retract paths walk",
		missing.is_empty() and count == 2,
		"%d room(s) registered, %d unregistered: %s" % [count, missing.size(), missing])


# ---------------------------------------------------------------------------
# Selecting, and what a selection is worth
# ---------------------------------------------------------------------------

## A click on a wire selects that wire. Driven through `id_at`, which is the same function
## `_gui_input` calls — see the header for why the event itself is out of reach.
##
## The point tested is the MIDDLE of the main lead, computed from the geometry rather than guessed,
## so the check does not quietly depend on the fan angles or on the panel size.
##
## MUTATION CONFIRMED RED: in `HarnessSchematic.id_at`, return "" for every wire (test the boxes
## only) — a schematic you cannot click.
static func _test_a_click_selects_the_segment_under_it() -> TestResult:
	var room := _room(ReferenceBuild.build())
	var main := _wire(room, "main_lead")
	var midpoint := (Vector2(main.get("from", Vector2.ZERO))
		+ Vector2(main.get("to", Vector2.ZERO))) * 0.5

	var hit := room.schematic.id_at(midpoint)
	room.schematic.select(hit)
	var shown := room.inspector._title.text
	room.free()

	return TestResult.new(
		"clicking a wire selects it and the inspector describes it",
		hit == "main_lead" and shown == "The main lead",
		"the point %.0f,%.0f hit \"%s\"; the inspector says \"%s\"" % [
			midpoint.x, midpoint.y, hit, shown])


## §2.1's distinction, as a check on both sides of it: the capacitor is drawn and selectable, it is
## never in `HarnessChecks.segments`, and the inspector offers it no gauge and no length because it
## has neither.
##
## MUTATION CONFIRMED RED: make `HarnessInspector.show_capacitor` fall through to `show_segment`'s
## controls (set `_gauge_row.visible = true`).
static func _test_the_capacitor_is_a_part_and_not_a_segment() -> TestResult:
	var room := _room(ReferenceBuild.build())
	var segment_ids: Array = []
	for segment in HarnessChecks.segments(room.build):
		segment_ids.append(String(segment["id"]))

	var drawn := false
	for box in room.schematic.geometry()["boxes"]:
		if String(box["id"]) == HarnessSchematic.CAPACITOR_ID:
			drawn = true

	room.schematic.select(HarnessSchematic.CAPACITOR_ID)
	var offers_gauge: bool = room.inspector._gauge_row.visible
	var offers_length: bool = room.inspector._length_row.visible
	room.free()

	return TestResult.new(
		"the capacitor is drawn and selectable, is not a segment, and is offered no gauge",
		drawn and not segment_ids.has(HarnessSchematic.CAPACITOR_ID)
			and not offers_gauge and not offers_length,
		"drawn: %s; segments are %s; gauge row up: %s, length row up: %s" % [
			drawn, segment_ids, offers_gauge, offers_length])


## "Default" clears the override rather than writing the derived number in as an authored one.
##
## The difference is invisible until the parts move, which is why it is checked here: after the
## clear, a longer arm has to lengthen the motor leads again. A default written in as a value would
## freeze at whatever the frame happened to be when the button was pressed — the defect
## `Harness`'s sparseness exists to prevent, arriving through the one control that can undo an
## override.
##
## MUTATION CONFIRMED RED: in `PowerWorkbench._on_default_restored`, replace `harness.clear(key)`
## with `harness.set_value(key, Harness.defaults(build)[key])`.
static func _test_default_restores_the_derived_value() -> TestResult:
	var room := _room(ReferenceBuild.build())
	room.schematic.select("motor_lead")
	room.inspector.value_edited.emit(Harness.MOTOR_LEAD_LENGTH_MM, 400.0)
	var authored := room.build.harness.has_override(Harness.MOTOR_LEAD_LENGTH_MM)

	room.inspector.default_restored.emit(Harness.MOTOR_LEAD_LENGTH_MM)
	var still := room.build.harness.has_override(Harness.MOTOR_LEAD_LENGTH_MM)
	var value := float(room.build.harness.value(Harness.MOTOR_LEAD_LENGTH_MM, room.build))
	var derived := float(Harness.defaults(room.build)[Harness.MOTOR_LEAD_LENGTH_MM])
	room.free()

	return TestResult.new(
		"\"Default\" forgets the override rather than writing the default in as one",
		authored and not still and absf(value - derived) < EPS,
		"authored: %s; override after Default: %s; reads %.1f mm against a derived %.1f mm" % [
			authored, still, value, derived])


## A selection is not an edit. Undo stepping back through clicks is the first thing a room-owned
## history gets wrong, and it gets it wrong here rather than in the canvas.
##
## MUTATION CONFIRMED RED: add `history.record(build.harness.overrides())` to
## `PowerWorkbench._on_selected`.
static func _test_selecting_records_no_history() -> TestResult:
	var room := _room(ReferenceBuild.build())
	room.schematic.select("main_lead")
	room.schematic.select("motor_lead")
	room.schematic.select(HarnessSchematic.CAPACITOR_ID)
	var depth := room.history.depth()
	var can_undo := room.history.can_undo()
	room.free()

	return TestResult.new(
		"selecting a segment records nothing to undo",
		depth == 0 and not can_undo,
		"three selections left %d entries on the undo stack" % depth)


## PW4's stub said "the model is built, the view is not" and named PW5 as what it waited on. PW5 is
## this slice, so the stub is gone — and the panel that replaced it carries the door into the room,
## because a panel with no way through to the thing it summarises is the stub again with better
## rows on it.
##
## MUTATION CONFIRMED RED: disconnect `harness_room_requested` in `GlassShell._build_power_room`.
static func _test_the_panel_that_replaced_the_stub_carries_a_door() -> TestResult:
	var shell := GlassShell.new()
	shell.select_system_by_name("Power")
	var wired: bool = shell.lab.harness_panel.harness_room_requested.get_connections().size() > 0

	shell.lab.harness_panel.harness_room_requested.emit()
	var opened: bool = shell.power_room().visible and shell.power_room().build != null
	shell.free()

	return TestResult.new(
		"the Harness panel's door opens the room, on the aircraft that is fitted",
		wired and opened,
		"door wired: %s; room up after pressing it: %s" % [wired, opened])


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## A room with an aircraft on the bench and a schematic big enough to have a geometry.
##
## The size is set BEFORE `set_build`, because `geometry()` fits to the rect it has and a (0, 0)
## control answers "nothing" — correctly, and in a way a careless check would read as a pass.
static func _room(build: Build, tweaks: AssemblyTweaks = null) -> PowerWorkbench:
	var room := PowerWorkbench.new()
	room.schematic.size = PANEL
	# The pack view is fitted the same way and for the same reason. Its own minimum is 360x240, so
	# PANEL is a fit and not a clamp here either.
	room.pack_view.size = PANEL
	room.set_build(build, tweaks if tweaks != null else AssemblyTweaks.new(),
		AirframeDocument.from_catalog_frame(build.frame))
	return room


## One wire out of the current geometry, by id. The FIRST of the four motor leads for that id, which
## is all four: they share a gauge and a length by construction (`HarnessSchematic`'s header).
static func _wire(room: PowerWorkbench, id: String) -> Dictionary:
	for wire in room.schematic.geometry()["wires"]:
		if String(wire["id"]) == id:
			return wire
	return {}


## `test_harness_checks.gd`'s fixture and its argument: the 10" on 6S is the only build in the
## catalog whose sustained draw genuinely under-rates a thin motor lead.
static func _six_s_cinelifter() -> Build:
	return Build.from_ids(PartsCatalog.load_default(), "frame_10in_long_range",
		"motor_2808_1300kv", "prop_10x5x2", "battery_6s_1300", "esc_4in1_80a_30x30",
		Build.DEFAULT_FC_ID, Build.no_components())


## Which of the two rooms, if either, is still on screen — named rather than counted, so a failure
## says which room and which path.
static func _still_up(shell: GlassShell, when: String) -> Array:
	var out: Array = []
	for entry in shell._overlay_rooms:
		var room: Control = entry["room"]
		var close_glass: Control = entry["close_glass"]
		if room != null and room.visible:
			out.append("%s is still up %s" % [entry["name"], when])
		if close_glass != null and close_glass.visible:
			out.append("the way out of %s is still up %s" % [entry["name"], when])
	if shell._page_bar.visible and not shell.page_open():
		out.append("the page bar is still up with no page %s" % when)
	return out


# ---------------------------------------------------------------------------
# PW6 — the pack, and the marker that moves with it
# ---------------------------------------------------------------------------

## THE SLICE IN ONE CHECK. The pack is slid 20 mm aft and the marker moves aft — by the number
## `AirframeProperties` computed for that aircraft and by no other number.
##
## Both halves matter and the second is the one with teeth: a marker drawn at 1.2x, or at a scale of
## its own, would still move in the right direction and would still look plausible on screen. So the
## pixels are compared against the centre of mass in METRES through the drawing's own px-per-mm,
## which is the same scale the pack and the plates are drawn at.
##
## MUTATION CONFIRMED RED: scale `com_plan` in `PackView.geometry` by 1.2.
static func _test_sliding_the_pack_aft_moves_the_marker_by_the_computed_amount() -> TestResult:
	var tweaks := AssemblyTweaks.new()
	var room := _room(ReferenceBuild.build(), tweaks)
	var before := room.pack_view.geometry()

	# Forward is −Z (physics.md §1), so aft is a NEGATIVE offset. Stated here because the sign is
	# the one thing about this axis that everybody gets wrong once.
	tweaks.set_mm(AssemblyTweaks.BATTERY_OFFSET, -20.0)
	room.refresh_pack()
	var after := room.pack_view.geometry()

	var scale := float(after["scale"])
	var moved_px: float = (after["com_plan"] as Vector2).x - (before["com_plan"] as Vector2).x
	var moved_mm: float = ((after["com_m"] as Vector3).z - (before["com_m"] as Vector3).z) * 1000.0
	var expected_px := moved_mm * scale
	# And the figure the marker was placed from is the one AirframeProperties gives for this
	# aircraft, computed here from the parts rather than taken from the view.
	var independent := _expected_cg_m(room.build, room.frame)
	var reads_true := absf(independent.z - (after["com_m"] as Vector3).z) < 1.0e-9
	room.free()

	return TestResult.new(
		"sliding the pack aft moves the marker aft, by the amount AirframeProperties computes",
		scale > 0.0 and moved_mm > 0.05 and absf(moved_px - expected_px) < 0.01 and reads_true,
		"the pack moved 20 mm aft, the centre of mass moved %.3f mm aft, the marker moved %.2f px against %.2f px expected at %.3f px/mm" % [
			moved_mm, moved_px, expected_px, scale])


## THE BUILD-FREE RULE, AS THE PLAN STATES IT: the pack's MASS changes and nothing else does. No
## dimension moves, no offset moves, no mount changes — every geometric input to this drawing is
## identical before and after.
##
## A view that derived the marker from where the pack is drawn — the obvious second derivation, and
## the one a room like this invites — would put the marker in exactly the same place twice. Only a
## marker that went back to `AirframeProperties.compute` can move here.
##
## MUTATION CONFIRMED RED: in `PackView.centre_of_mass_m`, return the pack's own centre scaled by
## its share of a nominal mass — i.e. any derivation that reads geometry rather than the computed
## centre of mass.
static func _test_the_marker_reads_airframe_properties_and_not_a_second_derivation() -> TestResult:
	var tweaks := AssemblyTweaks.new()
	# Off-centre, so the pack has a fore/aft moment for its mass to act through. A pack at the
	# frame's own centre contributes no first moment whatever it weighs, and this check would then
	# pass on the Y axis alone and say nothing about the axis the room is for.
	tweaks.set_mm(AssemblyTweaks.BATTERY_OFFSET, -25.0)
	var room := _room(ReferenceBuild.build(), tweaks)
	var before := room.pack_view.geometry()

	# The catalog row is duplicated first: the entry the build holds is the catalog's own dictionary,
	# and writing through it would leave a doubled pack in every suite that runs after this one.
	room.build.battery = room.build.battery.duplicate(true)
	room.build.battery["mass_g"] = float(room.build.battery["mass_g"]) * 2.0
	var after := room.pack_view.geometry()

	var geometry_still: bool = (before["pack_plan"] as Rect2).is_equal_approx(after["pack_plan"]) \
		and (before["pack_centre_m"] as Vector3).is_equal_approx(after["pack_centre_m"])
	var marker_moved_mm: float = ((after["com_m"] as Vector3).z - (before["com_m"] as Vector3).z) * 1000.0
	var marker_moved_px: float = (after["com_plan"] as Vector2).x - (before["com_plan"] as Vector2).x
	room.free()

	return TestResult.new(
		"doubling the pack's mass moves the marker, though nothing it is drawn from moved",
		geometry_still and absf(marker_moved_mm) > 0.5 and absf(marker_moved_px) > 0.5,
		"the drawn box is unchanged: %s; the marker moved %.2f mm (%.2f px)" % [
			geometry_still, marker_moved_mm, marker_moved_px])


## AND IT IS THE AIRCRAFT'S OWN CENTRE OF MASS, not a near neighbour of it.
##
## `AirframeProperties` weighs the frame from the document's plates and `mass_parts()` carries a
## `"Frame"` stand-in box as well, so the parts list handed over has that entry dropped — see
## `PackView`'s header. Forget the drop and the frame is weighed twice, at the origin, which does not
## look wrong: it drags the marker toward the middle by about half its distance out and every other
## check here still passes.
##
## So the marker's fore/aft figure is pinned against `MassProperties` over the SAME parts list —
## what the aircraft actually flies with — and the tolerance is a tenth of a millimetre, which the
## two agree to whenever the frame is counted once.
##
## MUTATION CONFIRMED RED: pass `_build.mass_parts()` straight through in `PackView._extra_parts`.
static func _test_the_marker_agrees_with_the_flight_centre_of_mass() -> TestResult:
	var tweaks := AssemblyTweaks.new()
	tweaks.set_mm(AssemblyTweaks.BATTERY_OFFSET, -25.0)
	var room := _room(ReferenceBuild.build(), tweaks)

	var marker := room.pack_view.centre_of_mass_m()
	var flying := MassProperties.compute(room.build.mass_parts()).com_m
	var gap_mm := absf(marker.z - flying.z) * 1000.0
	room.free()

	return TestResult.new(
		"the marker's fore/aft figure is the centre of mass the aircraft flies with",
		gap_mm < 0.1,
		"the marker reads %.4f mm and the flight centre of mass is %.4f mm — %.4f mm apart" % [
			marker.z * 1000.0, flying.z * 1000.0, gap_mm])


## A SYMMETRIC AIRCRAFT WITH A CENTRED PACK PUTS THE MARKER AT THE FRAME'S OWN CENTRE — in pixels,
## against the plates as drawn, because that is where an origin error lives. The metre-space figures
## would be zero either way.
##
## The build carries no optional components, and deliberately: the camera is at the nose and the VTX
## and the antenna are behind it, so a fitted aircraft's centre of mass is genuinely 0.2 mm aft of
## the frame's centre — a real answer that would make this check either wrong or slack.
##
## The VERTICAL axis is not asserted, and the honest reason is that it is not centred: the pack
## straps to the top plate and stands 31 mm above it, so the elevation marker belongs above the
## plates and a check that demanded otherwise would be asserting the physics is wrong.
##
## MUTATION CONFIRMED RED: add 5 px to `com_plan`'s origin in `PackView.geometry`.
static func _test_a_centred_pack_puts_the_marker_at_the_frames_own_centre() -> TestResult:
	var room := _room(ReferenceBuild.fore_aft_symmetric())
	var g := room.pack_view.geometry()

	var marker: Vector2 = g["com_plan"]
	var centre: Vector2 = g["frame_centre_plan"]
	var offset_mm := float(g["offset_mm"])
	var apart := (marker - centre).length()
	room.free()

	return TestResult.new(
		"a centred pack on a symmetric build puts the marker at the frame's own centre",
		float(g["scale"]) > 0.0 and absf(offset_mm) < 1.0e-9 and apart < 0.5,
		"the pack is at %.1f mm, the marker is at (%.1f, %.1f) px and the frame's centre is at (%.1f, %.1f) px — %.2f px apart" % [
			offset_mm, marker.x, marker.y, centre.x, centre.y, apart])


## THE BODY-AXES REORDER, IN THE PICTURE. `Build.battery_size_of` exists because the catalog
## publishes a pack in its own frame (length, width, height) and the aircraft wants body axes (width
## across X, height up Y, length along Z) — and the reorder is easy to get right in the physics and
## wrong in the drawing, where a pack laid across the airframe still looks like a pack.
##
## All three dimensions, over two panes: fore/aft and lateral out of the plan box, height out of the
## elevation box, each against `battery_size_m()` through the drawing's own scale. The fixture's pack
## is 35 x 37 x 75 mm — three different numbers, so a swapped pair has nowhere to hide.
##
## MUTATION CONFIRMED RED: swap `pack_size.z` and `pack_size.x` in `pack_plan` in
## `PackView.geometry`.
static func _test_the_drawn_pack_matches_battery_size_in_all_three_dimensions() -> TestResult:
	var room := _room(ReferenceBuild.build())
	var g := room.pack_view.geometry()
	var scale := float(g["scale"])
	var size_m: Vector3 = g["pack_size_m"]
	var plan: Rect2 = g["pack_plan"]
	var elevation: Rect2 = g["pack_elevation"]

	var drawn := Vector3(plan.size.y, elevation.size.y, plan.size.x) / maxf(scale, 1.0e-9) * 0.001
	var wrong: Array = []
	for pair in [["width across X", drawn.x, size_m.x], ["height up Y", drawn.y, size_m.y],
			["length along Z", drawn.z, size_m.z]]:
		if absf(float(pair[1]) - float(pair[2])) > 1.0e-6:
			wrong.append("%s is drawn %.1f mm and the pack is %.1f mm" % [
				pair[0], float(pair[1]) * 1000.0, float(pair[2]) * 1000.0])
	# And the elevation's fore/aft extent is the same length as the plan's, which is what makes the
	# two panes one drawing rather than two.
	if absf(elevation.size.x - plan.size.x) > 1.0e-6:
		wrong.append("the two panes disagree about the pack's length")
	room.free()

	return TestResult.new(
		"the drawn pack box matches battery_size_m() in all three body axes",
		scale > 0.0 and wrong.is_empty(),
		"drawn %.1f x %.1f x %.1f mm against %.1f x %.1f x %.1f mm%s" % [
			drawn.x * 1000.0, drawn.y * 1000.0, drawn.z * 1000.0,
			size_m.x * 1000.0, size_m.y * 1000.0, size_m.z * 1000.0,
			"" if wrong.is_empty() else " — " + "; ".join(wrong)])


## ONE OFFSET, TWO SCREENS. The Fit panel has shown and edited `battery_offset_mm` since the pack
## gained a mount, and this room must not become the third place it lives.
##
## The edit here is made through the PANEL, which is the case a room holding its own copy fails: a
## room that only wrote would still look right after its own slider moved, and would go stale the
## moment the value changed anywhere else. Both are then re-rendered against the same
## `AssemblyTweaks` and asked what they show.
##
## MUTATION CONFIRMED RED: in `PowerWorkbench.refresh_pack`, read the offset from `_offset_slider`
## instead of from `tweaks.value_mm` — the room's own copy.
static func _test_the_room_and_the_fit_panel_show_one_offset() -> TestResult:
	var tweaks := AssemblyTweaks.new()
	var build := ReferenceBuild.build()
	var panel := AssemblyPanel.new(tweaks)
	panel.render(build)
	var room := _room(build, tweaks)

	var applied := panel.set_tweak_mm(AssemblyTweaks.BATTERY_OFFSET, -12.0)
	panel.render(build)
	room.refresh_pack()

	var panel_text := panel.tweak_row_text(AssemblyTweaks.BATTERY_OFFSET)
	var room_text := room.offset_row_text()
	var drawn_mm := float(room.pack_view.geometry()["offset_mm"])
	panel.free()
	room.free()

	return TestResult.new(
		"the pack view and the Fit panel show the same offset, from the one place it lives",
		panel_text == room_text and absf(drawn_mm - applied) < 1.0e-9,
		"the panel says \"%s\", the room says \"%s\", and the drawing is at %.1f mm" % [
			panel_text, room_text, drawn_mm])


## What `AirframeProperties` says about this aircraft, derived HERE rather than asked of the view —
## the frame stand-in dropped, everything else passed through. A check that read the view's own
## figure and compared it to itself would be the tautology this suite's header refuses.
static func _expected_cg_m(build: Build, frame: AirframeDocument) -> Vector3:
	var extras: Array = []
	for part in build.mass_parts():
		if part.label != "Frame":
			extras.append(part)
	return AirframeProperties.compute(frame, PackView.materials(), extras).cg_m


## AND THE ROOM'S SLIDER IS ACTUALLY PLUGGED IN. The check above proves the two screens agree about
## a value; this one proves the room's own control reaches the place that value lives at all.
##
## Driven through the SHELL, because the routing is the shell's — the room announces
## `pack_offset_edited` and `GlassShell` hands it to `AssemblyPanel.set_tweak_mm`. A room whose
## slider was connected to nothing would pass every check in this file except this one, and would
## look exactly right until a builder dragged it.
##
## MUTATION CONFIRMED RED: drop the `pack_offset_edited` connection in
## `GlassShell._build_power_room`.
static func _test_the_rooms_offset_slider_reaches_the_one_path_a_tweak_takes() -> TestResult:
	var shell := GlassShell.new()
	shell.select_system_by_name("Power")
	shell.set_power_room_open(true)

	var room := shell.power_room()
	room.pack_offset_edited.emit(-9.0)
	var stored := shell.lab.tweaks.value_mm(AssemblyTweaks.BATTERY_OFFSET,
		shell.lab.current_build())
	var on_the_panel := shell.lab.assembly_panel.tweak_row_text(AssemblyTweaks.BATTERY_OFFSET)
	shell.free()

	return TestResult.new(
		"the room's offset control reaches the configuration, through the path that already owns it",
		absf(stored + 9.0) < 1.0e-9 and on_the_panel.begins_with("-9.0"),
		"the configuration reads %.1f mm and the Fit panel says \"%s\"" % [stored, on_the_panel])
