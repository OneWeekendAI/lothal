class_name TestFieldEditor
extends RefCounted
## The garage's field editor: the room where the world gets built (labs-and-sim.md §2.4).
##
## What is worth asserting here is not that the sliders move. It is that the editor is the ONLY
## writer, that what it writes is what Sim later flies, that the renderer follows the model rather
## than keeping a second copy of the gates, and that laying gates out costs nothing — no motor
## turns, so §5's consequence does not apply and nothing may invent one.

const LIBRARY_PATH := "user://test_field_editor_courses.json"


static func run() -> Array:
	var results: Array = []
	results.append_array(_editing_gates())
	results.append_array(_the_renderer_follows())
	results.append_array(_courses())
	results.append_array(_it_writes_what_sim_flies())
	results.append_array(_it_costs_nothing())
	results.append_array(_the_field_itself())
	return results


static func _forget(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _editor() -> FieldEditorScreen:
	_forget(LIBRARY_PATH)
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
## through to disk, that it belongs to a COURSE rather than to the editor, and that the readout
## the builder judges by is the derivation the physics runs on rather than a second copy of it.
static func _the_field_itself() -> Array:
	var results: Array = []
	var editor := _editor()

	results.append(TestResult.new(
		"a fresh course opens at standard sea-level air",
		editor.course().air.is_standard(),
		"%.4f kg/m3 at %.0f m, %.0f C" % [editor.course().air.kgm3(),
			editor.course().air.elevation_m, editor.course().air.temperature_c]))

	editor.set_field_elevation_m(920.0)
	editor.set_field_temperature_c(35.0)

	var expected := AirDensity.new(920.0, 35.0).kgm3()
	results.append(TestResult.new(
		"typing an elevation and a temperature derives the density the physics uses",
		absf(editor.course().air.kgm3() - expected) < 1.0e-12,
		"%.4f kg/m3, %.1f%% below standard" % [
			editor.course().air.kgm3(), editor.course().air.fraction_below_standard() * 100.0]))

	# The readout is what the builder judges by, and it has to be the SAME number — a panel that
	# formatted its own estimate would be a second source of truth for the one quantity this whole
	# screen exists to communicate.
	results.append(TestResult.new(
		"the readout quotes the derived density, not a second copy of it",
		editor._air_readout.text.contains("%.3f" % expected)
			and editor._air_readout.text.contains("16.2%"),
		"readout says: %s" % editor._air_readout.text))

	# Written through immediately, like every other edit here — there is no exit to save on.
	var from_disk := CourseLibrary.load_from(LIBRARY_PATH)
	results.append(TestResult.new(
		"the field is on disk immediately",
		absf(from_disk.selected().air.kgm3() - expected) < 1.0e-12,
		"%.4f m, %.1f C on disk" % [from_disk.selected().air.elevation_m,
			from_disk.selected().air.temperature_c]))

	# THE FIELD BELONGS TO THE COURSE, NOT TO THE EDITOR. This is the check that would catch air
	# being stored on the screen or in a single app-wide setting: a second course must have its own
	# air, and switching back must bring the first one's field back with it.
	editor.new_course("Sea level bando")
	results.append(TestResult.new(
		"a new course has its own field and does not inherit the last one's",
		editor.course().air.is_standard(),
		"%.4f kg/m3" % editor.course().air.kgm3()))
	results.append(TestResult.new(
		"and the readout followed the course rather than staying on the old numbers",
		editor._air_readout.text.contains("standard sea-level air"),
		"readout says: %s" % editor._air_readout.text))

	# AND THE SECOND COURSE IS GIVEN A DIFFERENT FIELD BEFORE SWITCHING BACK. Without this line the
	# section passes against an implementation that keeps ONE app-wide air on the editor — measured,
	# it did — because a freshly created course reads as standard under both designs and nothing
	# else ever writes the second course. Two courses with two different fields, both surviving a
	# switch, is the only arrangement the two designs disagree about.
	editor.set_field_elevation_m(1610.0)
	editor.set_field_temperature_c(30.0)
	var denver := AirDensity.new(1610.0, 30.0).kgm3()

	editor.choose_course("default_circuit")
	results.append(TestResult.new(
		"switching back brings the first course's field back with it",
		absf(editor.course().air.kgm3() - expected) < 1.0e-12,
		"%.0f m, %.0f C" % [editor.course().air.elevation_m, editor.course().air.temperature_c]))

	editor.choose_course("sea_level_bando")
	results.append(TestResult.new(
		"and the second course kept its own, so the two fields are not one shared setting",
		absf(editor.course().air.kgm3() - denver) < 1.0e-12
			and absf(denver - expected) > 0.01,
		"course A %.4f kg/m3, course B %.4f kg/m3" % [expected, editor.course().air.kgm3()]))
	editor.choose_course("default_circuit")

	# The domain guard, driven the way a hand-written caller would drive it rather than through a
	# SpinBox that would have clamped first. NaN on the stats panel is the failure being prevented.
	editor.set_field_elevation_m(1.0e9)
	results.append(TestResult.new(
		"an absurd elevation is clamped rather than turning the whole readout into NaN",
		not is_nan(editor.course().air.kgm3()) and editor.course().air.kgm3() > 0.0,
		"%.4f kg/m3 at %.0f m" % [editor.course().air.kgm3(), editor.course().air.elevation_m]))

	editor.free()
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
