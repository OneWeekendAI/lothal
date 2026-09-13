class_name TestCameraTilt
extends RefCounted
## CAMERA UPTILT — video-room design §1, §2 and §4, slices V1-V3.
##
## Tilt is a property of the build rather than of the part, so it rides the GPS mast's path: an
## AssemblyTweaks key, resolved into Build.assembly, drawn by ComponentMesh, flown by FpvView. This
## file follows it down that path one slice at a time, and each section is the proof for one slice.
##
## THREE TRAPS SHAPED THE CHECKS, and each is named where it bites:
##
## - A SECTION THAT DIES IS INVISIBLE. A runtime error inside one helper aborts only that helper and
##   the suite reports green over the missing assertions. So every section below is collected into a
##   dictionary and the last check asserts none came back empty; and a dictionary read that a
##   mutation could delete is written `.get(key, NAN)`, so the mutation reddens a check instead of
##   killing a section.
## - THE SIGN. This project shipped one mirrored-pitch error already. Uptilt is asserted by the
##   BORESIGHT pointing up (`y > 0`) and by its value against sin/cos of the angle, never by reading
##   the rotation back out of the node that was given it.
## - `global_transform` OUTSIDE THE TREE IS IDENTITY. Nothing here enters the tree, so every eye and
##   lens is composed from local transforms — the airframe's own accessors and
##   FpvView.world_transform_of — which is also exactly what production uses.

const EPS := 1e-6
const SAVE_PATH := "user://test_camera_tilt.json"


static func run() -> Array:
	var catalog := PartsCatalog.load_default()
	var sections := {
		"V1 resolved": [_the_tilt_is_resolved_into_the_assembly(catalog)],
		"V1 clamp": [_the_tilt_clamps_to_its_range_and_keeps_what_was_asked(catalog)],
		"V1 persistence": [_the_tilt_survives_a_restart_and_is_sparse(catalog)],
		"V1 unknown fields": [_a_file_with_the_tilt_keeps_what_it_does_not_know(catalog)],
		"V1 physics": [_the_tilt_moves_no_flight_number(catalog)],
	}

	var results: Array = []
	var empty: Array[String] = []
	for section in sections:
		var got: Array = sections[section]
		if got.is_empty() or got.has(null):
			empty.append(section)
		results.append_array(got.filter(func(r): return r != null))
	results.append(TestResult.new(
		"every camera-tilt section ran and returned its checks",
		empty.is_empty(),
		"%d sections%s" % [sections.size(), "" if empty.is_empty() else " — empty: " + str(empty)]))
	return results


static func _build(catalog: PartsCatalog) -> Build:
	return Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID)


# ---------------------------------------------------------------------------
# V1 — the tilt enters the assembly
# ---------------------------------------------------------------------------

## The one dictionary every consumer reads has to carry the tilt: the default when nothing was set,
## the builder's number when something was, and Build has to hand it back unchanged.
##
## MUTATION (run for V1): delete `camera_tilt_deg` from `resolved_m()`. Build then falls back to
## DEFAULT_ASSEMBLY, so a check that only read Build at the default would pass — which is why the
## set value is 40, not 25, and why the resolved dictionary is read directly as well.
static func _the_tilt_is_resolved_into_the_assembly(catalog: PartsCatalog) -> TestResult:
	var build := _build(catalog)
	var problems: Array[String] = []

	var untouched := AssemblyTweaks.new().resolved_m(build)
	var default_deg := float(untouched.get("camera_tilt_deg", NAN))
	if default_deg != 25.0 or default_deg != float(Build.DEFAULT_ASSEMBLY["camera_tilt_deg"]):
		problems.append("an untouched build resolves to %s deg, not Build's 25" % default_deg)

	var tweaks := AssemblyTweaks.new()
	tweaks.set_mm(AssemblyTweaks.CAMERA_TILT, 40.0)
	var resolved := tweaks.resolved_m(build)
	var set_deg := float(resolved.get("camera_tilt_deg", NAN))
	if set_deg != 40.0:
		problems.append("a 40 deg tilt resolves to %s" % set_deg)
	build.set_assembly(resolved)
	var through_build := float(build.assembly_value("camera_tilt_deg"))
	if through_build != 40.0:
		problems.append("Build hands back %s deg for a 40 deg tilt" % through_build)

	var row_found := false
	for row in AssemblyTweaks.ROWS:
		if row["key"] == AssemblyTweaks.CAMERA_TILT:
			row_found = row["label"] == "Camera uptilt" and row.get("unit", "") == "°"
	if not row_found:
		problems.append("no 'Camera uptilt' slider row quoted in degrees")

	return TestResult.new(
		"the camera tilt is resolved into the assembly — 25° untouched, the builder's number when set",
		problems.is_empty(),
		"untouched %s°, set 40 -> resolved %s° -> Build %s°%s" % [default_deg, set_deg, through_build,
			"" if problems.is_empty() else " — " + str(problems)])


## 0-60 deg, clamped on the way OUT and stored as asked on the way in — the rule every tweak
## follows, so a number from a later version with a wider range is not destroyed by reading it here.
static func _the_tilt_clamps_to_its_range_and_keeps_what_was_asked(catalog: PartsCatalog) -> TestResult:
	var build := _build(catalog)
	var limits: Dictionary = AssemblyTweaks.limits(build)[AssemblyTweaks.CAMERA_TILT]
	var problems: Array[String] = []
	if limits["min"] != 0.0 or limits["max"] != 60.0 or limits["default"] != 25.0:
		problems.append("limits are %s, not 0-60 with 25 default" % limits)

	var tweaks := AssemblyTweaks.new()
	tweaks.set_mm(AssemblyTweaks.CAMERA_TILT, 90.0)
	var high := tweaks.value_mm(AssemblyTweaks.CAMERA_TILT, build)
	var high_resolved := float(tweaks.resolved_m(build).get("camera_tilt_deg", NAN))
	tweaks.set_mm(AssemblyTweaks.CAMERA_TILT, -15.0)
	var low := tweaks.value_mm(AssemblyTweaks.CAMERA_TILT, build)
	if high != 60.0 or high_resolved != 60.0:
		problems.append("90 deg came back as %s (resolved %s), not 60" % [high, high_resolved])
	if low != 0.0:
		problems.append("-15 deg (downtilt) came back as %s, not 0" % low)

	tweaks.set_mm(AssemblyTweaks.CAMERA_TILT, 90.0)
	tweaks.save(SAVE_PATH)
	var stored: Variant = (JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH)) as Dictionary) \
		.get("tweaks", {}).get("camera_tilt_deg", NAN)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	if float(stored) != 90.0:
		problems.append("the file holds %s rather than the 90 that was asked for" % stored)

	tweaks.clear(AssemblyTweaks.CAMERA_TILT)
	if tweaks.value_mm(AssemblyTweaks.CAMERA_TILT, build) != 25.0:
		problems.append("clearing did not return to 25")

	return TestResult.new(
		"the camera tilt clamps to 0-60° when read, is stored as asked, and clears back to 25°",
		problems.is_empty(),
		"90 -> %s°, -15 -> %s°, file keeps %s%s" % [high, low, stored,
			"" if problems.is_empty() else " — " + str(problems)])


## THE MAST'S PERSISTENCE, EXACTLY: one per-user file, `user://assembly_tweaks.json`, which Lab
## writes and Sim reads when its scene loads (main.gd). There is no per-project copy — a project's
## `decisions.assembly` block exists in the schema and nothing writes a tweak into it, for the mast or
## anything else — so tilt gets the answer the mast got, which is the one file.
##
## Sparse, like every tweak: an untouched tilt is NOT written, so a future change of default follows
## the builder rather than being frozen at 25 the first time the file was saved.
static func _the_tilt_survives_a_restart_and_is_sparse(catalog: PartsCatalog) -> TestResult:
	var build := _build(catalog)
	var problems: Array[String] = []

	var written := AssemblyTweaks.new()
	written.set_mm(AssemblyTweaks.CAMERA_TILT, 37.5)
	if not written.save(SAVE_PATH):
		problems.append("save reported failure")
	var reloaded := AssemblyTweaks.load_from(SAVE_PATH)
	var came_back := float(reloaded.resolved_m(build).get("camera_tilt_deg", NAN))
	if came_back != 37.5 or not reloaded.has_override(AssemblyTweaks.CAMERA_TILT):
		problems.append("37.5 deg came back as %s" % came_back)

	var untouched := AssemblyTweaks.new()
	untouched.set_mm(AssemblyTweaks.PROP_SPACER, 1.0)
	untouched.save(SAVE_PATH)
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if (document.get("tweaks", {}) as Dictionary).has("camera_tilt_deg"):
		problems.append("an untouched tilt was written to the file")
	if AssemblyTweaks.load_from(SAVE_PATH).value_mm(AssemblyTweaks.CAMERA_TILT, build) != 25.0:
		problems.append("a file without the tilt does not open at 25")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

	return TestResult.new(
		"the camera tilt survives a save and a reopen, and an untouched tilt is not written",
		problems.is_empty(),
		"37.5° round-tripped as %s°%s" % [came_back,
			"" if problems.is_empty() else " — " + str(problems)])


## A file written by a LATER Lothal holding the tilt beside a field this version has never heard of,
## and a file written by an EARLIER one holding a tilt of the wrong type. The known number is read,
## the unknown field goes back out on save, and the bad value is a default rather than a zero.
static func _a_file_with_the_tilt_keeps_what_it_does_not_know(catalog: PartsCatalog) -> TestResult:
	var build := _build(catalog)
	var problems: Array[String] = []

	var handle := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	handle.store_string(JSON.stringify({
		"schema": AssemblyTweaks.SCHEMA_VERSION,
		"tweaks": {"camera_tilt_deg": 32.0, "camera_roll_deg": 3.0},
		"video_link": {"band": "R"},
	}))
	handle.close()
	var loaded := AssemblyTweaks.load_from(SAVE_PATH)
	var read := loaded.value_mm(AssemblyTweaks.CAMERA_TILT, build)
	if read != 32.0:
		problems.append("the tilt read as %s, not 32" % read)
	loaded.set_mm(AssemblyTweaks.CAMERA_TILT, 20.0)
	loaded.save(SAVE_PATH)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	var tweaks_block: Dictionary = saved.get("tweaks", {})
	if float(tweaks_block.get("camera_tilt_deg", NAN)) != 20.0:
		problems.append("the edited tilt was not saved")
	if not tweaks_block.has("camera_roll_deg"):
		problems.append("the unknown tweak beside the tilt was destroyed")
	if not saved.has("video_link"):
		problems.append("the unknown top-level block was destroyed")

	handle = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	handle.store_string('{"schema": 1, "tweaks": {"camera_tilt_deg": "steep"}}')
	handle.close()
	var bad := AssemblyTweaks.load_from(SAVE_PATH)
	if bad.has_override(AssemblyTweaks.CAMERA_TILT) or bad.value_mm(AssemblyTweaks.CAMERA_TILT, build) != 25.0:
		problems.append("a string tilt was not treated as absent")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

	return TestResult.new(
		"a file holding the tilt keeps its unknown fields, and a non-numeric tilt opens at 25°",
		problems.is_empty(),
		"read 32°, saved 20° beside camera_roll_deg and video_link%s" % (
			"" if problems.is_empty() else " — " + str(problems)))


## THE DECISION, AS A TEST: tilt is a shim, not a position. At 0 and at 60 degrees, every flight
## number and the centre of mass must be BIT-IDENTICAL to the untouched build — `==`, not a
## tolerance, because a rotation about the camera's own centre moves no mass at all.
##
## Its counterpart is V2's eye moving: an invariant with no check that the thing did SOMETHING would
## pass with tilt disconnected at the wall.
static func _the_tilt_moves_no_flight_number(catalog: PartsCatalog) -> TestResult:
	var figures := func(build: Build) -> Array:
		return [build.all_up_weight_g(), build.thrust_to_weight(), build.hover_throttle(),
			build.flight_time_min(), build.top_speed_kmh(), build.mass_properties.com_m,
			build.mass_properties.inertia]

	var untilted: Array = figures.call(_build(catalog))
	var problems: Array[String] = []
	for degrees in [0.0, 60.0]:
		var build := _build(catalog)
		var tweaks := AssemblyTweaks.new()
		tweaks.set_mm(AssemblyTweaks.CAMERA_TILT, degrees)
		build.set_assembly(tweaks.resolved_m(build))
		var got: Array = figures.call(build)
		for i in untilted.size():
			if got[i] != untilted[i]:
				problems.append("figure %d moved at %s deg: %s -> %s" % [i, degrees, untilted[i], got[i]])

	return TestResult.new(
		"camera tilt moves no flight number: weight, T/W, hover, CoM and inertia bit-identical at 0° and 60°",
		problems.is_empty(),
		"%.1f g, hover %.4f, CoM %s at both angles%s" % [untilted[0], untilted[2], untilted[5],
			"" if problems.is_empty() else " — " + str(problems)])
