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
	# THE HOLD ON THE BUILDER'S OWN FILES. Taken here and released below, because a section that
	# aborts mid-way never reaches its own restore — measured, and it is what left a 3500 m
	# elevation and an invented weather row on this developer's disk. `run()` is the only frame
	# GDScript guarantees will resume after an abort inside a section, so the hold lives here and
	# `run()` does nothing else but call sections and append results. See tests/real_files.gd.
	var held := RealFiles.hold([AppSettings.SAVE_PATH])
	results.append(_an_unchanged_drone_says_nothing())
	results.append(_a_clearance_change_is_named())
	results.append(_a_tilt_change_is_named_from_and_to())
	results.append(_the_newest_record_decides())
	results.append(_a_part_no_longer_generated_is_reported())
	results.append(_a_missing_file_is_reported())
	results.append(_opening_the_drone_says_it())
	# PR7: Keep and Reprint.
	results.append(_keep_hides_without_deleting())
	results.append(_a_new_divergence_after_keep_shows_again())
	results.append(_reprint_adds_one_record_for_that_part_only())
	results.append(_keep_survives_reopen_and_the_panel_routes())
	held.restore()
	results.append(TestResult.new(
		"the builder's own files are back the way they were found, whatever the sections did",
		held.intact(), held.report()))
	return results


static func _loosened(mm: float) -> Dictionary:
	var printing := {}
	PrintSettings.set_clearance_mm(printing, mm)
	return printing


## PR7 check 1. Keep acknowledges the camera mount's 0.35 mm divergence: it is gone from the findings,
## the other two parts still speak, and the drone still holds all three records.
static func _keep_hides_without_deleting() -> TestResult:
	var e := _exported({}, 25.0)
	var container: ProjectContainer = e["container"]
	var printing := _loosened(0.35)
	var build := _build(printing, 25.0)
	var before := PrintedDivergence.check(container.project, container, build)
	PrintedDivergence.acknowledge(printing, _for_part(before, "camera_mount"))
	build.set_printing(printing.duplicate(true))
	var after := PrintedDivergence.check(container.project, container, build)
	return TestResult.new("Keep hides the camera mount's message, leaves the other three, and deletes no record",
		before.size() == 4 and after.size() == 3 and _for_part(after, "camera_mount").is_empty()
			and container.project.print_records.size() == 4,
		"before %d, after %s, %d records" % [before.size(), _messages(after), container.project.print_records.size()])


## PR7 check 3. Kept at 0.35 mm; the drone moves on to 0.45 mm. That is a different divergence and it speaks.
static func _a_new_divergence_after_keep_shows_again() -> TestResult:
	var e := _exported({}, 25.0)
	var container: ProjectContainer = e["container"]
	var printing := _loosened(0.35)
	var kept := PrintedDivergence.check(container.project, container, _build(printing, 25.0))
	PrintedDivergence.acknowledge(printing, _for_part(kept, "camera_mount"))
	PrintSettings.set_clearance_mm(printing, 0.45)
	var later := PrintedDivergence.check(container.project, container, _build(printing, 25.0))
	var camera := _for_part(later, "camera_mount")
	return TestResult.new("a kept camera mount that diverges AGAIN (0.35 → 0.45 mm) shows again, naming the new clearance",
		String(camera.get("kind", "")) == "differs" and String(camera.get("message", "")).contains("0.45 mm"),
		"%s" % [_messages(later)])


## PR7 check 4. Reprint the camera mount only: one new record, for it; its finding clears; the others stay.
static func _reprint_adds_one_record_for_that_part_only() -> TestResult:
	var e := _exported({}, 25.0)
	var container: ProjectContainer = e["container"]
	var build := _build(_loosened(0.35), 25.0)
	var result := PrintedExport.export_part(build, "camera_mount", DIR, container)
	var records := container.project.print_records
	var after := PrintedDivergence.check(container.project, container, build)
	return TestResult.new("Reprint writes exactly one new record, for the camera mount, which then matches; the other three still diverge",
		bool(result.get("ok", false)) and records.size() == 5 and String(records[records.size() - 1]["part"]) == "camera_mount"
			and after.size() == 3 and _for_part(after, "camera_mount").is_empty(),
		"ok %s, %d records (last %s), findings %s" % [result.get("ok"), records.size(),
			records[records.size() - 1].get("part", "") if not records.is_empty() else "none", _messages(after)])


## PR7 checks 2 and 5, through the shell and the panel: a drone opened with a divergence shows Keep and
## Reprint; pressing Keep hides it, writes the drone, and it stays hidden when the drone is opened again;
## pressing Reprint on another part adds its record.
static func _keep_survives_reopen_and_the_panel_routes() -> TestResult:
	var previous: Variant = null
	if FileAccess.file_exists(AppSettings.SAVE_PATH):
		previous = FileAccess.get_file_as_string(AppSettings.SAVE_PATH)
	_clear_dir(RT_DIR)
	_clear_dir(DIR)
	var path := RT_DIR + "/keeping.lothal"
	var e := _exported({}, 25.0)
	var container: ProjectContainer = e["container"]
	container.project.parts["camera"] = "cam_micro_analog"
	container.project.parts["antenna"] = "antenna_rhcp_ufl"
	PrintSettings.set_clearance_mm(container.project.printing, 0.35)
	var wrote := container.write(path, RT_DIR + "/no_custom_parts.json")

	var shell := GlassShell.new()
	shell.open_folder_after_export = false
	shell.printed_export_dir = DIR
	var shown_before := 0
	var keep_button: Button = null
	var reprint_button: Button = null
	if wrote:
		shell.open_project(path)
		shown_before = shell.printed_divergence.size()
		keep_button = shell.lab.print_panel.divergence_button("camera_mount", "keep")
		reprint_button = shell.lab.print_panel.divergence_button("antenna_mount", "reprint")
	if keep_button != null:
		keep_button.pressed.emit()
	var after_keep := shell.printed_divergence.size()
	var records_after_keep := shell.container.project.print_records.size() if shell.container != null else -1
	# Reopened BEFORE Reprint: Reprint writes the drone too, and would carry an unwritten Keep with it.
	var between := GlassShell.new()
	between.open_folder_after_export = false
	if wrote:
		between.open_project(path)
	var kept_on_disk := _for_part(between.printed_divergence, "camera_mount").is_empty() \
		and between.printed_divergence.size() == 3
	between.free()
	if reprint_button != null:
		reprint_button.pressed.emit()
	var after_reprint := shell.printed_divergence.size()
	var records := shell.container.project.print_records.size() if shell.container != null else -1
	shell.free()

	var reopened := GlassShell.new()
	reopened.open_folder_after_export = false
	if wrote:
		reopened.open_project(path)
	var still := _for_part(reopened.printed_divergence, "camera_mount")
	var reopened_count := reopened.printed_divergence.size()
	reopened.free()

	_clear_dir(RT_DIR)
	if previous == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AppSettings.SAVE_PATH))
	else:
		var handle := FileAccess.open(AppSettings.SAVE_PATH, FileAccess.WRITE)
		handle.store_string(String(previous))
		handle.close()

	return TestResult.new(
		"the panel's Keep hides the camera mount and its Reprint re-exports the antenna mount; reopened, both stay quiet and only the arm guard and battery pad speak",
		wrote and shown_before == 4 and keep_button != null and reprint_button != null and after_keep == 3
			and records_after_keep == 4 and kept_on_disk
			and after_reprint == 2 and records == 5 and still.is_empty() and reopened_count == 2,
		"wrote %s; shown %d, after keep %d (%d records, on disk %s), after reprint %d, %d records; reopened %d" % [
			wrote, shown_before, after_keep, records_after_keep, kept_on_disk, after_reprint, records, reopened_count])


## A drone with camera and antenna mounts exported at `printing`, on a build at `tilt_deg`.
static func _exported(printing: Dictionary, tilt_deg: float) -> Dictionary:
	_clear_dir(DIR)
	var build := _build(printing, tilt_deg)
	var project := Project.create("Diverging")
	project.printing = printing.duplicate(true)
	var container := ProjectContainer.make(project)
	var result := PrintedExport.export_all(build, DIR, container)
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
	var findings := PrintedDivergence.check(container.project, container, _build({}, 25.0))
	return TestResult.new("a drone whose parts still generate what was exported says nothing — with four records to compare",
		(e["written"] as Array).size() == 4 and container.project.print_records.size() == 4 and findings.is_empty(),
		"%d records, findings %s" % [container.project.print_records.size(), _messages(findings)])


static func _a_clearance_change_is_named() -> TestResult:
	var e := _exported({}, 25.0)
	var container: ProjectContainer = e["container"]
	var looser := {}
	PrintSettings.set_clearance_mm(looser, 0.35)
	var findings := PrintedDivergence.check(container.project, container, _build(looser, 25.0))
	var camera := _for_part(findings, "camera_mount")
	var message := String(camera.get("message", ""))
	# Guarded: a broken export records nothing, and an unguarded [0] aborts the runner instead of failing.
	var date := String(container.project.print_records[0]["printed_at"]).substr(0, 10) \
		if not container.project.print_records.is_empty() else "no record"
	return TestResult.new(
		"0.20 → 0.35 mm clearance: the camera mount differs, dated, keep-or-reprint, naming the clearance from and to",
		String(camera.get("kind", "")) == "differs" and message.contains(date) and message.contains("reprint")
			and message.contains("clearance changed from 0.20 to 0.35 mm") and findings.size() == 4,
		"%d findings; camera \"%s\"" % [findings.size(), message])


## The coordinator's demand: a mount that differs because the GLOBAL tilt moved must say so, with the
## angles. A generic "differs" is exactly the message this check exists to reject.
static func _a_tilt_change_is_named_from_and_to() -> TestResult:
	var e := _exported({}, 25.0)
	var container: ProjectContainer = e["container"]
	var findings := PrintedDivergence.check(container.project, container, _build({}, 40.0))
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
	var fresh := PrintedExport.export_all(_build({}, 25.0), DIR, container)
	container.project.printing = {}
	var findings := PrintedDivergence.check(container.project, container, _build({}, 25.0))
	return TestResult.new("with an older stale record and a newer matching one, the newest decides: nothing is said",
		container.project.print_records.size() == 8 and (fresh.get("written", []) as Array).size() == 4
			and findings.is_empty(),
		"%d records, findings %s" % [container.project.print_records.size(), _messages(findings)])


static func _a_part_no_longer_generated_is_reported() -> TestResult:
	var e := _exported({}, 25.0)
	var container: ProjectContainer = e["container"]
	var build := _build({}, 25.0)
	build.components.erase("antenna")
	var findings := PrintedDivergence.check(container.project, container, build)
	var antenna := _for_part(findings, "antenna_mount")
	return TestResult.new("an antenna taken off the build reports its printed mount as no longer generated, and only that",
		String(antenna.get("kind", "")) == "gone" and String(antenna.get("message", "")).contains("antenna mount")
			and String(antenna.get("message", "")).contains("no longer") and findings.size() == 1,
		"%s" % [_messages(findings)])


static func _a_missing_file_is_reported() -> TestResult:
	var e := _exported({}, 25.0)
	var container: ProjectContainer = e["container"]
	if container.project.print_records.size() < 2:
		return TestResult.new("a record whose STL is missing from the drone is reported by name and file, never dropped",
			false, "the export recorded %d parts, so there is no second record to strip" % container.project.print_records.size())
	var record: Dictionary = container.project.print_records[1]
	container.set_member_bytes(String(record["file"]), PackedByteArray())
	var findings := PrintedDivergence.check(container.project, container, _build({}, 25.0))
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
