class_name TestPrintedExport
extends RefCounted
## Export every printed part into the drone — printed-room slice PR4
## (plans/2026-09-14-printed-room-plan.md, PR4 checks).
##
## Where each check could pass while proving nothing, and what stops it:
##   - "a record per part" on a build that prints nothing: the reference build lists three, and the
##     check compares against PrintedParts' own exportable rows AND a hard-coded three.
##   - "the record describes the file": the hash is recomputed from the bytes the container holds and
##     from the file on disk, and the clearance is a non-default 0.35 mm, so a record that wrote the
##     default would be caught.
##   - "the record round-trips" without writing a file proves nothing; this writes a real container,
##     reopens it, and hashes the member that came back.
##   - "one refusal refuses only itself" needs a refusing part beside parts that write: the whoop frame
##     refuses the arm guard, and the mounts still write.
##   - every test that exports clears its directory first; a broken refusal once wrote a file that
##     failed every later run (PR1).

const DIR := "user://exports/_test_printed"
const RT_DIR := "user://_test_printed_export"


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	results.append_array(_every_part_writes_and_records())
	results.append(_a_record_round_trips_through_the_file())
	results.append_array(_one_refusal_refuses_only_itself(catalog))
	results.append_array(_the_menu_entry_is_live_and_routes())
	# PR12: the prop-guard branch of the whole-room export, which no fixture reached before.
	results.append_array(_a_fitted_prop_guard_goes_through_the_room_export(catalog))
	return results


static func _every_part_writes_and_records() -> Array:
	_clear_dir(DIR)
	var build := ReferenceBuild.build()
	var printing := {}
	PrintSettings.set_clearance_mm(printing, 0.35)
	build.set_printing(printing)
	var container := ProjectContainer.make(Project.create("Export"))
	var result := PrintedExport.export_all(build, DIR, container)
	var written: Array = result.get("written", [])

	var expected: Array = []
	for row in PrintedParts.for_build(build):
		if bool(row["exportable"]):
			expected.append(String(row["id"]))
	var parts := _parts(written)

	var bad: Array = []
	var disk_matches := written.size() > 0
	for record in written:
		var part := String(record.get("part", ""))
		var bytes := container.member_bytes(String(record.get("file", "")))
		var text := bytes.get_string_from_utf8()
		var sha := text.sha256_text()
		var facets := text.count("facet normal")
		if not String(record.get("file", "")).begins_with("printed/"):
			bad.append("%s file %s" % [part, record.get("file")])
		if bytes.is_empty() or sha != String(record.get("geometry_sha256", "")):
			bad.append("%s hash" % part)
		if String(record.get("generator", "")) != "%s@1" % part:
			bad.append("%s generator %s" % [part, record.get("generator")])
		if not is_equal_approx(float(record.get("clearance_mm", -1.0)), 0.35):
			bad.append("%s clearance %s" % [part, record.get("clearance_mm")])
		if String(record.get("material", "")) != "tpu_95a" or String(record.get("printed_at", "")) == "":
			bad.append("%s material/date" % part)
		if facets == 0 or int(record.get("triangles", -1)) != facets:
			bad.append("%s triangles %s vs %d facets" % [part, record.get("triangles"), facets])
		var bbox: Array = record.get("bbox_mm", [])
		if bbox.size() != 3 or float(bbox[0]) <= 0.0 or float(bbox[1]) <= 0.0 or float(bbox[2]) <= 0.0:
			bad.append("%s bbox %s" % [part, bbox])
		if int(record.get("quantity", 0)) < 1:
			bad.append("%s quantity" % part)
		var on_disk := String(record.get("exported_to", ""))
		if on_disk == "" or not FileAccess.file_exists(on_disk) \
				or FileAccess.get_file_as_string(on_disk).sha256_text() != sha:
			disk_matches = false

	return [
		# Four since PR11: every build fits a pack, so every build lists a battery pad.
		TestResult.new("the reference build exports its four printable parts, and refuses nothing",
			parts == ["arm_guard", "camera_mount", "antenna_mount", "battery_pad"] and parts == expected
				and (result.get("refused", []) as Array).is_empty(),
			"wrote %s, listed %s, refused %s" % [parts, expected, result.get("refused")]),
		TestResult.new("each lands in the drone as printed/… with a record that describes those exact bytes at 0.35 mm",
			written.size() == 4 and bad.is_empty() and container.project.print_records.size() == 4,
			"problems %s; %d records on the project" % [bad, container.project.print_records.size()]),
		TestResult.new("and the STL written to the exports folder is byte-for-byte the one kept in the drone",
			disk_matches, "disk copies match: %s" % disk_matches),
	]


static func _a_record_round_trips_through_the_file() -> TestResult:
	_clear_dir(DIR)
	_clear_dir(RT_DIR)
	var path := RT_DIR + "/round_trip.lothal"
	var container := ProjectContainer.make(Project.create("Round trip"))
	var result := PrintedExport.export_all(ReferenceBuild.build(), DIR, container)
	var wrote := container.write(path, RT_DIR + "/no_custom_parts.json")
	var reopened := ProjectContainer.open(path) if wrote else null
	var problems: Array = []
	var records: Array = result.get("written", [])
	if reopened == null:
		problems.append("did not reopen (wrote %s)" % wrote)
	elif reopened.project.print_records.size() != records.size() or records.is_empty():
		problems.append("%d records back for %d written" % [reopened.project.print_records.size(), records.size()])
	else:
		for i in records.size():
			var a: Dictionary = records[i]
			var b: Dictionary = reopened.project.print_records[i]
			for key in ["part", "file", "generator", "geometry_sha256", "material", "printed_at"]:
				if String(a[key]) != String(b.get(key, "")):
					problems.append("%s.%s" % [a["part"], key])
			if int(a["triangles"]) != int(b.get("triangles", -1)):
				problems.append("%s.triangles" % a["part"])
			if reopened.member_bytes(String(b.get("file", ""))).get_string_from_utf8().sha256_text() != String(a["geometry_sha256"]):
				problems.append("%s member hash" % a["part"])
	_clear_dir(RT_DIR)
	return TestResult.new("the records and their STLs survive writing the .lothal and opening it again",
		problems.is_empty(), "problems %s" % [problems])


static func _one_refusal_refuses_only_itself(catalog: PartsCatalog) -> Array:
	_clear_dir(DIR)
	var build := ReferenceBuild.build()
	build.frame = catalog.get_part("frame_65mm_whoop")
	var container := ProjectContainer.make(Project.create("Whoop"))
	var result := PrintedExport.export_all(build, DIR, container)
	var refused: Array = result.get("refused", [])
	var summary := String(result.get("summary", ""))
	var arm_files := 0
	for f in DirAccess.get_files_at(DIR):
		if String(f).begins_with("arm_guard"):
			arm_files += 1
	return [
		TestResult.new("the whoop's arm guard is refused by name, and the camera mount, antenna mount and battery pad still write",
			refused.size() == 1 and String(refused[0]).begins_with("arm_guard:")
				and String(refused[0]).contains("frame_65mm_whoop")
				and _parts(result.get("written", [])) == ["camera_mount", "antenna_mount", "battery_pad"]
				and container.project.print_records.size() == 3 and arm_files == 0,
			"refused %s, wrote %s, %d arm-guard files" % [refused, _parts(result.get("written", [])), arm_files]),
		TestResult.new("and the summary names both what was written and what was not",
			summary.contains("camera_mount") and summary.contains("antenna_mount")
				and summary.contains("NOT EXPORTED") and summary.contains("arm_guard"),
			"\"%s\"" % summary),
	]


static func _the_menu_entry_is_live_and_routes() -> Array:
	var results: Array = []
	results.append(TestResult.new("Export printed parts… is live in the project menu",
		ProjectMenu.is_live("export_printed"), "live %s" % ProjectMenu.is_live("export_printed")))

	# The tilt edit below ends in tweaks.save(), which writes the REAL user://assembly_tweaks.json.
	var previous: Variant = TestVideoPanel._stash_saved_tweaks()
	var shell := GlassShell.new()
	shell.open_folder_after_export = false
	var project := Project.create("Menu")
	project.parts["camera"] = "cam_micro_analog"
	shell.apply_project(project)
	# 40°, not the 25° default: a path that forgets the assembly prints at 25° and only this shows it.
	shell.lab.assembly_panel.set_tweak_mm(AssemblyTweaks.CAMERA_TILT, 40.0)
	# The shell's own container has no path, so this can never rewrite a real drone on disk.
	var safe := shell.container != null and shell.container.path == ""
	_clear_dir(DIR)
	shell.printed_export_dir = DIR
	var before := shell.container.project.print_records.size() if safe else -1
	if safe:
		shell._on_project_action("export_printed")
	var records: Array = shell.container.project.print_records if safe else []
	var camera_record: Dictionary = {}
	for record in records:
		if String(record["part"]) == "camera_mount":
			camera_record = record
	var camera_files := 0
	for f in DirAccess.get_files_at(DIR):
		if String(f).begins_with("camera_mount"):
			camera_files += 1
	var summary := shell.last_printed_export_summary
	var theta := deg_to_rad(40.0)
	var tipped := snappedf(19.0 * sin(theta) + 21.0 * cos(theta), 0.01)
	var bbox: Array = camera_record.get("bbox_mm", [0.0, 0.0, 0.0])

	# The same part from its own Export button: the file it writes must be the recorded bytes.
	var button_path := DIR.path_join("camera_mount-cam_micro_analog.stl")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(button_path))
	if safe:
		shell._on_printed_export_requested(CameraMount.PART_ID)
	var button_sha := FileAccess.get_file_as_string(button_path).sha256_text() \
		if FileAccess.file_exists(button_path) else ""
	shell.free()
	TestVideoPanel._restore_saved_tweaks(previous)

	results.append(TestResult.new(
		"choosing it exports the open drone's parts at the Camera tilt (40°), records them on its project, and says so",
		safe and before == 0 and _parts(records).has("camera_mount") and camera_files == 1
			and summary.contains("camera_mount") and absf(float(bbox[1]) - tipped) < 0.011,
		"safe %s, records %s, %d camera files, cheek %.2f mm tall vs %.2f at 40°, summary \"%s\"" % [safe,
			_parts(records), camera_files, float(bbox[1]), tipped, summary]))
	results.append(TestResult.new(
		"and the camera mount's own Export button writes exactly the bytes the room export recorded",
		button_sha != "" and button_sha == String(camera_record.get("geometry_sha256", "-")),
		"button %s…, record %s…" % [button_sha.substr(0, 12), String(camera_record.get("geometry_sha256", "")).substr(0, 12)]))
	return results


## drone fits the 5" bumper, and the record's bytes must be exactly what Propulsion's own guard export
## writes — so a room export that tessellated its own ring, fails.
static func _a_fitted_prop_guard_goes_through_the_room_export(catalog: PartsCatalog) -> Array:
	_clear_dir(DIR)
	var guard := catalog.get_part("guard_bumper_5in_abs")
	var build := ReferenceBuild.build()
	build.guard = guard
	var container := ProjectContainer.make(Project.create("Guarded"))
	var result := PrintedExport.export_all(build, DIR, container)
	var record: Dictionary = {}
	for r in result.get("written", []):
		if String((r as Dictionary).get("part", "")) == "prop_guard":
			record = r

	var own_path := DIR.path_join("_propulsion_own_guard.stl")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(own_path))
	var own := PropulsionExport.write_guard(guard, own_path)
	# Propulsion names its solid by part id, which is also the room export's solid name for a guard.
	var own_sha := FileAccess.get_file_as_string(own_path).sha256_text() if FileAccess.file_exists(own_path) else ""
	var member := container.member_bytes(String(record.get("file", ""))).get_string_from_utf8()
	return [
		TestResult.new("a drone fitting the 5\" bumper exports its prop guard through the room export: one ring, print four",
			not record.is_empty() and int(record.get("quantity", 0)) == 4
				and String(record.get("generator", "")) == "prop_guard@1" and int(record.get("triangles", 0)) > 0,
			"record %s" % [record]),
		TestResult.new("and the bytes kept in the drone are exactly the ones Propulsion's own guard export writes",
			bool(own.get("ok", false)) and own_sha != "" and member.sha256_text() == own_sha
				and String(record.get("geometry_sha256", "")) == own_sha,
			"propulsion %s…, member %s…, record %s…" % [own_sha.substr(0, 12), member.sha256_text().substr(0, 12),
				String(record.get("geometry_sha256", "")).substr(0, 12)]),
	]


static func _parts(records: Array) -> Array:
	var out: Array = []
	for record in records:
		out.append(String((record as Dictionary).get("part", "")))
	return out


static func _clear_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(f)))
