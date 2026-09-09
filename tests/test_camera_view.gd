class_name TestCameraView
extends RefCounted
## P10c's deferred half: what the fitted camera is looking past —
## plans/2026-08-26-propulsion-room-design.md §5, and §4.2 for why it was left.
##
## ## What this file has to prove, given that the plan's own proof obligation is unmeetable
##
## §1's P10c row states the proof as: "the frustum check with a fitted guard FIRES on the reference
## cinewhoop (guard sits in the camera cone) and DOES NOT FIRE on the freestyle build (guard, if
## fitted, is behind the arm plane)."
##
## Measured, that is not true, and `_the_two_five_inch_guards_are_not_separated` pins it: the
## cinewhoop duct enters the view at 19.9 deg off centre and the freestyle bumper at 20.3 deg.
## Four tenths of a degree apart. The reason is geometry rather than an error in either part — a
## ring's centre sits at arm/sqrt(2) laterally and its own outer radius is very nearly that same
## number, so the inner edge of the front ring lands within a few millimetres of the centreline on
## BOTH builds (cinewhoop 96/sqrt(2) - 68 = -0.1 mm, freestyle 110/sqrt(2) - 72 = +5.8 mm).
##
## So no threshold separates them, and a constant chosen so that one fires and the other does not
## would be a bound set after seeing the data, which CONTINUE-HERE §9 names as a description
## wearing a bound's clothes. The check therefore reports the ANGLE and fires on both, and this
## test asserts the two are close together so that nobody can later reintroduce the discriminator
## the plan predicted without this file going red.
##
## ## The mutations, each run in the CODE and confirmed red
##
##   - vertices instead of edges in `min_off_axis_deg`      -> `_the_minimum_is_over_edges_not_corners`
##   - `global_transform` instead of local positions        -> `_the_eye_is_measured_without_a_tree`
##   - plate height captured at build time                  -> `_plate_heights_follow_the_seating`
##   - guard polygons centred on the node's own position    -> `_each_guard_ring_sits_on_its_own_motor`

const EPS := 1e-9
## Degrees. See `_dead_ahead_is_zero_and_behind_is_180` — this is the float32 floor of the
## Vector3s the angles are built from, not a judgement about how accurate the answer should be.
const DEG_EPS := 1e-4


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append(_dead_ahead_is_zero_and_behind_is_180())
	results.append(_the_minimum_is_over_edges_not_corners())
	results.append(_an_empty_polygon_is_never_in_shot())
	results.append(_the_eye_is_measured_without_a_tree(catalog))
	results.append(_plate_heights_follow_the_seating(catalog))
	results.append(_the_arms_are_the_plate_outlines(catalog))
	results.append(_a_moulded_frame_publishes_no_outline(catalog))
	results.append(_each_guard_ring_sits_on_its_own_motor(catalog))
	results.append(_the_warning_names_the_closest_part(catalog))
	results.append(_the_warning_is_characteristic_not_a_fault(catalog))
	results.append(_a_build_that_is_only_itself_says_nothing(catalog))
	results.append(_a_moulded_frame_has_no_silhouette_to_hide_behind(catalog))
	results.append(_the_two_five_inch_guards_are_not_separated(catalog))
	results.append(_no_field_of_view_is_read_anywhere())

	return results


# ---------------------------------------------------------------------------
# The geometry, on its own
# ---------------------------------------------------------------------------

static func _dead_ahead_is_zero_and_behind_is_180() -> TestResult:
	var eye := Vector3(0.1, -0.2, 0.3)
	var forward := Vector3(0.0, 0.0, -1.0)

	var ahead := CameraView.off_axis_deg(eye, forward, eye + Vector3(0.0, 0.0, -1.0))
	var behind := CameraView.off_axis_deg(eye, forward, eye + Vector3(0.0, 0.0, 1.0))
	var beside := CameraView.off_axis_deg(eye, forward, eye + Vector3(1.0, 0.0, -1.0))
	# A point AT the eye has no direction. 180 rather than 0, because 0 would claim the most
	# intrusive obstruction possible from the least information available.
	var at_the_eye := CameraView.off_axis_deg(eye, forward, eye)

	# 1e-4 degrees, not zero: `Vector3` is single precision, so a direction built from one carries
	# ~1e-7 relative error and the exactly-behind case comes back as 179.999991. Measured, then
	# bounded an order above what was measured — the same posture P10f took at the mm boundary.
	var passed := absf(ahead) < DEG_EPS and absf(behind - 180.0) < DEG_EPS \
		and absf(beside - 45.0) < DEG_EPS and absf(at_the_eye - 180.0) < DEG_EPS

	return TestResult.new(
		"off-axis angle is 0 dead ahead, 180 behind, 45 on the diagonal, 180 at the eye itself",
		passed,
		"ahead %.6f, behind %.6f, beside %.6f, at eye %.6f" % [ahead, behind, beside, at_the_eye]
	)


## THE LOAD-BEARING GEOMETRY CHECK. A silhouette's nearest approach to the centreline is normally
## in the MIDDLE of an edge, not at a corner, and a plate outline has four corners and four long
## runs between them. A corner-only minimum reports the aircraft as further out of shot than it is,
## which is the one direction this check must never fail in.
##
## The segment here crosses the centreline one metre ahead: its ends are at 45 deg and its middle
## is at 0. A vertices-only implementation returns 45 — the mutation was made in the CODE and this
## check goes red by the full 45 degrees, which is not a tolerance question.
static func _the_minimum_is_over_edges_not_corners() -> TestResult:
	var eye := Vector3.ZERO
	var forward := Vector3(0.0, 0.0, -1.0)
	var crossing := PackedVector3Array([Vector3(-1.0, 0.0, -1.0), Vector3(1.0, 0.0, -1.0)])

	var over_edges := CameraView.min_off_axis_deg(eye, forward, crossing)

	# The mutation, computed here as well as run in the code, so the number this check defends is
	# visible in its own detail line rather than being a bare "0.0 == 0.0".
	var over_corners := INF
	for point in crossing:
		over_corners = minf(over_corners, CameraView.off_axis_deg(eye, forward, point))

	var passed := absf(over_edges) < DEG_EPS and absf(over_corners - 45.0) < DEG_EPS

	return TestResult.new(
		"the minimum is taken over the edges, not the corners",
		passed,
		"edges %.6f deg, corners-only %.6f deg (the mutation)" % [over_edges, over_corners]
	)


static func _an_empty_polygon_is_never_in_shot() -> TestResult:
	var angle := CameraView.min_off_axis_deg(Vector3.ZERO, Vector3(0.0, 0.0, -1.0), PackedVector3Array())
	return TestResult.new(
		"a part that is not fitted is INF off-axis, so it sorts last rather than first",
		angle == INF,
		"angle %s" % angle
	)


# ---------------------------------------------------------------------------
# On a real aircraft
# ---------------------------------------------------------------------------

static func _build(catalog: PartsCatalog, frame_id: String, guard_id: String) -> Build:
	return Build.from_ids(catalog, frame_id, "motor_2207_1960kv", "prop_5x43x3",
		ReferenceBuild.BATTERY_ID, Build.DEFAULT_ESC_ID, Build.DEFAULT_FC_ID, {}, null, guard_id)


## The whole reason `camera_eye_m()` exists rather than callers reading `camera_eye().global_transform`.
##
## An `AirframeModel` built outside the tree — which is how every test in this project builds one,
## and how `AssemblyPanel` reads one before it is shown — returns IDENTITY from `global_transform`.
## Not an error, not a zero: a transform that looks perfectly valid and places the lens on the
## aircraft's origin, which is inside the stack rather than at the nose. Every angle measured from
## it would be wrong and none of them would look wrong.
##
## So this asserts the eye is where the node chain actually puts it AND that the global transform
## disagrees — the second half is what makes the first half mean something.
static func _the_eye_is_measured_without_a_tree(catalog: PartsCatalog) -> TestResult:
	var airframe := AirframeModel.new()
	airframe.rebuild(_build(catalog, "frame_5in_freestyle", ""))

	var eye_m = airframe.camera_eye_m()
	var mesh: ComponentMesh = airframe.component_meshes["camera"]
	var eye_node := mesh.get_node_or_null("Eye") as Node3D
	var expected: Vector3 = mesh.position + eye_node.position
	var global_says := eye_node.global_transform.origin

	airframe.free()

	var passed := eye_m != null \
		and (eye_m as Vector3).distance_to(expected) < EPS \
		and (eye_m as Vector3).length() > 0.01 \
		and global_says == Vector3.ZERO

	return TestResult.new(
		"the eye is read off local positions, and global_transform outside the tree would say the origin",
		passed,
		"eye %v, node chain %v, global_transform says %v" % [eye_m, expected, global_says]
	)


## A plate's height is READ when asked, not captured when built, because
## `_seat_top_plate_on_its_mount` moves both structural plates after `_build_plates` has run.
##
## No shipping preset shows the difference — with exactly two structural plates spanning the
## document's extremes, the pre-seat centre already lands on ±gap/2. It appears the moment a
## document carries a plate OUTSIDE that pair, which the Airframe room lets a builder draw: the
## normalisation is then computed against the outer plate's height and the top plate seats
## somewhere else entirely.
##
## Measured here: the top plate seats at +7.5 mm, where a build-time capture reports -2.45 mm —
## a centimetre, and on the wrong side of the aircraft.
static func _plate_heights_follow_the_seating(catalog: PartsCatalog) -> TestResult:
	var frame := catalog.get_part("frame_5in_freestyle")
	var document := AirframeDocument.from_catalog_frame(frame)
	var square := PackedVector2Array([
		Vector2(-20.0, -20.0), Vector2(20.0, -20.0), Vector2(20.0, 20.0), Vector2(-20.0, 20.0)])
	document.plates.append(
		AirframeDocument.make_plate(square, [], 2.0, 60.0, AirframeDocument.ROLE_MID))

	var gap := 0.015
	var frame_model := FrameModel.new()
	frame_model.rebuild_document(document, frame, gap)

	var top_y := INF
	var bottom_y := INF
	for record in frame_model.plate_polygons_m():
		if record["name"] == "PlateTop":
			top_y = record["y_m"]
		elif record["name"] == "PlateBottom":
			bottom_y = record["y_m"]

	# What a build-time capture would have recorded, derived the way `_build_plates` derives it
	# before the seating runs.
	var centres := PackedFloat64Array()
	for plate in document.plates:
		centres.append(AirframeDocument.plate_z_mm(plate)
			+ AirframeDocument.plate_thickness_mm(plate) * 0.5)
	var lowest := centres[0]
	var highest := centres[0]
	for value in centres:
		lowest = minf(lowest, value)
		highest = maxf(highest, value)
	var middle := (lowest + highest) * 0.5
	var stretch := (gap * 1000.0) / (highest - lowest)
	var top_before_seating := ((AirframeDocument.plate_z_mm(document.plates[5])
		+ AirframeDocument.plate_thickness_mm(document.plates[5]) * 0.5) - middle) * stretch / 1000.0

	frame_model.free()

	var passed := absf(top_y - gap * 0.5) < 1e-6 \
		and absf(bottom_y + gap * 0.5) < 1e-6 \
		and absf(top_y - top_before_seating) > 0.005

	return TestResult.new(
		"a plate's published height is where it was SEATED, not where it was built",
		passed,
		"top seated %.6f m (expected %.6f), bottom %.6f, build-time capture would say %.6f" % [
			top_y, gap * 0.5, bottom_y, top_before_seating]
	)


## The arms are not separate geometry to go and find — they are part of a plate's outline, which is
## §7.2's whole claim. So the obstruction set for a plate frame carries the four arm plates by name,
## and a check that quietly published only the two structural plates would leave the parts closest
## to the camera unmeasured.
static func _the_arms_are_the_plate_outlines(catalog: PartsCatalog) -> TestResult:
	var airframe := AirframeModel.new()
	airframe.rebuild(_build(catalog, "frame_5in_freestyle", ""))

	var obstructions := airframe.camera_obstruction_points_m()
	var arm_names: Array = []
	for key in obstructions:
		if str(key).begins_with("Plate_arm"):
			arm_names.append(key)
	var has_structural := obstructions.has("PlateTop") and obstructions.has("PlateBottom")
	var every_arm_is_a_closed_quad := true
	for key in arm_names:
		if (obstructions[key] as PackedVector3Array).size() != 4:
			every_arm_is_a_closed_quad = false

	airframe.free()

	var passed := arm_names.size() == 4 and has_structural and every_arm_is_a_closed_quad

	return TestResult.new(
		"the four arms reach the check as plate outlines, alongside both structural plates",
		passed,
		"%d arm plates, structural present: %s, all quads: %s" % [
			arm_names.size(), has_structural, every_arm_is_a_closed_quad]
	)


## A moulded frame has NO outline to publish, and saying so is the honest answer rather than a
## failure. `FrameModel` draws a stand-in body for exactly these frames because the plate model
## cannot describe the shape, so there is no silhouette to measure and the check must not invent
## one. Guarded against vacuity by asserting in the same breath that a plate frame does publish —
## without that, this check would pass against a version that published nothing for anything.
static func _a_moulded_frame_publishes_no_outline(catalog: PartsCatalog) -> TestResult:
	var moulded := AirframeModel.new()
	moulded.rebuild(_build(catalog, "frame_65mm_whoop", ""))
	var moulded_count := moulded.camera_obstruction_points_m().size()
	var moulded_warnings := moulded.camera_view_warnings().size()
	moulded.free()

	var plated := AirframeModel.new()
	plated.rebuild(_build(catalog, "frame_5in_freestyle", ""))
	var plated_count := plated.camera_obstruction_points_m().size()
	plated.free()

	var passed := moulded_count == 0 and moulded_warnings == 0 and plated_count == 6

	return TestResult.new(
		"a moulded frame reports no silhouette and says nothing, while a plate frame reports six",
		passed,
		"moulded %d obstructions / %d warnings, plated %d obstructions" % [
			moulded_count, moulded_warnings, plated_count]
	)


## The 2026-08-28 review's frame bug, now asserted through the caller it was waiting for. A version
## that centred each ring on the `GuardMesh` node's own position would put all four on the
## aircraft's centre, and every one of them would then report the SAME angle. The front pair and the
## rear pair must differ, and by a lot: the front rings are ahead of the lens and the rear ones are
## behind it.
static func _each_guard_ring_sits_on_its_own_motor(catalog: PartsCatalog) -> TestResult:
	var airframe := AirframeModel.new()
	airframe.rebuild(_build(catalog, "frame_5in_cinewhoop", "guard_duct_5in_cinewhoop"))

	var report := CameraView.off_axis_report(
		airframe.camera_eye_m(), airframe.camera_boresight(), airframe.camera_obstruction_points_m())

	var guard_angles := PackedFloat64Array()
	for key in report:
		if str(key).begins_with("guard "):
			guard_angles.append(report[key])
	guard_angles.sort()

	airframe.free()

	# Two forward, two aft, and the two groups an aircraft's length apart in angle.
	var passed := guard_angles.size() == 4 \
		and absf(guard_angles[0] - guard_angles[1]) < 1e-6 \
		and absf(guard_angles[2] - guard_angles[3]) < 1e-6 \
		and guard_angles[0] < 90.0 and guard_angles[3] > 90.0 \
		and (guard_angles[3] - guard_angles[0]) > 45.0

	return TestResult.new(
		"each guard ring is measured on its own motor — the front pair forward, the rear pair behind",
		passed,
		"angles %s" % [guard_angles]
	)


static func _the_warning_names_the_closest_part(catalog: PartsCatalog) -> TestResult:
	var airframe := AirframeModel.new()
	airframe.rebuild(_build(catalog, "frame_5in_cinewhoop", "guard_duct_5in_cinewhoop"))

	var warnings := airframe.camera_view_warnings()
	var passed := warnings.size() == 1
	var detail := "no warning"
	if passed:
		var warning := warnings[0]
		var values := warning.values
		var closest_deg: float = values["closest_deg"]
		var frame_deg: float = values["frame_deg"]
		# The closest thing on a cinewhoop is a duct, not the frame — that is what a cinewhoop IS.
		passed = warning.id == &"camera_obstruction" \
			and str(values["closest_name"]).begins_with("guard ") \
			and closest_deg > 19.0 and closest_deg < 21.0 \
			and frame_deg > 50.0 and frame_deg < 60.0 \
			and int(values["worse_count"]) == 2 \
			and warning.message.contains("geometry rather than a verdict")
		detail = "%s at %.2f deg against the frame's %.2f, %d worse — \"%s\"" % [
			values["closest_name"], closest_deg, frame_deg, values["worse_count"], warning.message]

	airframe.free()
	return TestResult.new(
		"the warning names the nearest obstruction, its angle, and refuses to call it a verdict",
		passed, detail
	)


## Severity, and it is the point rather than a detail. Ducts in the corners of the picture are what
## a cinewhoop is FOR. `BuildWarning`'s header names this exact failure — a cinelifter builder told
## they had made a mistake for correctly building a cinelifter — and the rule is that a warning is
## only LIMITING or IMPOSSIBLE where there is a boundary in the physics to point at. There is none
## here: no lens angle is published, so nothing has been exceeded.
static func _the_warning_is_characteristic_not_a_fault(catalog: PartsCatalog) -> TestResult:
	var airframe := AirframeModel.new()
	airframe.rebuild(_build(catalog, "frame_5in_cinewhoop", "guard_duct_5in_cinewhoop"))
	var warnings := airframe.camera_view_warnings()
	var found := warnings.size() == 1
	var severity := warnings[0].severity if found else BuildWarning.Severity.IMPOSSIBLE
	airframe.free()

	return TestResult.new(
		"a part in view is CHARACTERISTIC — a description of the build, never a fault",
		found and severity == BuildWarning.Severity.CHARACTERISTIC,
		"%d warning(s), severity %d (CHARACTERISTIC is %d)" % [
			warnings.size(), severity, BuildWarning.Severity.CHARACTERISTIC]
	)


## AN AIRCRAFT THAT IS ONLY ITSELF SAYS NOTHING, and this is the check that made the comparison
## against the frame necessary rather than optional.
##
## The first version of this warning reported everything forward of the lens plane. It fired on the
## REFERENCE BUILD — a plain 5" freestyle X with nothing fitted — because the arms of a standard X
## sit ~54 deg off centre, which a real 150 deg lens does see. It was true, and it was noise: it
## broke `test_lab`'s "the reference build fits and warns about nothing" by adding an amber block to
## every aircraft in the app, which is the same objection that keeps the propellers out of the
## obstruction set entirely.
##
## Both halves are asserted, and the second is what stops this passing for the wrong reason: the
## reference build HAS a frame in view (its arms are forward of the lens) and still says nothing,
## because nothing fitted is worse than the aircraft already is.
static func _a_build_that_is_only_itself_says_nothing(catalog: PartsCatalog) -> TestResult:
	var airframe := AirframeModel.new()
	airframe.rebuild(_build(catalog, "frame_5in_freestyle", ""))
	var warnings := airframe.camera_view_warnings()
	var report := CameraView.off_axis_report(
		airframe.camera_eye_m(), airframe.camera_boresight(), airframe.camera_obstruction_points_m())
	var arms_are_in_view := false
	for key in report:
		if str(key).begins_with("Plate_arm") and report[key] < 90.0:
			arms_are_in_view = true
	var eye_exists = airframe.camera_eye_m() != null
	airframe.free()

	return TestResult.new(
		"the reference build says nothing, though its own arms ARE forward of the lens",
		warnings.is_empty() and arms_are_in_view and eye_exists,
		"%d warnings, arms forward of the lens: %s, camera fitted: %s" % [
			warnings.size(), arms_are_in_view, eye_exists]
	)


## A moulded whoop has no plate silhouette at all, so a fitted guard has nothing to hide behind and
## the sentence says so instead of comparing against an INF that would read as "the frame is fine".
static func _a_moulded_frame_has_no_silhouette_to_hide_behind(catalog: PartsCatalog) -> TestResult:
	var airframe := AirframeModel.new()
	airframe.rebuild(_build(catalog, "frame_65mm_whoop", "guard_duct_3in_tpu"))
	var warnings := airframe.camera_view_warnings()
	var says_it := warnings.size() == 1 \
		and warnings[0].message.contains("no plate silhouette to hide behind") \
		and is_inf(warnings[0].values["frame_deg"])
	var detail := warnings[0].message if warnings.size() == 1 else "%d warnings" % warnings.size()
	airframe.free()

	return TestResult.new(
		"a moulded frame offers no silhouette, and the warning says that rather than comparing to INF",
		says_it, detail
	)


## THE PLAN'S PREDICTED DISCRIMINATOR DOES NOT EXIST, and this pins it so that it cannot be
## quietly reintroduced. See this file's header for the geometry. The two 5" guards land within a
## degree of each other, so no threshold fires on one and not the other, and the check reports the
## angle instead of pretending to a verdict it cannot reach.
static func _the_two_five_inch_guards_are_not_separated(catalog: PartsCatalog) -> TestResult:
	var angles := {}
	for pair in [["frame_5in_cinewhoop", "guard_duct_5in_cinewhoop"],
			["frame_5in_freestyle", "guard_bumper_5in_abs"]]:
		var airframe := AirframeModel.new()
		airframe.rebuild(_build(catalog, pair[0], pair[1]))
		var warnings := airframe.camera_view_warnings()
		angles[pair[0]] = float(warnings[0].values["closest_deg"]) if warnings.size() == 1 else NAN
		# And on both builds the nearest thing is the guard, not the frame.
		if warnings.size() == 1 and not str(warnings[0].values["closest_name"]).begins_with("guard "):
			angles[pair[0]] = NAN
		airframe.free()

	var cinewhoop: float = angles["frame_5in_cinewhoop"]
	var freestyle: float = angles["frame_5in_freestyle"]
	var separation := absf(cinewhoop - freestyle)

	return TestResult.new(
		"both 5\" guards are in view within a degree of each other — no threshold separates them",
		not is_nan(cinewhoop) and not is_nan(freestyle) \
			and cinewhoop < 90.0 and freestyle < 90.0 and separation < 1.0,
		"cinewhoop duct %.2f deg, freestyle bumper %.2f deg, apart by %.2f deg" % [
			cinewhoop, freestyle, separation]
	)


## The refusal, asserted against the SOURCE rather than against behaviour, in the posture
## test_prop_rotation.gd uses for "this class holds no speed". A field of view is exactly the kind
## of number that gets added later to make a check feel more decisive, and the moment one appears
## here the warning becomes a claim about a lens nobody measured.
static func _no_field_of_view_is_read_anywhere() -> TestResult:
	var offenders: Array[String] = []
	for path in ["res://src/lab/camera_view.gd", "res://src/lab/airframe_model.gd"]:
		var file := FileAccess.open(path, FileAccess.READ)
		var line_number := 0
		while not file.eof_reached():
			var line := file.get_line()
			line_number += 1
			var code := line.strip_edges()
			if code.begins_with("#"):
				continue
			if code.contains("PLACEHOLDER_FOV_DEG") or code.contains("FpvView") \
					or code.contains(".fov") or code.contains("fov_deg"):
				offenders.append("%s:%d %s" % [path.get_file(), line_number, code])
		file.close()

	return TestResult.new(
		"neither the geometry nor the warning reads a field of view from anywhere",
		offenders.is_empty(),
		"offending lines: %s" % ("none" if offenders.is_empty() else str(offenders))
	)
