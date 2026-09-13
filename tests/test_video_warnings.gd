class_name TestVideoWarnings
extends RefCounted
## `VideoPlausibility` — video-room design §3, slice V4.
##
## THE CLEARANCE FIXTURE IS CHOSEN SO ONLY THE TILT CAN EXPLAIN IT. A nano camera (14 mm long,
## 15 mm tall) behind standoffs raised to 28 mm, which leaves 18 mm between the plates' faces: level
## it stands 15 mm and fits, at 25° it stands 14·sin 25° + 15·cos 25° = 19.5 mm and does not. So a
## check that measured the camera untilted — design §3's own mutation — reads 15 mm, fits, and goes
## silent. The oracle below is that sin/cos, written out, so it is not the AABB transform checking
## itself.
##
## A SECTION THAT DIES IS INVISIBLE (see test_camera_tilt.gd's header), so sections are collected
## into a dictionary and the last check asserts none came back empty.

const NANO := "cam_nano_analog"
## 28 mm standoffs less one 10 mm lumped plate thickness: 18 mm between the faces.
const RAISED_GAP_M := 0.028


static func run() -> Array:
	var catalog := PartsCatalog.load_default()
	var sections := {
		"fixtures": [_the_fixtures_are_really_in_the_catalog(catalog)],
		"tilt fires": [_a_camera_that_fits_level_does_not_fit_tipped_up(catalog)],
		"level silent": [_the_same_camera_level_says_nothing(catalog)],
		"default gap silent": [_a_camera_that_does_not_fit_level_is_not_blamed_on_the_tilt(catalog)],
		"moulded silent": [_a_moulded_frame_has_no_top_plate(catalog)],
		"registered": [_build_warnings_carries_it(catalog)],
		"drawing agrees": [_the_drawn_camera_tips_with_the_same_rotation(catalog)],
		"vtx": _a_transmitter_with_no_antenna_is_said_and_nothing_else_is(catalog),
	}

	var results: Array = []
	var empty: Array[String] = []
	for section in sections:
		var got: Array = sections[section]
		if got.is_empty() or got.has(null):
			empty.append(section)
		results.append_array(got.filter(func(r): return r != null))
	results.append(TestResult.new(
		"every video-warning section ran and returned its checks",
		empty.is_empty(),
		"%d sections%s" % [sections.size(), "" if empty.is_empty() else " — empty: " + str(empty)]))
	return results


static func _build(catalog: PartsCatalog, components: Dictionary, frame_id: String = ReferenceBuild.FRAME_ID) -> Build:
	return Build.from_ids(catalog, frame_id, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, Build.DEFAULT_ESC_ID,
		Build.DEFAULT_FC_ID, components)


static func _nano_build(catalog: PartsCatalog, gap_m: float, tilt_deg: float,
		frame_id: String = ReferenceBuild.FRAME_ID) -> Build:
	var build := _build(catalog, {"camera": NANO}, frame_id)
	build.set_assembly({"plate_gap_m": gap_m, "camera_tilt_deg": tilt_deg})
	return build


static func _find(warnings: Array[BuildWarning], id: StringName) -> BuildWarning:
	for warning in warnings:
		if warning.id == id:
			return warning
	return null


## The vacuity guard. A renamed camera would fit the default micro instead, which does not fit
## level in 18 mm, and every "stays silent" row below would pass for that reason instead.
static func _the_fixtures_are_really_in_the_catalog(catalog: PartsCatalog) -> TestResult:
	var nano := catalog.get_part(NANO)
	var size := Build.component_size_of(nano)
	return TestResult.new(
		"the nano camera is in the catalog at 14 mm long and 15 mm tall",
		not nano.is_empty() and is_equal_approx(size.z, 0.014) and is_equal_approx(size.y, 0.015),
		"size %s" % size)


static func _a_camera_that_fits_level_does_not_fit_tipped_up(catalog: PartsCatalog) -> TestResult:
	var build := _nano_build(catalog, RAISED_GAP_M, 25.0)
	var warning := _find(VideoPlausibility.warnings_for(build), &"camera_tilt_into_top_plate")
	var theta := deg_to_rad(25.0)
	var oracle_mm := 14.0 * sin(theta) + 15.0 * cos(theta)
	var passed := warning != null \
		and warning.severity == BuildWarning.Severity.LIMITING \
		and absf(float(warning.values.get("standing_mm", NAN)) - oracle_mm) < 1e-3 \
		and absf(float(warning.values.get("clear_mm", NAN)) - 18.0) < 1e-3 \
		and absf(float(warning.values.get("level_mm", NAN)) - 15.0) < 1e-3 \
		and warning.message.contains("19.5 mm") and warning.message.contains("18.0 mm")
	return TestResult.new(
		"a nano camera that fits 18 mm level is said to strike the top plate at 25° (LIMITING, numbers quoted)",
		passed,
		"no warning" if warning == null else "%s — oracle %.2f mm" % [warning.message, oracle_mm])


static func _the_same_camera_level_says_nothing(catalog: PartsCatalog) -> TestResult:
	var build := _nano_build(catalog, RAISED_GAP_M, 0.0)
	var warning := _find(VideoPlausibility.warnings_for(build), &"camera_tilt_into_top_plate")
	return TestResult.new(
		"the same camera, level, in the same gap, says nothing",
		warning == null, "fired: %s" % (warning.message if warning != null else "no"))


## THE DELIBERATE SILENCE, pinned. At the default standoffs the plates leave 5 mm, the nano stands
## 15 mm level, and the gap is a lumped ratio rather than a published figure — see the header. If
## this starts firing, every aircraft in the app has grown an amber line.
static func _a_camera_that_does_not_fit_level_is_not_blamed_on_the_tilt(catalog: PartsCatalog) -> TestResult:
	var reference_build := _build(catalog, {})
	var nano := _nano_build(catalog, -1.0, 40.0)
	var ids := []
	for build in [reference_build, nano]:
		for warning in VideoPlausibility.warnings_for(build):
			ids.append(warning.id)
	return TestResult.new(
		"a camera taller than the default gap even level is not said — the reference build and a 40° nano stay silent",
		not ids.has(&"camera_tilt_into_top_plate"), "ids %s" % [ids])


static func _a_moulded_frame_has_no_top_plate(catalog: PartsCatalog) -> TestResult:
	var build := _nano_build(catalog, RAISED_GAP_M, 60.0, "frame_65mm_whoop")
	var moulded := str(build.frame.get("specs", {}).get("construction", "")) == "moulded"
	var warning := _find(VideoPlausibility.warnings_for(build), &"camera_tilt_into_top_plate")
	return TestResult.new(
		"a moulded whoop has no top plate, and a 60° camera on it says nothing",
		moulded and warning == null, "moulded=%s, fired=%s" % [moulded, warning != null])


## Registered the way ControlPlausibility is — through Build.warnings(), which is what every panel
## shows. Removing the append line is the mutation.
static func _build_warnings_carries_it(catalog: PartsCatalog) -> TestResult:
	var build := _nano_build(catalog, RAISED_GAP_M, 25.0)
	var warning := _find(build.warnings(), &"camera_tilt_into_top_plate")
	return TestResult.new(
		"Build.warnings() carries the clearance warning", warning != null,
		"%d warnings" % build.warnings().size())


## The drawing and the check tip the camera with ONE rotation. The drawn silhouette at 40° must be
## taller than the level box (the tilt reached the mesh) and no taller than the published box the
## warning measures (the lens barrel is narrower than the body, so the drawing is the shorter).
static func _the_drawn_camera_tips_with_the_same_rotation(catalog: PartsCatalog) -> TestResult:
	var build := _build(catalog, {})
	var tweaks := AssemblyTweaks.new()
	tweaks.set_mm(AssemblyTweaks.CAMERA_TILT, 40.0)
	var airframe := AirframeModel.new()
	airframe.rebuild(build, tweaks)
	var drawn_m := airframe.component_aabb_m("camera").size.y
	airframe.free()
	var camera: Dictionary = build.components["camera"]
	var level_m := Build.camera_standing_height_m(camera, 0.0)
	var published_m := Build.camera_standing_height_m(camera, 40.0)
	return TestResult.new(
		"at 40° the drawn camera stands taller than level and no taller than the published box",
		drawn_m > level_m + 0.001 and drawn_m <= published_m + 1e-6,
		"drawn %.2f mm, level %.2f mm, published tipped %.2f mm" % [
			drawn_m * 1000.0, level_m * 1000.0, published_m * 1000.0])


static func _a_transmitter_with_no_antenna_is_said_and_nothing_else_is(catalog: PartsCatalog) -> Array:
	var cases := [
		{"what": "a VTX with no antenna", "components": {"antenna": ""}, "fires": true},
		{"what": "the reference build (VTX and antenna)", "components": {}, "fires": false},
		{"what": "no video payload at all", "components": {"camera": "", "vtx": "", "antenna": ""}, "fires": false},
		{"what": "a camera with no VTX (the whoop-AIO shape)", "components": {"vtx": "", "antenna": ""}, "fires": false},
	]
	var results: Array = []
	for case in cases:
		var build := _build(catalog, case["components"])
		var warning := _find(build.warnings(), &"vtx_without_antenna")
		var ok: bool = (warning != null) == bool(case["fires"])
		if warning != null and bool(case["fires"]):
			ok = warning.severity == BuildWarning.Severity.CHARACTERISTIC \
				and warning.message.contains("Lothal cannot tell")
		results.append(TestResult.new(
			"%s %s vtx_without_antenna" % [case["what"], "says" if case["fires"] else "does not say"],
			ok, "fired: %s" % (warning.message if warning != null else "no")))
	return results
