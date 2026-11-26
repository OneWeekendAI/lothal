class_name TestFrameConstants
extends RefCounted
## Plate thickness comes from the fitted frame (PLAN item 10): the drawn document's centre plates, else the
## catalogue's `plate_thickness_mm`, else Build.FRAME_PLATE_THICKNESS_M as a labelled typical — and only
## then. The stack mount PATTERN was already the frame's own (`specs.stack_mount`); the last block pins
## that the fit warnings quote it. Expected numbers are written HERE, from frames.json's published values
## (5" freestyle: 2.5 mm plates, 30.5x30.5; 3.5" freestyle: 2.0 mm, 20x20; 65 mm whoop lite: states none).

const EPS := 1.0e-9
const TYPICAL_M := 0.010

static func run() -> Array:
	var catalog := PartsCatalog.load_default()
	return [
		_catalogue_thickness_is_read(catalog),
		_catalogue_thickness_sets_the_default_gap(catalog),
		_catalogue_thickness_sets_the_stack_seat(catalog),
		_silent_frame_falls_back_to_the_typical(catalog),
		_thickness_reaches_the_inertia_box(catalog),
		_thickness_reaches_the_body_boxes(catalog),
		_thickness_reaches_the_drag_body_height(catalog),
		_drawn_thickness_overrides_the_catalogue(catalog),
		_an_edit_of_the_arms_alone_leaves_thickness_to_the_catalogue(catalog),
		_a_replacement_drawing_without_plates_does_not_inherit(catalog),
		_the_tweak_limits_follow_the_frame(catalog),
		_mismatched_fc_warns_with_the_frames_pattern(catalog),
		_matching_fc_is_silent(catalog),
		_a_drawn_pattern_is_quoted(catalog),
	]


static func _build(catalog: PartsCatalog, frame_id: String) -> Build:
	return Build.from_ids(catalog, frame_id, "motor_2207_1960kv", "prop_5x43x3", "battery_4s_1300")


## Relative to 1e-9 of the value: Vector3.is_equal_approx has an absolute floor larger than a 150 mm plate's inertia.
static func _close(a: Vector3, b: Vector3) -> bool:
	return absf(a.x - b.x) <= 1e-9 * absf(b.x) and absf(a.y - b.y) <= 1e-9 * absf(b.y) \
		and absf(a.z - b.z) <= 1e-9 * absf(b.z)


static func _warning(build: Build, id: StringName) -> BuildWarning:
	for w in build.warnings():
		if w.id == id:
			return w
	return null


static func _catalogue_thickness_is_read(catalog: PartsCatalog) -> TestResult:
	var b := _build(catalog, "frame_5in_freestyle")
	return TestResult.new("frame constants: a frame that states 2.5 mm plates is built with 2.5 mm",
		absf(b.plate_thickness_m() - 0.0025) < EPS, "got %.6f m" % b.plate_thickness_m())


static func _catalogue_thickness_sets_the_default_gap(catalog: PartsCatalog) -> TestResult:
	var b := _build(catalog, "frame_5in_freestyle")
	var top := MountLayout.by_id(b.mount_points(), "strap_top")
	var bottom := MountLayout.by_id(b.mount_points(), "stack")
	# gap = 1.5 t = 3.75 mm; the top plate's upper face is gap/2 + t/2 above the origin.
	var want_top := 0.00375 * 0.5 + 0.0025 * 0.5
	var want_stack := -0.00375 * 0.5 + 0.0025 * 0.5
	return TestResult.new("frame constants: the derived standoff gap is 1.5 x this frame's plate",
		absf(top.position.y - want_top) < EPS and absf(bottom.position.y - want_stack) < EPS,
		"top %.6f want %.6f, stack %.6f want %.6f" % [top.position.y, want_top, bottom.position.y, want_stack])


static func _catalogue_thickness_sets_the_stack_seat(catalog: PartsCatalog) -> TestResult:
	var thin := _build(catalog, "frame_5in_freestyle")
	var thick := _build(catalog, "frame_5in_freestyle")
	thick.set_frame_edit({"part_id": "frame_5in_freestyle", "mass_g": float(thick.frame["mass_g"]),
		"arm_mm": float(thick.frame["specs"]["arm_mm"]), "specs": {"plate_thickness_mm": 10.0}})
	var seat_thin := MountLayout.by_id(thin.mount_points(), "stack").position.y
	var seat_thick := MountLayout.by_id(thick.mount_points(), "stack").position.y
	# At the typical 10 mm the seat is -0.0025 (the pre-item-10 value); at 2.5 mm it is -0.000625.
	return TestResult.new("frame constants: the stack seat moves with the plate stock",
		absf(seat_thin - (-0.000625)) < EPS and absf(seat_thick - (-0.0025)) < EPS,
		"2.5 mm seat %.6f, 10 mm seat %.6f" % [seat_thin, seat_thick])


static func _silent_frame_falls_back_to_the_typical(catalog: PartsCatalog) -> TestResult:
	var b := _build(catalog, "frame_65mm_whoop_lite")
	var stated: bool = b.frame["specs"].has("plate_thickness_mm")
	var seat := MountLayout.by_id(b.mount_points(), "stack").position.y
	return TestResult.new("frame constants: a frame that states no plate stock gets the labelled 10 mm typical",
		not stated and absf(b.plate_thickness_m() - TYPICAL_M) < EPS and absf(seat - (-0.0025)) < EPS,
		"stated %s, t %.6f, seat %.6f" % [stated, b.plate_thickness_m(), seat])


static func _thickness_reaches_the_inertia_box(catalog: PartsCatalog) -> TestResult:
	var b := _build(catalog, "frame_5in_freestyle")
	var m := float(b.frame["mass_g"]) / 1000.0
	var plate := b.arm_m * Build.FRAME_PLATE_TO_ARM_RATIO
	var want := InertiaPrimitives.box(m, Vector3(plate, 0.0025, plate))
	var got := Vector3.ZERO
	for part in b.mass_parts():
		if (part as PartMass).label == "Frame":
			got = (part as PartMass).local_inertia_diag
	var typical := InertiaPrimitives.box(m, Vector3(plate, TYPICAL_M, plate))
	return TestResult.new("frame constants: the frame's inertia box is as thick as the frame's plates",
		_close(got, want) and not _close(got, typical), "got %s want %s" % [got, want])


static func _thickness_reaches_the_body_boxes(catalog: PartsCatalog) -> TestResult:
	var b := _build(catalog, "frame_5in_freestyle")
	var ok := false
	for box in b.body_boxes():
		if box["name"] == "Bottom plate":
			ok = absf((box["size"] as Vector3).y - 0.0025) < EPS
	return TestResult.new("frame constants: the drawn bottom plate box is the frame's thickness", ok, "")


static func _thickness_reaches_the_drag_body_height(catalog: PartsCatalog) -> TestResult:
	var thin := _build(catalog, "frame_5in_freestyle")
	var thick := _build(catalog, "frame_5in_freestyle")
	thick.set_frame_edit({"part_id": "frame_5in_freestyle", "mass_g": float(thick.frame["mass_g"]),
		"arm_mm": float(thick.frame["specs"]["arm_mm"]), "specs": {"plate_thickness_mm": 10.0}})
	# The body is pack + plate + stack tall; 7.5 mm more plate is 7.5 mm more body, across the pack's width.
	# drag_projected_areas_m2() is (side, top, front); front = body_w * body_h, side = body_l * body_h.
	var pack := thin.battery_size_m()
	var front := thick.drag_projected_areas_m2().z - thin.drag_projected_areas_m2().z
	var side := thick.drag_projected_areas_m2().x - thin.drag_projected_areas_m2().x
	var want_front := maxf(pack.x, Build.DRAG_MIN_BODY_M) * 0.0075
	var want_side := maxf(pack.z, Build.DRAG_MIN_BODY_M) * 0.0075
	return TestResult.new("frame constants: the drag body is as tall as this frame's plates make it",
		absf(front - want_front) < 1e-9 and absf(side - want_side) < 1e-9,
		"front grew %.9f want %.9f, side grew %.9f want %.9f" % [front, want_front, side, want_side])


static func _drawn_thickness_overrides_the_catalogue(catalog: PartsCatalog) -> TestResult:
	var frame := catalog.get_part("frame_5in_freestyle")
	var doc := AirframeDocument.from_catalog_frame(frame)
	for plate in doc.plates:
		var role := str(plate.get("role", ""))
		if role == AirframeDocument.ROLE_BOTTOM or role == AirframeDocument.ROLE_TOP:
			plate["thickness_mm"] = 4.0
	var edit := FittedFrame.edit_of(frame, doc, FittedFrame.baseline(frame))
	var b := _build(catalog, "frame_5in_freestyle")
	b.set_frame_edit(edit)
	var stated := float(edit.get("specs", {}).get("plate_thickness_mm", -1.0))
	return TestResult.new("frame constants: a drawn 4 mm centre plate wins over the catalogue's 2.5 mm",
		absf(stated - 4.0) < EPS and absf(b.plate_thickness_m() - 0.004) < EPS,
		"edit specs %s, build t %.6f" % [edit.get("specs"), b.plate_thickness_m()])


static func _an_edit_of_the_arms_alone_leaves_thickness_to_the_catalogue(catalog: PartsCatalog) -> TestResult:
	var frame := catalog.get_part("frame_5in_freestyle")
	var doc := AirframeDocument.from_catalog_frame(frame)
	for plate in doc.plates:
		if str(plate.get("role", "")) == AirframeDocument.ROLE_ARM:
			plate["thickness_mm"] = float(plate["thickness_mm"]) * 0.5
	var edit := FittedFrame.edit_of(frame, doc, FittedFrame.baseline(frame))
	return TestResult.new("frame constants: thinning only the arms states no plate thickness",
		not edit.is_empty() and not (edit.get("specs", {}) as Dictionary).has("plate_thickness_mm"),
		"edit specs %s" % [edit.get("specs")])


static func _a_replacement_drawing_without_plates_does_not_inherit(catalog: PartsCatalog) -> TestResult:
	var frame := catalog.get_part("frame_5in_freestyle")
	var doc := AirframeDocument.from_catalog_frame(frame)
	doc.id = "someone_elses_frame"
	var kept: Array = []
	for plate in doc.plates:
		var role := str(plate.get("role", ""))
		if role != AirframeDocument.ROLE_BOTTOM and role != AirframeDocument.ROLE_TOP:
			kept.append(plate)
	doc.plates = kept
	var edit := FittedFrame.edit_of(frame, doc, FittedFrame.baseline(frame))
	var b := _build(catalog, "frame_5in_freestyle")
	b.set_frame_edit(edit)
	return TestResult.new("frame constants: a drawing with no centre plate falls to the typical, not the fitted frame's 2.5 mm",
		absf(b.plate_thickness_m() - TYPICAL_M) < EPS, "t %.6f, edit specs %s" % [b.plate_thickness_m(), edit.get("specs")])


static func _the_tweak_limits_follow_the_frame(catalog: PartsCatalog) -> TestResult:
	var b := _build(catalog, "frame_5in_freestyle")
	var limits := AssemblyTweaks.limits(b)
	var gap: Dictionary = limits[AssemblyTweaks.PLATE_GAP]
	return TestResult.new("frame constants: the standoff tweak's min and default come from the frame's plate",
		absf(float(gap["min"]) - 2.5) < 1e-6 and absf(float(gap["default"]) - 3.75) < 1e-6,
		"min %s default %s" % [gap["min"], gap["default"]])


static func _mismatched_fc_warns_with_the_frames_pattern(catalog: PartsCatalog) -> TestResult:
	# The default FC is 30.5x30.5; the 3.5" freestyle is drilled 20x20.
	var b := _build(catalog, "frame_35in_freestyle")
	var w := _warning(b, &"fc_stack_mount")
	return TestResult.new("frame constants: a 30.5 FC on a 20x20 frame warns, quoting the frame's 20x20",
		w != null and str(w.values.get("frame_pattern", "")) == "20x20"
			and str(w.values.get("board_pattern", "")) == "30.5x30.5" and w.message.contains("20x20"),
		"warning %s" % [w.message if w != null else "none"])


static func _matching_fc_is_silent(catalog: PartsCatalog) -> TestResult:
	var b := _build(catalog, "frame_5in_freestyle")
	return TestResult.new("frame constants: a 30.5 FC on a 30.5 frame does not warn",
		_warning(b, &"fc_stack_mount") == null, "")


static func _a_drawn_pattern_is_quoted(catalog: PartsCatalog) -> TestResult:
	var b := _build(catalog, "frame_5in_freestyle")
	b.set_frame_edit({"part_id": "frame_5in_freestyle", "mass_g": float(b.frame["mass_g"]),
		"arm_mm": float(b.frame["specs"]["arm_mm"]), "specs": {"stack_mount": "25.5x25.5"}})
	var w := _warning(b, &"fc_stack_mount")
	return TestResult.new("frame constants: a drawn 25.5 pattern is what the warning quotes",
		w != null and str(w.values.get("frame_pattern", "")) == "25.5x25.5", "warning %s" % [w.message if w != null else "none"])
