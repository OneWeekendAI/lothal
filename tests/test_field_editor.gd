class_name TestFieldEditor
extends RefCounted
## The garage's field editor: the room where the world gets built (labs-and-sim.md §2.4).
##
## What is worth asserting here is not that the sliders move. It is that the editor is the ONLY
## writer, that what it writes is what Sim later flies, that the renderer follows the model rather
## than keeping a second copy of the gates, and that laying gates out costs nothing — no motor
## turns, so §5's consequence does not apply and nothing may invent one.

const LIBRARY_PATH := "user://test_field_editor_courses.json"
## The sites file that pairs with it. SiteLibrary owns the pairing rule; this is the same answer,
## spelled here so the teardown can delete it.
const SITES_PATH := "user://test_field_editor_courses_sites.json"
## And the conditions file beside it, on the same pairing rule — this room switches the weather now
## that the temperature has left the site (F2).
const CONDITIONS_PATH := "user://test_field_editor_courses_conditions.json"


static func run() -> Array:
	var results: Array = []
	# THE HOLD ON THE BUILDER'S OWN FILES. Taken here and released below, because a section that
	# aborts mid-way never reaches its own restore — measured, and it is what left a 3500 m
	# elevation and an invented weather row on this developer's disk. `run()` is the only frame
	# GDScript guarantees will resume after an abort inside a section, so the hold lives here and
	# `run()` does nothing else. See tests/real_files.gd.
	var held := RealFiles.hold([
		SiteLibrary.SAVE_PATH, CourseLibrary.SAVE_PATH, ConditionsLibrary.SAVE_PATH])
	var sections := {
		"editing gates": _editing_gates(),
		"the renderer": _the_renderer_follows(),
		"courses": _courses(),
		"what sim flies": _it_writes_what_sim_flies(),
		"it costs nothing": _it_costs_nothing(),
		"the field itself": _the_field_itself(),
	}
	held.restore()
	results.append(TestResult.new(
		"the builder's own files are back the way they were found, whatever the sections did",
		held.intact(), held.report()))
	# ADDED IN F2, AFTER THIS FILE PROVED THE NEED FOR IT. A runtime error partway through a
	# section aborts only that section and its append never runs, so the suite passes with its best
	# checks silently deleted. Measured here: `Site.air()` went away, "the field itself" aborted at
	# its fourth check, and the whole run still printed ALL 2668 TESTS PASSED with an error line
	# scrolled past above it. Every other suite in this directory had this guard; this one did not.
	for label in sections:
		var section: Array = sections[label]
		results.append(TestResult.new(
			"section \"%s\" produced results" % label, not section.is_empty(),
			"%d checks" % section.size()))
		results.append_array(section)
	return results


static func _forget(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _editor() -> FieldEditorScreen:
	_forget(LIBRARY_PATH)
	_forget(SITES_PATH)
	_forget(CONDITIONS_PATH)
	return FieldEditorScreen.new(
		CourseLibrary.load_from(LIBRARY_PATH), ReferenceBuild.build(), LIBRARY_PATH)


# ---------------------------------------------------------------------------
# Placing, moving, re-ordering, adding and removing
# ---------------------------------------------------------------------------

static func _editing_gates() -> Array:
	var results: Array = []
	var editor := _editor()

	var before := editor.course().gates.size()
	editor.select_gate(2)
	editor.add_gate()
	results.append(TestResult.new(
		"a gate can be added, and it lands between the two it was added between",
		editor.course().gates.size() == before + 1 and editor.selected_gate == 3,
		"%d gates, editing gate %d" % [editor.course().gates.size(), editor.selected_gate + 1]
	))

	# The added gate has to be somewhere flyable, not at the origin: an editor that drops new
	# gates in a corner of the map makes you drag every one of them before the course means
	# anything, which is the difference between authoring and data entry.
	var added: Dictionary = editor.course().gates[3]
	var neighbours := float(editor.course().gates[2]["position"].distance_to(
		editor.course().gates[4]["position"]))
	results.append(TestResult.new(
		"a new gate appears on the route rather than at the origin",
		added["position"].distance_to(editor.course().gates[2]["position"]) < neighbours
			and added["position"].y > 0.0,
		"new gate at %s, %.1f m from the one before it" % [
			added["position"], added["position"].distance_to(editor.course().gates[2]["position"])]
	))

	# The course must still be flyable with the extra gate in it — the whole point of putting the
	# new gate on the route.
	editor.course().reset()
	var passes := 0
	for i in editor.course().gates.size():
		var gate: Dictionary = editor.course().gates[i]
		if editor.course().advance(gate["position"] - gate["normal"] * 0.5,
				gate["position"] + gate["normal"] * 0.5):
			passes += 1
	results.append(TestResult.new(
		"a nine-gate course is flown and lapped as nine gates",
		passes == 9 and editor.course().just_completed_lap(),
		"%d of %d gates scored" % [passes, editor.course().gates.size()]
	))

	# Moving a gate: the editor authors in the terms you think in — a place on the ground, a
	# height, a heading and a ring size.
	editor.select_gate(0)
	editor.set_gate_ground_position(Vector3(40.0, 0.0, -12.0))
	editor.set_gate_height_m(6.5)
	editor.set_gate_heading_deg(90.0)
	editor.set_gate_radius_m(0.9)
	var moved: Dictionary = editor.course().gates[0]
	results.append(TestResult.new(
		"a gate is placed by ground position, height, heading and ring size",
		moved["position"].distance_to(Vector3(40.0, 6.5, -12.0)) < 1.0e-6
			and absf(float(moved["radius"]) - 0.9) < 1.0e-6
			and moved["normal"].distance_to(Vector3(1.0, 0.0, 0.0)) < 1.0e-6,
		"gate 1 at %s facing %s, %.2f m ring" % [
			moved["position"], moved["normal"], float(moved["radius"])]
	))

	# Re-ordering changes the route, which is what makes the order part of the authored world
	# rather than an accident of when a gate was placed.
	var second_before: Vector3 = editor.course().gates[1]["position"]
	editor.select_gate(1)
	var reordered := editor.reorder_gate(1)
	results.append(TestResult.new(
		"a gate can be moved later in the running order, and the selection follows it",
		reordered and editor.selected_gate == 2
			and editor.course().gates[2]["position"].distance_to(second_before) < 1.0e-9,
		"the gate that was 2nd is now %d%s" % [editor.selected_gate + 1, ""]
	))

	var fresh := FieldEditorScreen.new(
		CourseLibrary.load_from(LIBRARY_PATH), ReferenceBuild.build(), LIBRARY_PATH)
	results.append(TestResult.new(
		"the first gate cannot be moved earlier than first",
		not fresh.reorder_gate(-1),
		"reordering gate 1 backwards refused"
	))
	fresh.free()

	# Removing, down to the floor: a course with no gates is not a course.
	var removals := 0
	while editor.remove_gate():
		removals += 1
	results.append(TestResult.new(
		"gates can be removed, but never the last one — a course with no gates is not a course",
		editor.course().gates.size() == 1 and removals == 8,
		"%d removed, %d gate left" % [removals, editor.course().gates.size()]
	))

	editor.free()
	return results


# ---------------------------------------------------------------------------
# One description of the world
# ---------------------------------------------------------------------------

static func _the_renderer_follows() -> Array:
	var results: Array = []
	var editor := _editor()

	# The editor draws gates through CourseRenderer, off the same GateCourse Sim reads. An editor
	# that drew its own rings would be the second implementation of the world, which is the one
	# thing gate_course.gd's opening line forbids.
	var renderer := editor.renderer
	results.append(TestResult.new(
		"the editor draws the course through CourseRenderer, not through gates of its own",
		renderer != null and renderer.course == editor.course()
			and renderer.get_child_count() == editor.course().gates.size(),
		"%d rings drawn for %d gates" % [
			0 if renderer == null else renderer.get_child_count(), editor.course().gates.size()]
	))

	editor.select_gate(3)
	editor.add_gate()
	results.append(TestResult.new(
		"adding a gate adds a ring — the picture cannot fall behind the model",
		renderer.get_child_count() == editor.course().gates.size(),
		"%d rings for %d gates" % [renderer.get_child_count(), editor.course().gates.size()]
	))

	results.append(TestResult.new(
		"the gate being edited is the lit one",
		renderer.highlight_index == editor.selected_gate,
		"editing gate %d, lit gate %d" % [editor.selected_gate + 1, renderer.highlight_index + 1]
	))

	editor.select_gate(0)
	editor.set_gate_height_m(0.5)
	var says := editor.warnings()
	var complained := false
	for entry in says:
		if entry.id == CourseWarnings.GATE_BELOW_GROUND:
			complained = true
	results.append(TestResult.new(
		"burying a ring in the ground is reported the moment it happens",
		complained,
		"a 1.5 m ring centred 0.5 m up says: %s" % ", ".join(BuildWarning.messages(says))
	))

	editor.free()
	return results


# ---------------------------------------------------------------------------
# More than one course
# ---------------------------------------------------------------------------

static func _courses() -> Array:
	var results: Array = []
	var editor := _editor()

	editor.new_course("Whoop box")
	results.append(TestResult.new(
		"a new course is created and becomes the one being edited",
		editor.course().course_name == "Whoop box"
			and editor.library.selected_id == editor.course().course_id,
		"editing \"%s\"" % editor.course().course_name
	))

	editor.rename_course("Back garden")
	results.append(TestResult.new(
		"renaming keeps the id, so nothing that pointed at the course is orphaned",
		editor.course().course_name == "Back garden"
			and editor.course().course_id == "whoop_box",
		"\"%s\" is still id \"%s\"" % [editor.course().course_name, editor.course().course_id]
	))

	results.append(TestResult.new(
		"the default circuit is still there to go back to",
		editor.choose_course(GateCourse.DEFAULT_ID)
			and editor.course().course_id == GateCourse.DEFAULT_ID,
		"switched to \"%s\"" % editor.course().course_id
	))

	editor.choose_course("whoop_box")
	editor.delete_course()
	results.append(TestResult.new(
		"deleting a course leaves you editing one that still exists",
		not editor.library.has("whoop_box") and editor.course() != null,
		"now editing \"%s\"" % editor.course().course_id
	))

	editor.free()
	return results


# ---------------------------------------------------------------------------
# Lab writes; Sim reads
# ---------------------------------------------------------------------------

static func _it_writes_what_sim_flies() -> Array:
	var results: Array = []
	var editor := _editor()

	editor.new_course("Sprint")
	editor.select_gate(0)
	editor.set_gate_ground_position(Vector3(-60.0, 0.0, 25.0))
	editor.set_gate_height_m(5.0)

	# Every edit is written straight through, for the same reason a tweak is: there is no exit to
	# save on — Lothal is closed by closing the window.
	var from_disk := CourseLibrary.load_from(LIBRARY_PATH)
	var reloaded := from_disk.course("sprint")
	results.append(TestResult.new(
		"every edit is on disk immediately — there is no exit to save on",
		reloaded != null and reloaded.gates[0]["position"].distance_to(Vector3(-60.0, 5.0, 25.0)) < 1.0e-6,
		"gate 1 on disk at %s" % ["nowhere" if reloaded == null else str(reloaded.gates[0]["position"])]
	))

	results.append(TestResult.new(
		"the course Sim would open is the one that was just edited",
		from_disk.selected_id == "sprint"
			and from_disk.selected().fingerprint() == editor.course().fingerprint(),
		"Sim would open \"%s\"" % from_disk.selected_id
	))

	# And a best lap set on the course BEFORE the edit is not sitting there afterwards claiming to
	# be a record on the course that now exists. This is the hazard the editor creates, checked at
	# the point the editor creates it.
	var before_edit := editor.course().fingerprint()
	editor.set_gate_height_m(9.0)
	results.append(TestResult.new(
		"moving a gate in the editor retires the record set on the old layout",
		editor.course().fingerprint() != before_edit,
		"fingerprint went from %s to %s" % [before_edit, editor.course().fingerprint()]
	))

	editor.free()
	return results


# ---------------------------------------------------------------------------
# Where the course IS — elevation, temperature, and the air they imply
# ---------------------------------------------------------------------------

## Air is a property of the world, so it is authored here beside the gates (labs-and-sim.md §1).
## What is worth asserting is the same set of things the gates get: that it is written straight
## through to disk, that it belongs to the WORLD rather than to the editor, and that the readout
## the builder judges by is the derivation the physics runs on rather than a second copy of it.
##
## SINCE F1 THE ELEVATION LIVES ON THE SITE, not on the course, and the checks below moved with it
## rather than being relaxed. "A second course has its own field" is the same property it always
## was — it just reads the site the course points at instead of a block on the course — and it is
## still the check that would catch air being kept in one app-wide setting on the screen.
static func _the_field_itself() -> Array:
	var results: Array = []
	var editor := _editor()

	results.append(TestResult.new(
		"a fresh course opens at standard sea-level air",
		editor.air().is_standard(),
		"%.4f kg/m3 at %.0f m, %.0f C" % [editor.air().kgm3(),
			editor.air().elevation_m, editor.air().temperature_c]))

	editor.set_field_elevation_m(920.0)
	editor.set_field_temperature_c(35.0)

	var expected := AirDensity.new(920.0, 35.0).kgm3()
	results.append(TestResult.new(
		"typing an elevation and a temperature derives the density the physics uses",
		absf(editor.air().kgm3() - expected) < 1.0e-12,
		"%.4f kg/m3, %.1f%% below standard" % [
			editor.air().kgm3(), editor.air().fraction_below_standard() * 100.0]))

	# The readout is what the builder judges by, and it has to be the SAME number — a panel that
	# formatted its own estimate would be a second source of truth for the one quantity this whole
	# screen exists to communicate.
	results.append(TestResult.new(
		"the readout quotes the derived density, not a second copy of it",
		editor._air_readout.text.contains("%.3f" % expected)
			and editor._air_readout.text.contains("16.2%"),
		"readout says: %s" % editor._air_readout.text))

	# Written through immediately, like every other edit here — there is no exit to save on.
	# RE-POINTED IN F2, AND IT NOW READS TWO FILES BECAUSE THE NUMBER LIVES IN TWO FILES. The
	# elevation is a fact about the place and is on the site; the temperature is a fact about the
	# day and is on the selected conditions. Composing them off disk is also a SECOND opinion — it
	# never asks the editor what it thinks it wrote.
	var from_disk := CourseLibrary.load_from(LIBRARY_PATH)
	var site_on_disk := SiteLibrary.load_from(SITES_PATH).site(from_disk.selected().site_id)
	var weather_on_disk := ConditionsLibrary.load_from(CONDITIONS_PATH).selected()
	var disk_air := AirDensity.compose(site_on_disk, weather_on_disk)
	results.append(TestResult.new(
		"the field is on disk immediately",
		site_on_disk != null and weather_on_disk != null
			and absf(disk_air.kgm3() - expected) < 1.0e-12,
		"nowhere on disk" if site_on_disk == null else "%.4f m, %.1f C on disk" % [
			disk_air.elevation_m, disk_air.temperature_c]))
	results.append(TestResult.new(
		"and the temperature is on the conditions rather than parked on the site",
		site_on_disk != null and site_on_disk.parked_temperature_c == null
			and weather_on_disk != null and absf(weather_on_disk.temperature_c - 35.0) < 1.0e-9,
		"site slot %s, weather \"%s\" at %.1f C" % [
			"nowhere" if site_on_disk == null else str(site_on_disk.parked_temperature_c),
			"none" if weather_on_disk == null else weather_on_disk.conditions_name,
			-999.0 if weather_on_disk == null else weather_on_disk.temperature_c]))

	# AND AN EDIT THAT IS NOT ABOUT THE WEATHER DOES NOT WRITE THE WEATHER FILE. Dragging a gate
	# rewriting `conditions.json` is not cosmetic: on a fresh install the first drag materialises a
	# file holding a `Standard` row nobody authored, and `RoomHost._init` refuses exactly that on
	# the way in. Bytes AND stamp, because the document would come back identical — the act is what
	# is being forbidden, not the content.
	# Re-indented first, for the reason `tests/test_conditions.gd` §4 spells out: an mtime has
	# one-second resolution and a save landing inside the same second leaves it alone, while the
	# bytes of a document that round-trips are identical either way. Written in a form the app's
	# own writer does not emit, any save at all normalises it and the bytes say so.
	var weather_document := JsonStore.read_document(CONDITIONS_PATH)
	var weather_handle := FileAccess.open(CONDITIONS_PATH, FileAccess.WRITE)
	weather_handle.store_string(JSON.stringify(weather_document, "\t"))
	weather_handle.close()
	var weather_bytes := FileAccess.get_file_as_string(CONDITIONS_PATH)
	var weather_stamp := FileAccess.get_modified_time(CONDITIONS_PATH)
	editor.select_gate(1)
	editor.set_gate_height_m(2.5)
	editor.rename_course("Bando, renamed")
	editor.set_field_elevation_m(920.0)
	results.append(TestResult.new(
		"moving a gate, renaming a course and nudging the elevation do not write conditions.json",
		FileAccess.get_file_as_string(CONDITIONS_PATH) == weather_bytes
			and FileAccess.get_modified_time(CONDITIONS_PATH) == weather_stamp,
		"%s, stamp %s" % [
			"untouched" if FileAccess.get_file_as_string(CONDITIONS_PATH) == weather_bytes
				else "REWRITTEN",
			"unmoved" if FileAccess.get_modified_time(CONDITIONS_PATH) == weather_stamp
				else "MOVED"]))

	# THE FIELD BELONGS TO THE WORLD, NOT TO THE EDITOR. This is the check that would catch air
	# being stored on the screen or in a single app-wide setting: a second course must have its own
	# field, and switching back must bring the first one's back with it.
	# RE-POINTED IN F2: A COURSE HAS ITS OWN ELEVATION, AND THE TEMPERATURE IS NOT ITS OWN.
	#
	# This check used to demand that a new course read as standard on BOTH halves, and half of that
	# was never a fact about the course. Where a field sits above sea level belongs to the place;
	# how warm it is is the question you are asking, and it stays put when you open a different
	# route (design §3.1). So a new course is at sea level, still in the 35 C the builder chose —
	# and the property this check exists for, "the field is not one app-wide setting on the
	# screen", is still asked below on the half that carries it.
	editor.new_course("Sea level bando")
	var sea_level_hot := AirDensity.new(0.0, 35.0).kgm3()
	results.append(TestResult.new(
		"a new course has its own elevation and does not inherit the last one's",
		absf(editor.air().elevation_m) < 1.0e-9
			and absf(editor.air().kgm3() - sea_level_hot) < 1.0e-12,
		"%.4f kg/m3 at %.0f m, %.0f C" % [editor.air().kgm3(),
			editor.air().elevation_m, editor.air().temperature_c]))
	results.append(TestResult.new(
		"and the temperature stayed, because the weather is not a property of the route",
		absf(editor.air().temperature_c - 35.0) < 1.0e-9
			and absf(sea_level_hot - AirDensity.standard_kgm3()) > 0.05,
		"%.1f C, %.4f kg/m3 against %.4f at 15 C" % [
			editor.air().temperature_c, sea_level_hot, AirDensity.standard_kgm3()]))
	results.append(TestResult.new(
		"and the readout followed the course rather than staying on the old numbers",
		editor._air_readout.text.contains("%.3f" % sea_level_hot),
		"readout says: %s" % editor._air_readout.text))

	# AND THE SECOND COURSE IS GIVEN A DIFFERENT FIELD BEFORE SWITCHING BACK. Without this line the
	# section passes against an implementation that keeps ONE app-wide air on the editor — measured,
	# it did — because a freshly created course reads as standard under both designs and nothing
	# else ever writes the second course. Two courses with two different fields, both surviving a
	# switch, is the only arrangement the two designs disagree about.
	editor.set_field_elevation_m(1610.0)
	editor.set_field_temperature_c(30.0)
	var denver := AirDensity.new(1610.0, 30.0).kgm3()
	# The temperature is now global, so the first course is at 920 m in the SAME 30 C — which is
	# what makes the pair below a test of the elevation belonging to the course rather than of two
	# numbers moving together.
	var first_again := AirDensity.new(920.0, 30.0).kgm3()

	editor.choose_course("default_circuit")
	results.append(TestResult.new(
		"switching back brings the first course's field back with it",
		absf(editor.air().kgm3() - first_again) < 1.0e-12,
		"%.0f m, %.0f C" % [editor.air().elevation_m, editor.air().temperature_c]))

	editor.choose_course("sea_level_bando")
	results.append(TestResult.new(
		"and the second course kept its own, so the two fields are not one shared setting",
		absf(editor.air().kgm3() - denver) < 1.0e-12
			and absf(denver - first_again) > 0.01,
		"course A %.4f kg/m3, course B %.4f kg/m3" % [first_again, editor.air().kgm3()]))
	editor.choose_course("default_circuit")

	# The domain guard, driven the way a hand-written caller would drive it rather than through a
	# SpinBox that would have clamped first. NaN on the stats panel is the failure being prevented.
	editor.set_field_elevation_m(1.0e9)
	results.append(TestResult.new(
		"an absurd elevation is clamped rather than turning the whole readout into NaN",
		not is_nan(editor.air().kgm3()) and editor.air().kgm3() > 0.0,
		"%.4f kg/m3 at %.0f m" % [editor.air().kgm3(), editor.air().elevation_m]))

	editor.free()

	results.append_array(_the_garage_follows_the_field())
	return results


## The half of this that a builder actually notices: change the field, walk back to the garage, and
## the five derived stats are for the place you are going to fly.
##
## Through the shell rather than through the editor alone, because the wiring IS the feature here.
## Lab holds its own air and the shell keeps it in step; a test that only checked the editor's
## model would pass against a build where the two rooms never spoke.
static func _the_garage_follows_the_field() -> Array:
	var results: Array = []

	# AppShell owns the REAL library, so this section edits `user://courses.json` — the builder's
	# own courses. Everything below puts it back. A test that quietly left somebody's home field at
	# 3500 m would be a worse bug than any it could catch, and it would also poison every later
	# suite that reads the default circuit.
	var real_path := CourseLibrary.SAVE_PATH
	var real_sites := SiteLibrary.SAVE_PATH
	var had_file := FileAccess.file_exists(real_path)
	var had_sites := FileAccess.file_exists(real_sites)
	var saved_contents := FileAccess.get_file_as_string(real_path) if had_file else ""
	var saved_sites := FileAccess.get_file_as_string(real_sites) if had_sites else ""
	# AND THE THIRD FILE, since F2: switching the temperature selects a set of conditions, which
	# this room writes to `user://conditions.json`. A restore that forgot it would leave somebody's
	# weather on a 30 C afternoon for ever.
	var real_weather := ConditionsLibrary.SAVE_PATH
	var had_weather := FileAccess.file_exists(real_weather)
	var saved_weather := FileAccess.get_file_as_string(real_weather) if had_weather else ""

	var shell := AppShell.new()

	var before := shell.lab.current_build().thrust_to_weight()
	shell.show_field_editor()
	shell.field_editor.set_field_elevation_m(3500.0)
	shell.field_editor.set_field_temperature_c(30.0)
	shell.show_lab()
	var after := shell.lab.current_build().thrust_to_weight()

	var expected := Build.from_ids(shell.lab.catalog,
		shell.lab.selection()["frame"], shell.lab.selection()["motor"],
		shell.lab.selection()["propeller"], shell.lab.selection()["battery"],
		shell.lab.selection()["esc"], shell.lab.selection()["flight_controller"],
		{}, AirDensity.new(3500.0, 30.0)).thrust_to_weight()

	results.append(TestResult.new(
		"editing the field moves the garage's thrust-to-weight to the field's own figure",
		absf(after - expected) < 0.01 and absf(after - before) > 0.5,
		"%.2f:1 at sea level, %.2f:1 at 3500 m (expected %.2f:1)" % [before, after, expected]))

	# And the build that walks through the door into Sim is the one quoted in the garage, or the
	# field would fly an aircraft the readout never described.
	#
	# THE RIGHT-HAND SIDE IS READ OFF DISK, not asked of `rooms.air_of_selected_course()`. Asking
	# that function is asking the very call RoomHost used to SET `lab.air`, so the two sides agree
	# by construction: it would still catch a stale copy and could no longer catch a wrong
	# derivation inside the function — a check that had quietly stopped being able to fail for half
	# of what it is for. Going to the file and composing the air independently gives it back a
	# second opinion.
	var on_disk := SiteLibrary.load_from(SiteLibrary.SAVE_PATH)
	var flown_site := on_disk.site(
		CourseLibrary.load_from(CourseLibrary.SAVE_PATH).selected().site_id)
	# RE-POINTED IN F2: the temperature is no longer parked on the site, it is on the selected
	# conditions. Both halves are still read off DISK and composed here, which is what keeps this a
	# second opinion rather than a call to the function that set the value.
	var weather_on_disk := ConditionsLibrary.load_from(ConditionsLibrary.SAVE_PATH).selected()
	var independent := (AirDensity.compose(flown_site, weather_on_disk).kgm3()
		if flown_site != null else -1.0)
	results.append(TestResult.new(
		"and the build handed to Sim carries the same air",
		flown_site != null
			and absf(shell.lab.current_build().air.kgm3() - independent) < 1.0e-12,
		"garage %.4f kg/m3, the site on disk %.4f kg/m3" % [
			shell.lab.current_build().air.kgm3(), independent]))

	shell.free()

	if had_file:
		var restore := FileAccess.open(real_path, FileAccess.WRITE)
		restore.store_string(saved_contents)
		restore.close()
	else:
		DirAccess.remove_absolute(real_path)
	# The elevation moved to sites.json in F1, so this section now edits TWO of the builder's files
	# and has to put both back. A restore that forgot the second would leave somebody's home field
	# at 3500 m — the bug the paragraph above calls worse than anything this could catch.
	if had_sites:
		var restore_sites := FileAccess.open(real_sites, FileAccess.WRITE)
		restore_sites.store_string(saved_sites)
		restore_sites.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(real_sites))
	if had_weather:
		var restore_weather := FileAccess.open(real_weather, FileAccess.WRITE)
		restore_weather.store_string(saved_weather)
		restore_weather.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(real_weather))

	results.append(TestResult.new(
		"and the builder's own courses are put back the way they were found",
		FileAccess.file_exists(real_path) == had_file
			and (not had_file or FileAccess.get_file_as_string(real_path) == saved_contents),
		"%s on the way in, %s on the way out" % [
			"a file" if had_file else "no file",
			"a file" if FileAccess.file_exists(real_path) else "no file"]))
	results.append(TestResult.new(
		"and so are their sites",
		FileAccess.file_exists(real_sites) == had_sites
			and (not had_sites or FileAccess.get_file_as_string(real_sites) == saved_sites),
		"%s on the way in, %s on the way out" % [
			"a file" if had_sites else "no file",
			"a file" if FileAccess.file_exists(real_sites) else "no file"]))
	return results


# ---------------------------------------------------------------------------
# Laying out gates turns no motors
# ---------------------------------------------------------------------------

static func _it_costs_nothing() -> Array:
	var results: Array = []

	# labs-and-sim.md §5: a bench run costs charge because a motor is drawing current. Nothing
	# turns in the field editor, so nothing may be invented to charge for it. Checked through the
	# shell, which is the thing that would have to save a changed pack on the way out.
	var shell := AppShell.new()
	var pack_id: String = shell.lab.selection()["battery"]
	var before := shell.pack_charge.used_mah(pack_id)

	shell.show_field_editor()
	var editor: FieldEditorScreen = shell.field_editor
	editor.select_gate(1)
	editor.set_gate_height_m(7.0)
	editor.add_gate()
	shell.show_lab()

	results.append(TestResult.new(
		"laying out gates costs no charge — no motor turned",
		absf(shell.pack_charge.used_mah(pack_id) - before) < 1.0e-9
			and not shell.pack_charge.has_unsaved_changes(),
		"pack drew %.4f mAh before, %.4f after" % [before, shell.pack_charge.used_mah(pack_id)]
	))

	results.append(TestResult.new(
		"the field editor is a room, and it is gone when you leave it",
		shell.field_editor == null and shell.showing_lab(),
		"field editor is %s" % ("gone" if shell.field_editor == null else "still here")
	))

	shell.free()
	return results
