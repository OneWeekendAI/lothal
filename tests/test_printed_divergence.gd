class_name TestPrintedDivergence
extends RefCounted
## Divergence on open — printed-room slice PR5 (plans/2026-09-14-printed-room-plan.md, PR5 checks).
##
## Where each check could pass while proving nothing, and what stops it:
##   - "a match says nothing" is the silent path, and a check that changes nothing proves only that.
##     So the fixture HAS records, and every other check changes exactly one input and demands speech.
##   - "the tilt changed" is checked at 25° → 40° with both numbers in the message, so a message that
##     merely says "differs" fails, and so does one that quotes the wrong from/to.
##   - "the newest record decides" needs an OLDER stale record beside a current one; a single record
##     cannot tell newest from first.
##   - "a missing file is reported" deletes the member of a record that otherwise matches, so only the
##     missing-member rule can explain speech.
##   - every export clears its directory first, and the shell check stashes app_settings.json, which
##     open_project writes.

const DIR := "user://exports/_test_divergence"
const RT_DIR := "user://_test_divergence"


static func run() -> Array:
	var results: Array = []
	results.append(_an_unchanged_drone_says_nothing())
	results.append(_a_clearance_change_is_named())
	results.append(_a_tilt_change_is_named_from_and_to())
	results.append(_the_newest_record_decides())
	results.append(_a_part_no_longer_generated_is_reported())
	results.append(_a_missing_file_is_reported())
	results.append(_opening_the_drone_says_it())
	return results


## A drone with camera and antenna mounts exported at `printing`, on a build at `tilt_deg`.
static func _exported(printing: Dictionary, tilt_deg: float) -> Dictionary:
	_clear_dir(DIR)
	var build := _build(printing, tilt_deg)
	var project := Project.create("Diverging")
	project.printing = printing.duplicate(true)
	var container := ProjectContainer.make(project)
	var result := PrintedExport.export_all(build, 0.0, DIR, container)
	return {"container": container, "written": result.get("written", [])}


static func _build(printing: Dictionary, tilt_deg: float) -> Build:
	var build := ReferenceBuild.build()
	build.set_printing(printing.duplicate(true))
	build.set_assembly({"camera_tilt_deg": tilt_deg})
	return build


static func _messages(findings: Array) -> Array:
	var out: Array = []
	for f in findings:
		out.append(String((f as Dictionary).get("message", "")))
	return out


static func _for_part(findings: Array, part: String) -> Dictionary:
	for f in findings:
		if String((f as Dictionary).get("part", "")) == part:
			return f
	return {}


static func _an_unchanged_drone_says_nothing() -> TestResult:
	var e := _exported({}, 25.0)
	var container: ProjectContainer = e["container"]
	var findings := PrintedDivergence.check(container.project, container, _build({}, 25.0), 0.0)
	return TestResult.new("a drone whose parts still generate what was exported says nothing — with three records to compare",
		(e["written"] as Array).size() == 3 and container.project.print_records.size() == 3 and findings.is_empty(),
		"%d records, findings %s" % [container.project.print_records.size(), _messages(findings)])


static func _a_clearance_change_is_named() -> TestResult:
	var e := _exported({}, 25.0)
	var container: ProjectContainer = e["container"]
	var looser := {}
	PrintSettings.set_clearance_mm(looser, 0.35)
	var findings := PrintedDivergence.check(container.project, container, _build(looser, 25.0), 0.0)
	var camera := _for_part(findings, "camera_mount")
	var message := String(camera.get("message", ""))
	var date := String(container.project.print_records[0]["printed_at"]).substr(0, 10)
	return TestResult.new(
		"0.20 → 0.35 mm clearance: the camera mount differs, dated, keep-or-reprint, naming the clearance from and to",
		String(camera.get("kind", "")) == "differs" and message.contains(date) and message.contains("reprint")
			and message.contains("clearance changed from 0.20 to 0.35 mm") and findings.size() == 3,
		"%d findings; camera \"%s\"" % [findings.size(), message])


## The coordinator's demand: a mount that differs because the GLOBAL tilt moved must say so, with the
## angles. A generic "differs" is exactly the message this check exists to reject.
static func _a_tilt_change_is_named_from_and_to() -> TestResult:
	var e := _exported({}, 25.0)
	var container: ProjectContainer = e["container"]
	var findings := PrintedDivergence.check(container.project, container, _build({}, 40.0), 0.0)
	var camera := _for_part(findings, "camera_mount")
	var message := String(camera.get("message", ""))
	return TestResult.new(
		"camera tilt 25° → 40°: the camera mount differs and the message says the camera tilt changed from 25° to 40°; nothing else changed",
		String(camera.get("kind", "")) == "differs" and message.contains("camera tilt changed from 25° to 40°")
			and not message.contains("clearance changed") and findings.size() == 1,
		"%d findings: %s" % [findings.size(), _messages(findings)])


static func _the_newest_record_decides() -> TestResult:
	# An old export at 0.35 mm, then a current one at the default: the drone now matches its newest print.
	var looser := {}
	PrintSettings.set_clearance_mm(looser, 0.35)
	var old := _exported(looser, 25.0)
	var container: ProjectContainer = old["container"]
	var fresh := PrintedExport.export_all(_build({}, 25.0), 0.0, DIR, container)
	container.project.printing = {}
	var findings := PrintedDivergence.check(container.project, container, _build({}, 25.0), 0.0)
	return TestResult.new("with an older stale record and a newer matching one, the newest decides: nothing is said",
		container.project.print_records.size() == 6 and (fresh.get("written", []) as Array).size() == 3
			and findings.is_empty(),
		"%d records, findings %s" % [container.project.print_records.size(), _messages(findings)])


static func _a_part_no_longer_generated_is_reported() -> TestResult:
	var e := _exported({}, 25.0)
	var container: ProjectContainer = e["container"]
	var build := _build({}, 25.0)
	build.components.erase("antenna")
	var findings := PrintedDivergence.check(container.project, container, build, 0.0)
	var antenna := _for_part(findings, "antenna_mount")
	return TestResult.new("an antenna taken off the build reports its printed mount as no longer generated, and only that",
		String(antenna.get("kind", "")) == "gone" and String(antenna.get("message", "")).contains("antenna mount")
			and String(antenna.get("message", "")).contains("no longer") and findings.size() == 1,
		"%s" % [_messages(findings)])


static func _a_missing_file_is_reported() -> TestResult:
	var e := _exported({}, 25.0)
	var container: ProjectContainer = e["container"]
	var record: Dictionary = container.project.print_records[1]
	container.set_member_bytes(String(record["file"]), PackedByteArray())
	var findings := PrintedDivergence.check(container.project, container, _build({}, 25.0), 0.0)
	var hit := _for_part(findings, String(record["part"]))
	return TestResult.new("a record whose STL is missing from the drone is reported by name and file, never dropped",
		String(hit.get("kind", "")) == "missing_file" and String(hit.get("message", "")).contains(String(record["file"]))
			and findings.size() == 1,
		"%s" % [_messages(findings)])


## Export, write the drone, loosen its clearance in the file, open it: the status line says the camera
## mount differs. The real app_settings.json is stashed, because open_project remembers the path.
static func _opening_the_drone_says_it() -> TestResult:
	var previous: Variant = null
	if FileAccess.file_exists(AppSettings.SAVE_PATH):
		previous = FileAccess.get_file_as_string(AppSettings.SAVE_PATH)
	_clear_dir(RT_DIR)
	var path := RT_DIR + "/diverging.lothal"
	var e := _exported({}, 25.0)
	var container: ProjectContainer = e["container"]
	# The default micro camera, so the opened drone generates a camera mount at all.
	container.project.parts["camera"] = "cam_micro_analog"
	container.project.parts["antenna"] = "antenna_rhcp_ufl"
	PrintSettings.set_clearance_mm(container.project.printing, 0.35)
	var wrote := container.write(path, RT_DIR + "/no_custom_parts.json")

	var shell := GlassShell.new()
	shell.open_folder_after_export = false
	if wrote:
		shell.open_project(path)
	var findings: Array = shell.printed_divergence
	var status := shell.status_text()
	shell.free()

	_clear_dir(RT_DIR)
	if previous == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AppSettings.SAVE_PATH))
	else:
		var handle := FileAccess.open(AppSettings.SAVE_PATH, FileAccess.WRITE)
		handle.store_string(String(previous))
		handle.close()

	var camera := _for_part(findings, "camera_mount")
	return TestResult.new("opening a drone whose clearance moved since its export puts the camera mount's divergence on the status line",
		wrote and String(camera.get("kind", "")) == "differs" and status.contains("camera mount")
			and status.contains("clearance changed from 0.20 to 0.35 mm"),
		"wrote %s; findings %s; status \"%s\"" % [wrote, _messages(findings), status])


static func _clear_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(f)))
