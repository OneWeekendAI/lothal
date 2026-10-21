class_name TestDrawnFramePersists
extends RefCounted
## A drawn airframe is part of the saved drone (`Project.airframe`): it round-trips through the
## `.lothal` container, an old file without one opens as the catalogue frame it always was, and the
## projects list weighs the drawing rather than the catalogue frame the rail names.
##
## Each check was run against the code with its fix taken out, and failed:
## - the round trip, without `decisions.airframe` being written (nothing comes back) and without
##   `to_build` flying the drawing (the reopened drone weighs the catalogue frame);
## - the shell round trip, without `apply_project` handing the drawing to Lab (the room reopens on
##   the generated catalogue document);
## - old-file compatibility, with `set_drawn_frame` only acting on a non-empty drawing (the previous
##   drone's drawing leaks onto an old file on the same catalogue frame), and with `drawn_frame`
##   returning the generated document (an untouched drone saves a drawing nobody made);
## - the list row, without `to_build` flying the drawing (the row weighs 110 g of carbon).
##
## The drawing used is a generated Quad X with 75 mm arms, 12x12 motors and a 20x20 stack: a
## different frame from the rail's 5" freestyle (id, arm, mass and drilling), so no check can pass on the catalogue's numbers.

const TEST_DIR := "user://test_drawn_frame"


static func run() -> Array:
	var results: Array = []
	_clean(TEST_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
	var catalog := PartsCatalog.load_default()

	results.append_array(_a_replacement_flies_as_drawn(catalog))
	results.append_array(_the_drawing_survives_save_and_open(catalog))
	results.append_array(_the_shell_saves_and_reopens_the_drawing())
	results.append_array(_an_old_file_opens_as_the_catalogue_frame(catalog))
	results.append_array(_the_list_row_weighs_the_drawing(catalog))

	_clean(TEST_DIR)
	return results


## A fixed id: `FrameEdits.new_frame` stamps the clock, and every check compares ids.
static func _drawing() -> AirframeDocument:
	var document := FrameLayouts.build("quad_x",
		{"arm_length_mm": 75.0, "motor_pitch_mm": 12.0, "stack_pitch_mm": 20.0})
	document.id = "test_drawn_quad_x"
	return document


static func _drawn_project(name: String) -> Project:
	var project := ProjectLibrary.starting_project(name)
	project.airframe = _drawing().to_dictionary()
	return project


static func _components(project: Project) -> Dictionary:
	var out := {}
	for category in Build.OPTIONAL_COMPONENTS:
		out[category] = String(project.parts.get(category, ""))
	return out


static func _dry_g(build: Build) -> float:
	return build.all_up_weight_g() - float(build.battery.get("mass_g", 0.0))


# ---------------------------------------------------------------------------

## The one-source rule at its root: a frame that is not the fitted one flies on its own numbers.
static func _a_replacement_flies_as_drawn(catalog: PartsCatalog) -> Array:
	var frame := catalog.get_part(ReferenceBuild.FRAME_ID)
	var drawing := _drawing()
	var measured := FittedFrame.drawn(drawing)
	var flown := FittedFrame.apply(frame, FittedFrame.edit_of(frame, drawing, FittedFrame.baseline(frame)))
	var specs: Dictionary = flown.get("specs", {})
	return [
		TestResult.new("drawn frame: a different frame flies its own drawn mass and arm, not weighed + delta",
			absf(float(flown["mass_g"]) - float(measured["mass_g"])) < 1e-6
				and absf(float(specs["arm_mm"]) - 75.0) < 1e-3,
			"flown %.2f g / %.2f mm, drawn %.2f g" % [float(flown["mass_g"]),
				float(specs["arm_mm"]), float(measured["mass_g"])]),
		TestResult.new("drawn frame: its name, clearance and drilling come off the drawing, not the catalogue",
			str(flown["name"]) == drawing.name
				and absf(float(specs["max_prop_inches"]) - 75.0 * sqrt(2.0) / 25.4) < 1e-3
				and str(specs["motor_mount"]) == "12x12" and str(specs["stack_mount"]) == "20x20",
			"name \"%s\", specs %s" % [flown["name"], specs]),
	]


static func _the_drawing_survives_save_and_open(catalog: PartsCatalog) -> Array:
	var project := _drawn_project("Drawn")
	var path := "%s/drawn.%s" % [TEST_DIR, ProjectContainer.EXTENSION]
	var wrote := ProjectContainer.make(project).write(path)
	var reopened := ProjectContainer.open(path)
	var doc := reopened.project.airframe_document() if reopened != null else null
	var drawn_g := float(FittedFrame.drawn(_drawing())["mass_g"])
	var build: Build = reopened.project.to_build(catalog) if reopened != null else null
	return [
		TestResult.new("drawn frame: a saved drone's drawing is in the file and comes back whole",
			wrote and doc != null and doc.id == project.airframe["id"]
				and doc.plates.size() == _drawing().plates.size()
				and absf(float(FittedFrame.drawn(doc)["mass_g"]) - drawn_g) < 1e-3,
			"wrote %s, reopened %s" % [wrote, "(none)" if doc == null else "%s, %d plates, %.3f g" % [
				doc.id, doc.plates.size(), float(FittedFrame.drawn(doc)["mass_g"])]]),
		TestResult.new("drawn frame: the reopened drone flies the drawing's mass",
			build != null and absf(float(build.frame["mass_g"]) - drawn_g) < 1e-3,
			"frame %.3f g, drawn %.3f g" % [float(build.frame["mass_g"]) if build != null else -1.0,
				drawn_g]),
	]


## Through the shell's own save and open path: `_sync_project` writes what Lab holds, and
## `apply_project` (what `open_project` calls) puts it back in the room and on the aircraft.
static func _the_shell_saves_and_reopens_the_drawing() -> Array:
	var results: Array = []
	var shell := GlassShell.new()
	_open(shell, ProjectLibrary.starting_project("Shell drawn"))
	shell._sync_project()
	results.append(TestResult.new(
		"drawn frame: an untouched drone saves no drawing (the catalogue frame keeps flying)",
		shell.container.project.airframe.is_empty(),
		"saved %d keys" % shell.container.project.airframe.size()))

	var drawing := _drawing()
	shell._on_frame_edited(drawing)
	shell._sync_project()
	var path := "%s/shell.%s" % [TEST_DIR, ProjectContainer.EXTENSION]
	shell.container.write(path)
	var drawn_g := float(FittedFrame.drawn(drawing)["mass_g"])

	# A fresh shell, so nothing the first one held can answer for the file.
	shell.free()
	var again := GlassShell.new()
	var opened := ProjectContainer.open(path)
	_open(again, opened.project)
	var doc := again.lab.frame_document
	var build := again.lab.current_build()
	results.append(TestResult.new(
		"drawn frame: reopening the drone puts the drawing back in the Airframe room and on the aircraft",
		doc != null and doc.id == drawing.id
			and absf(float(build.frame["mass_g"]) - drawn_g) < 1e-3,
		"room %s, flown %.2f g, drawn %.2f g" % ["(none)" if doc == null else doc.id,
			float(build.frame["mass_g"]), drawn_g]))
	again.free()
	return results


static func _an_old_file_opens_as_the_catalogue_frame(catalog: PartsCatalog) -> Array:
	var results: Array = []
	# What a minor-2 Lothal wrote: no `airframe` block at all.
	var document := ProjectLibrary.starting_project("Old").to_dict()
	(document["decisions"] as Dictionary).erase("airframe")
	document["schema"] = {"major": 1, "minor": 2}
	var old := Project.from_dict(JSON.parse_string(JSON.stringify(document)))
	var catalogue_only := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID, _components(old))
	var build := old.to_build(catalog)
	results.append(TestResult.new(
		"drawn frame: an old file has no drawing and weighs exactly what it did",
		old.airframe.is_empty() and old.load_warnings.is_empty()
			and build.all_up_weight_g() == catalogue_only.all_up_weight_g()
			and float(build.frame["mass_g"]) == 110.0,
		"airframe %d keys, warnings %s, %.4f vs %.4f g" % [old.airframe.size(), old.load_warnings,
			build.all_up_weight_g(), catalogue_only.all_up_weight_g()]))

	# Opened in a shell that just had a DRAWN drone on the same catalogue frame: the old file must
	# not inherit that drawing.
	var shell := GlassShell.new()
	_open(shell, _drawn_project("Before"))
	var before := shell.lab.frame_document.id if shell.lab.frame_document != null else ""
	_open(shell, old)
	var after := shell.lab.frame_document
	var flown := shell.lab.current_build()
	shell._sync_project()
	results.append(TestResult.new(
		"drawn frame: an old file opened after a drawn drone gets the catalogue frame, not the drawing",
		before == _drawing().id and after != null and after.id == ReferenceBuild.FRAME_ID
			and float(flown.frame["mass_g"]) == 110.0
			and shell.container.project.airframe.is_empty(),
		"before %s, after %s, flown %.2f g, saved %d keys" % [before,
			"(none)" if after == null else after.id, float(flown.frame["mass_g"]),
			shell.container.project.airframe.size()]))
	shell.free()
	return results


## The projects table (PROP / DRY / AUW): a row reads the file through `ProjectsScreen.list_builds`.
static func _the_list_row_weighs_the_drawing(catalog: PartsCatalog) -> Array:
	ProjectLibrary.ensure_dir()
	var drawn := _drawn_project("Listed drawn")
	var plain := ProjectLibrary.starting_project("Listed plain")
	var drawn_path := ProjectLibrary.path_for(drawn)
	var plain_path := ProjectLibrary.path_for(plain)
	ProjectContainer.make(drawn).write(drawn_path)
	ProjectContainer.make(plain).write(plain_path)

	var rows := {}
	for entry in ProjectsScreen.list_builds(catalog):
		rows[str(entry["path"])] = entry
	DirAccess.remove_absolute(ProjectSettings.globalize_path(drawn_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(plain_path))

	var drawn_row: Dictionary = rows.get(drawn_path, {})
	var plain_row: Dictionary = rows.get(plain_path, {})
	var expected := drawn.to_build(catalog)
	# Independent of `to_build`: the drawing's own weight, measured off the document.
	var drawn_frame_g := float(FittedFrame.drawn(_drawing())["mass_g"])
	var ok := not drawn_row.is_empty() and not plain_row.is_empty() \
		and absf(float(drawn_row["dry_g"]) - _dry_g(expected)) < 1e-6 \
		and absf(float(expected.frame["mass_g"]) - drawn_frame_g) < 1e-3 \
		and float(plain_row["dry_g"]) - float(drawn_row["dry_g"]) > 110.0 - drawn_frame_g - 1.0
	return [TestResult.new(
		"drawn frame: the projects list row weighs the drawn frame (DRY / AUW), not the catalogue's",
		ok,
		"drawn row %s, plain row %s, drawn frame %.2f g" % [
			drawn_row.get("dry_g", "(missing)"), plain_row.get("dry_g", "(missing)"), drawn_frame_g])]


## What `open_project` does once the file is read, minus the settings and the chip: the container
## becomes the shell's and `apply_project` fits it.
static func _open(shell: GlassShell, project: Project) -> void:
	shell.container = ProjectContainer.make(project)
	shell.apply_project(project)


static func _clean(dir: String) -> void:
	var absolute := ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	for file in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute(absolute.path_join(file))
	DirAccess.remove_absolute(absolute)
