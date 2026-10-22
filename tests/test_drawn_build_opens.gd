class_name TestDrawnBuildOpens
extends RefCounted
## A saved build with a drawn frame, opened THE APP'S WAY: a shell in a tree (so `_ready` has run
## and the rails' `part_selected` is wired to `_refresh_status`), already showing a drone on the same
## catalogue frame, then `open_project` on the file. What it checks is what the builder reads: the
## top bar's Dry, the Airframe rows, the 3D frame, the aircraft Sim flies, and the file after an
## autosave.
##
## WHY THIS SUITE EXISTS. `TestDrawnFramePersists` drove `apply_project` on a shell that was never in
## a tree, so `_ready` never connected the rails, `_sync_project` never ran mid-open, and the model
## API passed while the app opened every drawn build on the catalogue 5" frame — and its next autosave
## wrote `"airframe": {}` over the file. Frames are needed for the wiring, so this runs beside the
## laid-out suite rather than in the synchronous list.
##
## Each check was run with its fix taken out, and failed:
## - every check, with `apply_project` reading `project.airframe` AFTER `apply_selection` (the
##   original defect: the rails' `_sync_project` had already replaced it with the previous drone's
##   `{}`), the autosave check included — the file came back with no drawing;
## - the Frame and Arms rows, with `FittedFrame._replacement_edit` carrying no `catalog` block (the
##   rows read "5\" · 150 mm" and "carbon fibre 3K" about a PA12 drawing);
## - the 3D check, with `AirframeModel.draws` matching on the part id alone (the drawing was drawn as a
##   generic plate from the 5" rail's specs);
## - the Sim check, without `RoomHost.show_sim` handing the document across (the field drew the
##   generic plate too).

const TEST_DIR := "user://test_drawn_build_opens"
const SETTLE_FRAMES := 3
const WINDOW := Vector2i(1280, 720)
const MATERIAL_ID := "pa12_sls"


static func run(tree: SceneTree) -> Array:
	var results: Array = []
	var previous_settings: Variant = _read(AppSettings.SAVE_PATH)
	ProjectLibrary.ensure_dir()
	var builds_before := _lothal_files()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
	var catalog := PartsCatalog.load_default()

	var drawing := _drawing()
	var project := ProjectLibrary.starting_project("Drawn on open")
	project.airframe = drawing.to_dictionary()
	var path := "%s/drawn.%s" % [TEST_DIR, ProjectContainer.EXTENSION]
	var wrote := ProjectContainer.make(project).write(path)

	# The shell boots on a drone of its own (resumed or adopted) on the catalogue 5" frame, which is
	# the state the builder opens a saved drone from.
	var frame := SubViewport.new()
	frame.size = WINDOW
	tree.root.add_child(frame)
	var shell := GlassShell.new()
	frame.add_child(shell)
	for i in SETTLE_FRAMES:
		await tree.process_frame
	if wrote:
		shell.open_project(path)
	shell.select_system_by_name("Airframe")
	for i in SETTLE_FRAMES:
		await tree.process_frame

	var drawn_g := float(FittedFrame.drawn(drawing)["mass_g"])
	var plain := Project.from_dict(JSON.parse_string(JSON.stringify(project.to_dict())))
	plain.airframe = {}
	results.append(_the_header_weighs_the_drawing(shell, project.to_build(catalog),
		plain.to_build(catalog)))
	results.append(_the_frame_row_is_the_drawing(shell, drawing, drawn_g))
	results.append(_the_arms_row_is_the_drawings_material(shell))
	results.append(_the_layout_and_straps_rows_read_the_drawing(shell))
	results.append(_the_3d_frame_is_the_drawing(shell, drawing))

	# Autosave, the way the timer does it: the drawing must still be in the file afterwards.
	shell._on_autosave_tick()
	var reopened := ProjectContainer.open(path)
	results.append(TestResult.new(
		"drawn build on open: an autosave after opening keeps the drawing in the file",
		reopened != null and reopened.project.airframe_document() != null
			and reopened.project.airframe_document().id == drawing.id,
		"file airframe: %s" % ("(unreadable)" if reopened == null else
			"%d keys, id %s" % [reopened.project.airframe.size(),
				str(reopened.project.airframe.get("id", "(none)"))])))

	# Out to the field: the aircraft Sim flies and draws.
	shell.rooms.show_sim()
	for i in SETTLE_FRAMES:
		await tree.process_frame
	results.append(_sim_flies_and_draws_the_drawing(shell, drawing, drawn_g))

	frame.queue_free()
	for i in SETTLE_FRAMES:
		await tree.process_frame
	_clean(TEST_DIR)
	var absolute := ProjectSettings.globalize_path(ProjectLibrary.DIR)
	for file in _lothal_files():
		if not builds_before.has(file):
			DirAccess.remove_absolute(absolute.path_join(file))
	_restore(AppSettings.SAVE_PATH, previous_settings)
	return results


## A 3" quad X in PA12 with 12x12 motors and a 20x20 stack: different from the 5" freestyle rail in
## id, arm, mass, material, drilling and strap slots, so no check can pass on the catalogue's numbers.
static func _drawing() -> AirframeDocument:
	var document := FrameLayouts.build("quad_x", {"arm_length_mm": 75.0, "motor_pitch_mm": 12.0,
		"stack_pitch_mm": 20.0, "material_id": MATERIAL_ID})
	document.id = "test_drawn_on_open"
	document.name = "Drawn on open 3in"
	return document


static func _dry_g(build: Build) -> float:
	return build.all_up_weight_g() - float(build.battery.get("mass_g", 0.0))


static func _the_header_weighs_the_drawing(shell: GlassShell, drawn: Build, catalogue: Build) -> TestResult:
	var text := shell.build_stats_text()
	var regex := RegEx.create_from_string("Dry (\\d+) g")
	var found := regex.search(text)
	var dry := float(found.get_string(1)) if found != null else -1.0
	return TestResult.new(
		"drawn build on open: the top bar's Dry is the drawn frame's aircraft, not the catalogue's",
		absf(dry - _dry_g(drawn)) <= 1.0 and absf(dry - _dry_g(catalogue)) > 5.0,
		"header \"%s\"; drawn build %.1f g, catalogue build %.1f g" % [text, _dry_g(drawn),
			_dry_g(catalogue)])


static func _lines(shell: GlassShell, id: StringName) -> PackedStringArray:
	return shell.section_list().row_lines(id)


static func _the_frame_row_is_the_drawing(shell: GlassShell, drawing: AirframeDocument,
		drawn_g: float) -> TestResult:
	var lines := _lines(shell, &"frame")
	return TestResult.new(
		"drawn build on open: the Frame row names the drawing and its drawn mass, not 5\" 110 g",
		lines.size() >= 3 and lines[1] == drawing.name and lines[2] == "~%d g" % roundi(drawn_g),
		"row %s, drawn %.1f g" % [lines, drawn_g])


static func _the_arms_row_is_the_drawings_material(shell: GlassShell) -> TestResult:
	var lines := _lines(shell, &"arms")
	var expected := str(AirframePanel.materials().get_material(MATERIAL_ID).get("name", ""))
	return TestResult.new(
		"drawn build on open: the Arms row reads the drawing's material, not carbon fibre",
		expected != "" and lines.size() >= 2 and lines[1] == expected,
		"row %s, expected \"%s\"" % [lines, expected])


static func _the_layout_and_straps_rows_read_the_drawing(shell: GlassShell) -> TestResult:
	var layout := _lines(shell, &"layout")
	var straps := _lines(shell, &"straps")
	return TestResult.new(
		"drawn build on open: Layout reads the drawn 20x20 stack and Straps the drawn slots",
		layout.size() >= 2 and layout[1] == "stack 20x20"
			and straps.size() >= 3 and not " ".join(straps).contains("no strap slots"),
		"layout %s, straps %s" % [layout, straps])


## The flat plates the Lab's 3D aircraft drew, outline for outline, against the drawing's.
static func _the_3d_frame_is_the_drawing(shell: GlassShell, drawing: AirframeDocument) -> TestResult:
	var drawn := _model_outlines(shell.lab.airframe.frame_model)
	var expected := _flat_outlines(drawing)
	return TestResult.new(
		"drawn build on open: the Lab's 3D frame is the drawing's plates",
		not expected.is_empty() and drawn == expected,
		"drew %d flat plates, the drawing has %d; equal outlines: %s" % [drawn.size(),
			expected.size(), drawn == expected])


static func _sim_flies_and_draws_the_drawing(shell: GlassShell, drawing: AirframeDocument,
		drawn_g: float) -> TestResult:
	var sim: Node = shell.rooms.sim
	var build: Build = sim.build if sim != null else null
	var airframe: AirframeModel = sim.airframe if sim != null else null
	var flown := float(build.frame["mass_g"]) if build != null else -1.0
	var drawn := _model_outlines(airframe.frame_model) if airframe != null else []
	var expected := _flat_outlines(drawing)
	return TestResult.new(
		"drawn build on open: Sim flies the drawn frame's mass and draws its plates",
		build != null and absf(flown - drawn_g) < 1e-3 and not expected.is_empty()
			and drawn == expected,
		"sim frame %.2f g (drawn %.2f g); drew %d flat plates, the drawing has %d, equal: %s" % [
			flown, drawn_g, drawn.size(), expected.size(), drawn == expected])


## Outlines as sorted strings, so the comparison is a set of shapes and not a draw order.
static func _model_outlines(model: FrameModel) -> Array:
	var out: Array = []
	for record in model.plate_polygons_m():
		out.append(var_to_str(record["outline_mm"]))
	out.sort()
	return out


static func _flat_outlines(drawing: AirframeDocument) -> Array:
	var out: Array = []
	for plate in drawing.plates:
		if AirframeDocument.is_upright(plate):
			continue
		if PlateMesh.extrude(AirframeDocument.plate_outline(plate),
				AirframeDocument.plate_thickness_mm(plate)) == null:
			continue
		out.append(var_to_str(AirframeDocument.plate_outline(plate)))
	out.sort()
	return out


static func _lothal_files() -> Array:
	var absolute := ProjectSettings.globalize_path(ProjectLibrary.DIR)
	var found: Array = []
	if not DirAccess.dir_exists_absolute(absolute):
		return found
	for file in DirAccess.get_files_at(absolute):
		if file.ends_with(".%s" % ProjectContainer.EXTENSION):
			found.append(file)
	return found


static func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return FileAccess.get_file_as_string(path)


static func _restore(path: String, previous: Variant) -> void:
	if previous == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	var handle := FileAccess.open(path, FileAccess.WRITE)
	handle.store_string(String(previous))
	handle.close()


static func _clean(dir: String) -> void:
	var absolute := ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	for file in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute(absolute.path_join(file))
	DirAccess.remove_absolute(absolute)
