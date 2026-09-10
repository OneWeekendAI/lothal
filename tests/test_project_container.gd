class_name TestProjectContainer
extends RefCounted
## The `.lothal` file — one file a builder can find, move and reopen.
##
## Four checks here are written specifically so they cannot pass on a container that is not really
## a container:
##
## **1. Round-tripping through memory proves nothing.** Every assertion below goes through a real
## file on disk, opened by a fresh reader that has never seen the object that wrote it. The first
## version of this class was deliberately written to hold its members in a Dictionary and never
## open ZIPPacker at all, and the round-trip test passed against it.
##
## **2. "It saved" is not "it is a zip".** One check opens the file with a plain ZIPReader and
## asserts the member NAMES, so a container that quietly fell back to writing JSON at that path
## would fail even though every read-back value is correct.
##
## **3. A transitive custom-part reference is the case that will actually break.** A custom motor
## cites a custom propeller in its thrust table. Copying only what is FITTED produces a file whose
## motor refuses to load on the other machine, complaining about a propeller nobody chose — and
## copying nothing at all passes any test that only looks at the fitted motor. So the check fits
## the motor, leaves the prop unfitted, and asserts the prop travelled anyway.
##
## **4. Atomicity is asserted by breaking a write.** A directory is parked where the temporary
## needs to go; the check is that the PREVIOUS container is still openable and still correct.

const TEST_DIR := "user://test_container"
const CUSTOM_PATH := TEST_DIR + "/custom_parts.json"

static func run() -> Array:
	var results: Array = []
	_clean()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))

	results.append_array(_test_a_drone_survives_the_app_closing())
	results.append_array(_test_it_is_really_a_zip())
	results.append_array(_test_unknown_members_are_carried_through())
	results.append_array(_test_custom_parts_travel_with_the_drone())
	results.append_array(_test_a_later_container_is_refused())
	results.append_array(_test_a_broken_file_does_not_take_the_others_with_it())
	results.append_array(_test_a_failed_write_leaves_the_previous_container_whole())
	results.append_array(_test_an_unchanged_project_writes_nothing())

	_clean()
	return results


static func _project(p_name: String = "Weekend 5") -> Project:
	var project := Project.create(p_name)
	project.parts["frame"] = ReferenceBuild.FRAME_ID
	project.parts["motor"] = ReferenceBuild.MOTOR_ID
	project.parts["propeller"] = ReferenceBuild.PROPELLER_ID
	project.parts["battery"] = ReferenceBuild.BATTERY_ID
	project.parts["esc"] = ReferenceBuild.ESC_ID
	project.parts["flight_controller"] = ReferenceBuild.FC_ID
	# The four optional bays, fitted explicitly. A project created fresh fits NOTHING optional —
	# which is ProjectSchema's dense-parts rule working, and is why this helper weighs 475 g
	# without these four lines. Spelled out so the 496 g oracle below is about the container
	# round trip rather than about what Project.create() happens to default to.
	# `Build.OPTIONAL_COMPONENTS` and NOT `ProjectSchema.OPTIONAL_CATEGORIES`, and the difference
	# is not cosmetic — it is what P10f's guard exposed. The schema's optional list is "categories
	# a project file may leave off" and the Build's is "the payload the mass model weighs from a
	# dictionary"; the guard is in the first and not the second, because it reaches `Build` as a
	# trailing argument rather than through `component_ids`. This loop wants the four bays with
	# defaults, so it reads the list that HAS defaults.
	for category in Build.OPTIONAL_COMPONENTS:
		project.parts[category] = String(Build.DEFAULT_COMPONENT_IDS[category])
	return project


static func _path(file_name: String) -> String:
	return "%s/%s.%s" % [TEST_DIR, file_name, ProjectContainer.EXTENSION]


static func _test_a_drone_survives_the_app_closing() -> Array:
	var results: Array = []
	var project := _project()
	project.assembly["plate_gap_mm"] = 7.5
	project.tune["roll"] = {"p": 48.0, "i": 62.0, "d": 34.0}
	project.add_version("before the 6S swap")

	var container := ProjectContainer.make(project)
	var wrote := container.write(_path("weekend"))
	results.append(TestResult.new(
		"a drone writes to one file",
		wrote and FileAccess.file_exists(_path("weekend")),
		"wrote=%s exists=%s" % [wrote, FileAccess.file_exists(_path("weekend"))]
	))

	# A fresh reader, which has never seen the container that wrote this.
	var reopened := ProjectContainer.open(_path("weekend"))
	results.append(TestResult.new(
		"and reopens with the same id, name, parts, tweaks, tune and versions",
		reopened != null
			and reopened.project.project_id == project.project_id
			and reopened.project.name == "Weekend 5"
			and String(reopened.project.parts["motor"]) == ReferenceBuild.MOTOR_ID
			and is_equal_approx(float(reopened.project.assembly["plate_gap_mm"]), 7.5)
			and is_equal_approx(
				float((reopened.project.tune["roll"] as Dictionary)["d"]), 34.0)
			and reopened.project.versions.size() == 1,
		"reopened=%s" % ("null" if reopened == null else reopened.project.name)
	))

	# The oracle: it is the reference build, so it weighs 496 g on the other side of the file.
	var build := reopened.project.to_build(PartsCatalog.load_default())
	results.append(TestResult.new(
		"and it is still the same aircraft, to the gram",
		build != null and absf(build.all_up_weight_g() - 507.48) < 0.05,
		"%.2f g" % (0.0 if build == null else build.all_up_weight_g())
	))
	return results


static func _test_it_is_really_a_zip() -> Array:
	var reader := ZIPReader.new()
	var opened := reader.open(_path("weekend")) == OK
	var files: Array = []
	if opened:
		for f in reader.get_files():
			files.append(String(f))
		reader.close()
	return [TestResult.new(
		"the file is an archive with the members the design names, not JSON at a .lothal path",
		opened
			and files.has(ProjectContainer.MANIFEST_MEMBER)
			and files.has(ProjectContainer.PROJECT_MEMBER),
		"members: %s" % [files]
	)]


static func _test_unknown_members_are_carried_through() -> Array:
	# A member from a Lothal that does not exist yet: a printed part, and a wiring diagram.
	var project := _project("Has a future in it")
	var container := ProjectContainer.make(project)
	container.write(_path("future"))

	var seeded := ProjectContainer.open(_path("future"))
	seeded._members["printed/camera_mount_v3.stl"] = "solid mount\nendsolid".to_utf8_buffer()
	seeded._members["wiring/harness.svg"] = "<svg/>".to_utf8_buffer()
	seeded.project.name = "Renamed by an older Lothal"
	seeded.write()

	# Saved by a version that knows nothing about either member. They must still be there.
	var after := ProjectContainer.open(_path("future"))
	var stl: PackedByteArray = after._members.get("printed/camera_mount_v3.stl", PackedByteArray())
	return [TestResult.new(
		"a member a later Lothal wrote survives this one saving the file",
		after != null
			and after.project.name == "Renamed by an older Lothal"
			and stl.get_string_from_utf8() == "solid mount\nendsolid"
			and after._members.has("wiring/harness.svg"),
		"members: %s" % [after._members.keys()]
	)]


static func _test_custom_parts_travel_with_the_drone() -> Array:
	var results: Array = []

	# A custom motor whose thrust table cites a custom PROPELLER. The prop is not fitted.
	var custom := {
		"schema": 1,
		"propellers": [{
			"part_id": "prop_custom_tri", "name": "My tri-blade", "category": "propellers",
			"specs": {"diameter_in": 5.1, "pitch_in": 4.3, "blades": 3}, "mass_g": 4.8,
			"source": "measured",
		}],
		"motors": [{
			"part_id": "motor_custom_2207", "name": "My 2207", "category": "motors",
			"specs": {"kv": 1960, "stator_diameter_mm": 22, "stator_height_mm": 7},
			"mass_g": 32.0, "source": "measured",
			"thrust_test": {"prop_id": "prop_custom_tri", "volts": 14.8, "points": []},
		}],
	}
	JsonStore.write_document(CUSTOM_PATH, custom)

	var project := _project("Custom motor build")
	project.parts["motor"] = "motor_custom_2207"
	var container := ProjectContainer.make(project)
	container.write(_path("custom"), CUSTOM_PATH)

	var reopened := ProjectContainer.open(_path("custom"))
	var travelled := reopened.custom_parts()
	var motors: Array = travelled.get("motors", [])
	var props: Array = travelled.get("propellers", [])

	results.append(TestResult.new(
		"the custom part the drone uses is copied into the file",
		motors.size() == 1
			and String((motors[0] as Dictionary)["part_id"]) == "motor_custom_2207",
		"motors: %s" % [motors.size()]
	))
	results.append(TestResult.new(
		"and so is the custom prop its thrust table cites, though nothing fitted it",
		props.size() == 1
			and String((props[0] as Dictionary)["part_id"]) == "prop_custom_tri",
		"propellers: %s" % [props.size()]
	))

	# The other half: a custom part the drone does NOT use stays out of the file. Without this,
	# "copy everything" passes both checks above and every shared drone drags along the whole of
	# somebody's parts bin.
	var unrelated := custom.duplicate(true)
	(unrelated["propellers"] as Array).append({
		"part_id": "prop_custom_unused", "name": "Unused", "category": "propellers",
		"specs": {"diameter_in": 3.0, "pitch_in": 2.0, "blades": 2}, "mass_g": 2.0,
		"source": "measured",
	})
	JsonStore.write_document(CUSTOM_PATH, unrelated)
	ProjectContainer.make(project).write(_path("custom2"), CUSTOM_PATH)
	var second := ProjectContainer.open(_path("custom2"))
	var second_props: Array = second.custom_parts().get("propellers", [])
	var ids: Array = []
	for record in second_props:
		ids.append(String((record as Dictionary)["part_id"]))
	results.append(TestResult.new(
		"a custom part this drone does not use stays out of its file",
		not ids.has("prop_custom_unused") and ids.has("prop_custom_tri"),
		"propellers carried: %s" % [ids]
	))
	return results


static func _test_a_later_container_is_refused() -> Array:
	var project := _project("From the future")
	var container := ProjectContainer.make(project)
	container.write(_path("newer"))

	# Rewrite the manifest as a later container layout, keeping everything else.
	var reader := ZIPReader.new()
	reader.open(_path("newer"))
	var document := reader.read_file(ProjectContainer.PROJECT_MEMBER)
	reader.close()

	var packer := ZIPPacker.new()
	packer.open(_path("newer"), ZIPPacker.APPEND_CREATE)
	packer.start_file(ProjectContainer.MANIFEST_MEMBER)
	packer.write_file(JSON.stringify({
		"container": {"major": ProjectContainer.CONTAINER_MAJOR + 1, "minor": 0},
	}).to_utf8_buffer())
	packer.close_file()
	packer.start_file(ProjectContainer.PROJECT_MEMBER)
	packer.write_file(document)
	packer.close_file()
	packer.close()

	return [TestResult.new(
		"a container whose layout has changed is refused rather than half-read",
		ProjectContainer.open(_path("newer")) == null,
		"container major %d" % (ProjectContainer.CONTAINER_MAJOR + 1)
	)]


static func _test_a_broken_file_does_not_take_the_others_with_it() -> Array:
	var results: Array = []
	var handle := FileAccess.open(_path("garbage"), FileAccess.WRITE)
	handle.store_string("this is not a zip")
	handle.close()

	results.append(TestResult.new(
		"a file that is not a container opens as nothing, not as a crash",
		ProjectContainer.open(_path("garbage")) == null,
		"opened null"
	))
	results.append(TestResult.new(
		"and it is left exactly as it was, for a builder to rescue by hand",
		FileAccess.get_file_as_string(_path("garbage")) == "this is not a zip",
		"still %d bytes" % FileAccess.get_file_as_string(_path("garbage")).length()
	))
	# And the neighbour still opens.
	results.append(TestResult.new(
		"and the drone next to it still opens",
		ProjectContainer.open(_path("weekend")) != null,
		"weekend.lothal opened"
	))
	return results


static func _test_a_failed_write_leaves_the_previous_container_whole() -> Array:
	var results: Array = []
	var project := _project("Precious")
	var container := ProjectContainer.make(project)
	container.write(_path("precious"))

	# A directory where the temporary has to go. The write cannot complete.
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_path("precious") + ".tmp"))
	container.project.name = "Changed, and doomed"
	var wrote := container.write(_path("precious"))

	results.append(TestResult.new(
		"a container write that cannot complete says so",
		not wrote,
		"write returned %s" % wrote
	))
	var survivor := ProjectContainer.open(_path("precious"))
	results.append(TestResult.new(
		"and the drone that was already there is still openable, and still itself",
		survivor != null and survivor.project.name == "Precious",
		"name after the failed write: %s" % ("(gone)" if survivor == null else survivor.project.name)
	))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path("precious") + ".tmp"))
	return results


static func _test_an_unchanged_project_writes_nothing() -> Array:
	var container := ProjectContainer.make(_project("Idle"))
	container.write(_path("idle"))
	var results: Array = [TestResult.new(
		"a project just written has nothing to write",
		not container.has_unsaved_changes(),
		"has_unsaved_changes=%s" % container.has_unsaved_changes()
	)]
	container.project.assembly["plate_gap_mm"] = 9.0
	results.append(TestResult.new(
		"and one that changed by a single tweak does",
		container.has_unsaved_changes(),
		"has_unsaved_changes=%s" % container.has_unsaved_changes()
	))
	return results


static func _clean() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_DIR)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	for file in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute(absolute.path_join(file))
	for directory in DirAccess.get_directories_at(absolute):
		DirAccess.remove_absolute(absolute.path_join(directory))
	DirAccess.remove_absolute(absolute)
