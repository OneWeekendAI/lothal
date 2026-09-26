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
		"V2 boresight": [_the_boresight_points_up_by_the_tilt(catalog)],
		"V2 eye": [_the_eye_swings_up_with_the_camera(catalog)],
		"V2 seat": [_the_camera_rotates_about_its_own_centre(catalog)],
		"V2 camera view": [_the_camera_view_report_moves_with_the_tilt(catalog)],
		"V3 lens": [_a_level_aircraft_looks_above_the_horizon_by_the_tilt(catalog)],
		"V3 caption": [_the_caption_states_the_builders_uptilt(catalog)],
		"V3 sim wiring": [_sim_builds_its_airframe_from_the_saved_tweaks()],
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


# ---------------------------------------------------------------------------
# V2 — the tilt reaches the drawing
# ---------------------------------------------------------------------------

## An airframe drawn through the path Lab and Sim both use: a tweaks object, resolved inside
## AirframeModel.rebuild. Caller frees it.
static func _airframe_at(catalog: PartsCatalog, degrees: float) -> AirframeModel:
	var tweaks := AssemblyTweaks.new()
	tweaks.set_mm(AssemblyTweaks.CAMERA_TILT, degrees)
	var airframe := AirframeModel.new()
	airframe.rebuild(_build(catalog), tweaks)
	return airframe


## THE SIGN CHECK. Uptilt must point the lens ABOVE the horizon — `y > 0` is the assertion that a
## mirrored rotation cannot pass — and by exactly the angle, (0, sin θ, -cos θ). The expected vector
## is written from sin and cos here, not read back off any node, so the test and the code are two
## statements of the angle rather than one statement compared with itself.
##
## Also checked with NO tweaks object: the drawing's own fallback must be Build's 25, not level.
##
## MUTATION (run for V2): flip the sign of the rotation in ComponentMesh — the lens then looks at the
## ground, `y` goes negative, and this goes red.
static func _the_boresight_points_up_by_the_tilt(catalog: PartsCatalog) -> TestResult:
	var problems: Array[String] = []
	var seen: Array[String] = []
	for degrees in [40.0, 60.0]:
		var airframe := _airframe_at(catalog, degrees)
		var bore := airframe.camera_boresight()
		airframe.free()
		var theta := deg_to_rad(degrees)
		var expected := Vector3(0.0, sin(theta), -cos(theta))
		seen.append("%s° -> %s" % [degrees, bore])
		if not bore.y > 0.0:
			problems.append("at %s deg the boresight looks DOWN (%s)" % [degrees, bore])
		if bore.distance_to(expected) > EPS:
			problems.append("at %s deg the boresight is %s, sin/cos give %s" % [degrees, bore, expected])

	var fallback := AirframeModel.new()
	fallback.rebuild(_build(catalog))
	var default_bore := fallback.camera_boresight()
	fallback.free()
	var t25 := deg_to_rad(25.0)
	if default_bore.distance_to(Vector3(0.0, sin(t25), -cos(t25))) > EPS:
		problems.append("an airframe drawn with no tweaks looks along %s, not 25 deg up" % default_bore)

	var level := _airframe_at(catalog, 0.0)
	var level_bore := level.camera_boresight()
	level.free()
	if level_bore.distance_to(Vector3(0.0, 0.0, -1.0)) > EPS:
		problems.append("at 0 deg the boresight is %s, not straight forward" % level_bore)

	return TestResult.new(
		"the boresight points above the horizon by exactly the tilt — (0, sin θ, −cos θ)",
		problems.is_empty(),
		"%s; no tweaks -> %s; 0° -> %s%s" % [", ".join(seen), default_bore, level_bore,
			"" if problems.is_empty() else " — " + str(problems)])


## The eye sits AHEAD of the camera box, so tipping the box up must lift the eye and pull it back
## toward the box's centre — not only turn it. Asserted as "higher, and still the same distance from
## the camera's centre", both of which a position-plus-position composition fails.
static func _the_eye_swings_up_with_the_camera(catalog: PartsCatalog) -> TestResult:
	var level := _airframe_at(catalog, 0.0)
	var tipped := _airframe_at(catalog, 40.0)
	var eye_level: Vector3 = level.camera_eye_m()
	var eye_tipped: Vector3 = tipped.camera_eye_m()
	var centre_level: Vector3 = (level.component_meshes["camera"] as Node3D).position
	var centre_tipped: Vector3 = (tipped.component_meshes["camera"] as Node3D).position
	level.free()
	tipped.free()

	var arm_level := eye_level - centre_level
	var arm_tipped := eye_tipped - centre_tipped
	var theta := deg_to_rad(40.0)
	# The arm is (0, 0, -r) level; tipped by θ it is (0, r sin θ, -r cos θ). Written out, not rotated.
	var r := arm_level.length()
	var expected := Vector3(0.0, r * sin(theta), -r * cos(theta))

	var problems: Array[String] = []
	if not eye_tipped.y > eye_level.y:
		problems.append("the eye did not rise (%.5f -> %.5f m)" % [eye_level.y, eye_tipped.y])
	if absf(arm_tipped.length() - r) > EPS:
		problems.append("the eye changed its distance from the camera's centre")
	if arm_tipped.distance_to(expected) > EPS:
		problems.append("the eye is at %s from centre, expected %s" % [arm_tipped, expected])

	return TestResult.new(
		"the eye swings up with the camera, about the camera's own centre",
		problems.is_empty(),
		"eye %.1f mm ahead; level y %.2f mm -> 40° y %.2f mm%s" % [r * 1000.0,
			eye_level.y * 1000.0, eye_tipped.y * 1000.0,
			"" if problems.is_empty() else " — " + str(problems)])


## Rotating about its own centre means the camera is SEATED identically at every tilt — its node
## position is bit-identical — and the mass the physics weighs there does not move. The CoM half was
## asserted through Build in V1; this is the drawing's half, so a slice that "helpfully" re-seated a
## tilted camera would be caught on the picture as well as on the tensor.
static func _the_camera_rotates_about_its_own_centre(catalog: PartsCatalog) -> TestResult:
	var positions: Array = []
	var coms: Array = []
	for degrees in [0.0, 60.0]:
		var airframe := _airframe_at(catalog, degrees)
		positions.append((airframe.component_meshes["camera"] as Node3D).position)
		airframe.free()
		var build := _build(catalog)
		var tweaks := AssemblyTweaks.new()
		tweaks.set_mm(AssemblyTweaks.CAMERA_TILT, degrees)
		build.set_assembly(tweaks.resolved_m(build))
		coms.append(build.mass_properties.com_m)

	return TestResult.new(
		"the camera is seated identically and the CoM is bit-identical at 0° and 60°",
		positions[0] == positions[1] and coms[0] == coms[1],
		"seat %s vs %s; CoM %s vs %s" % [positions[0], positions[1], coms[0], coms[1]])


## The camera-view report takes the eye and boresight as numbers, so tilt should move it with no
## change to CameraView. Asserted as: the frame's plates go FURTHER off-axis when the lens looks up
## — the bottom plate's front edge is below and ahead of the lens, so tipping away from it can only
## widen the angle. A report that did not change would pass with the tilt disconnected.
static func _the_camera_view_report_moves_with_the_tilt(catalog: PartsCatalog) -> TestResult:
	var nearest := func(degrees: float) -> float:
		var airframe := _airframe_at(catalog, degrees)
		var report := CameraView.off_axis_report(airframe.camera_eye_m(), airframe.camera_boresight(),
			airframe.camera_obstruction_points_m())
		airframe.free()
		var best := INF
		for part_name in report:
			if str(part_name).begins_with("Plate"):
				best = minf(best, float(report[part_name]))
		return best

	var level: float = nearest.call(0.0)
	var tipped: float = nearest.call(40.0)
	return TestResult.new(
		"the camera-view report moves with the tilt — the plates go further off-axis as the lens looks up",
		level != INF and tipped > level + 1.0,
		"nearest plate %.1f° level, %.1f° at 40°" % [level, tipped])


# ---------------------------------------------------------------------------
# V3 — the tilt reaches Sim
# ---------------------------------------------------------------------------

## An airframe as Sim builds one: the tweaks READ BACK FROM A FILE, then `rebuild(build, tweaks)` —
## main.gd's two lines, with a test path in place of the real one so the developer's own settings
## are never touched. Parented to a level drone node, as main.tscn's Drone holds it. Returns
## [drone, airframe]; freeing the drone frees the airframe with it.
static func _sim_airframe(catalog: PartsCatalog, degrees: float) -> Array:
	var written := AssemblyTweaks.new()
	written.set_mm(AssemblyTweaks.CAMERA_TILT, degrees)
	written.save(SAVE_PATH)
	var tweaks := AssemblyTweaks.load_from(SAVE_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

	var drone := Node3D.new()
	var airframe := AirframeModel.new()
	drone.add_child(airframe)
	airframe.rebuild(_build(catalog), tweaks)
	return [drone, airframe]


## A camera standing in for main.tscn's, carrying the chase lens it authors.
static func _scene_camera() -> Camera3D:
	var camera := Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.02
	camera.far = 600.0
	return camera


## THE V3 CLAIM. With the aircraft dead level, the lens Sim flies must look above the horizon by
## EXACTLY the tilt the builder saved — elevation = asin(forward.y), compared with the number typed
## in, not with anything read off the camera node. Checked at 35 deg and at 0, because a lens that
## always looked 35 deg up would pass the first alone.
##
## No code was added to FpvView to make this pass: the lens is `world_transform_of(_eye)`, and the eye
## was tipped in V2. This test is the proof that "inherits" is true rather than assumed.
##
## MUTATION (run for V3): disconnect the tilt from the eye — let ComponentMesh tip the Body and Lens
## but not the Eye. The drawing still looks tilted and the feed flies level; this goes red.
static func _a_level_aircraft_looks_above_the_horizon_by_the_tilt(catalog: PartsCatalog) -> TestResult:
	var problems: Array[String] = []
	var seen: Array[String] = []
	for degrees in [35.0, 0.0]:
		var pair := _sim_airframe(catalog, degrees)
		var drone: Node3D = pair[0]
		var airframe: AirframeModel = pair[1]
		var view := FpvView.new()
		var camera := _scene_camera()
		view.attach(airframe.camera_eye())
		view.toggle_main()
		view.place_lenses(camera, Transform3D.IDENTITY)

		var forward: Vector3 = (-camera.transform.basis.z).normalized()
		var elevation := rad_to_deg(asin(forward.y))
		var is_fpv := camera.fov == FpvView.PLACEHOLDER_FOV_DEG
		seen.append("%s° saved -> lens %.4f° above the horizon" % [degrees, elevation])
		if not is_fpv:
			problems.append("the main camera is not wearing the FPV lens at %s deg" % degrees)
		if absf(elevation - degrees) > 1e-4:
			problems.append("saved %s deg, the lens looks %.4f deg up" % [degrees, elevation])
		if degrees > 0.0 and not forward.y > 0.0:
			problems.append("at %s deg the lens looks DOWN" % degrees)
		if absf(forward.x) > EPS:
			problems.append("the lens yawed off the centreline (%s)" % forward)

		drone.free()
		view.free()
		camera.free()

	return TestResult.new(
		"a level aircraft's FPV lens looks above the horizon by exactly the saved tilt",
		problems.is_empty(),
		"%s%s" % ["; ".join(seen), "" if problems.is_empty() else " — " + str(problems)])


## The caption states the builder's number in both modes, and it is the number the lens is actually
## flying — `tilt_deg()` reads the eye, so under the V3 mutation the caption says 0 over a level feed
## rather than 35 over one. It never says "no tilt" again.
static func _the_caption_states_the_builders_uptilt(catalog: PartsCatalog) -> TestResult:
	var pair := _sim_airframe(catalog, 35.0)
	var drone: Node3D = pair[0]
	var airframe: AirframeModel = pair[1]
	var view := FpvView.new()
	view.attach(airframe.camera_eye())
	var inset := view.caption_text()
	view.toggle_main()
	var full := view.caption_text()
	var read := view.tilt_deg()
	drone.free()
	view.free()

	return TestResult.new(
		"the FPV caption states the builder's uptilt in both modes, read off the lens",
		inset.contains("uptilt 35°") and full.contains("uptilt 35°")
			and not inset.contains("no tilt") and not full.contains("no tilt")
			and absf(read - 35.0) < 1e-4,
		"inset: %s | full: %s | tilt_deg() %.4f" % [inset, full, read])


## The runtime checks above run main.gd's two lines; this one holds main.gd to BEING those two
## lines. If Sim ever stops reading the tweaks file, or rebuilds its airframe without it, it flies
## Build's 25 deg default whatever the builder saved — which looks entirely plausible in the air
## and is exactly the kind of wrong nobody notices. Counts what it read, so a moved file fails.
static func _sim_builds_its_airframe_from_the_saved_tweaks() -> TestResult:
	var path := "res://src/scenes/main.gd"
	var source := FileAccess.get_file_as_string(path)
	var reads := source.contains("AssemblyTweaks.load_from()")
	var rebuilds := source.contains("airframe.rebuild(build, tweaks)")
	var attaches := source.contains("fpv_view.attach(airframe.camera_eye())")
	return TestResult.new(
		"Sim reads the saved tweaks and rebuilds the airframe it flies FPV from with them",
		source.length() > 0 and reads and rebuilds and attaches,
		"%s: %d chars read; load_from %s, rebuild(build, tweaks) %s, attach eye %s" % [
			path, source.length(), reads, rebuilds, attaches])
