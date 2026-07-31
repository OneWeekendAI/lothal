class_name TestFrameModel
extends RefCounted
## FrameModel is procedural geometry generated from a frame part's real specs, not a
## hand-modelled or scaled asset. These tests exist to catch exactly that regression: a
## fixed mesh or a hardcoded arm length would still "look right" for one frame but fail
## the cross-frame comparisons below, which is why at least two tests always build two
## different frames and compare generated geometry against each other rather than
## re-reading arm_mm out of the JSON.

const EPS := 0.0005

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append(_test_arm_tips_match_layout(catalog))
	results.append(_test_7in_longer_than_3in(catalog))
	results.append(_test_plate_tracks_arm_length(catalog))
	results.append(_test_rebuild_no_stale_children(catalog))
	results.append(_test_missing_catalog_block_does_not_crash())

	return results


static func _test_arm_tips_match_layout(catalog: PartsCatalog) -> TestResult:
	var frame_ids := ["frame_3in_toothpick", "frame_5in_freestyle", "frame_7in_long_range"]
	var all_ok := true
	var detail := ""

	for frame_id in frame_ids:
		var frame: Dictionary = catalog.get_part(frame_id)
		var arm_m: float = float(frame["specs"]["arm_mm"]) / 1000.0

		var model := FrameModel.new()
		model.rebuild(frame)

		for motor_name in MotorLayout.MOTOR_NAMES:
			var expected := MotorLayout.motor_position(motor_name, arm_m)
			var pad: Node3D = model.arm_tips[motor_name]
			var actual: Vector3 = pad.position
			var d := (actual - expected).length()
			if d > EPS:
				all_ok = false
				detail += "%s/%s expected %s got %s (d=%.5f); " % [frame_id, motor_name, expected, actual, d]

		model.free()

	if all_ok:
		detail = "all arm tips within %.4f m of MotorLayout.motor_position for %d frames" % [EPS, frame_ids.size()]

	return TestResult.new("arm tips land exactly at motor layout positions", all_ok, detail)


static func _test_7in_longer_than_3in(catalog: PartsCatalog) -> TestResult:
	var frame_3in: Dictionary = catalog.get_part("frame_3in_toothpick")
	var frame_7in: Dictionary = catalog.get_part("frame_7in_long_range")

	var model_3in := FrameModel.new()
	model_3in.rebuild(frame_3in)
	var model_7in := FrameModel.new()
	model_7in.rebuild(frame_7in)

	# Measure GENERATED geometry (pad distance from origin), not arm_mm out of the JSON.
	var len_3in: float = (model_3in.arm_tips["M1"].position as Vector3).length()
	var len_7in: float = (model_7in.arm_tips["M1"].position as Vector3).length()

	model_3in.free()
	model_7in.free()

	var margin := 0.02  # metres — a meaningful margin, not float noise
	var passed := len_7in > len_3in + margin

	return TestResult.new(
		"7-inch generated arms are strictly longer than 3-inch generated arms",
		passed,
		"3in pad distance=%.4fm, 7in pad distance=%.4fm (margin required %.3fm)" % [len_3in, len_7in, margin]
	)


static func _test_plate_tracks_arm_length(catalog: PartsCatalog) -> TestResult:
	var frame_3in: Dictionary = catalog.get_part("frame_3in_toothpick")
	var frame_7in: Dictionary = catalog.get_part("frame_7in_long_range")

	var model_3in := FrameModel.new()
	model_3in.rebuild(frame_3in)
	var model_7in := FrameModel.new()
	model_7in.rebuild(frame_7in)

	var plate_3in: MeshInstance3D = model_3in.get_node("PlateTop")
	var plate_7in: MeshInstance3D = model_7in.get_node("PlateTop")

	var size_3in: Vector3 = (plate_3in.mesh as BoxMesh).size
	var size_7in: Vector3 = (plate_7in.mesh as BoxMesh).size

	model_3in.free()
	model_7in.free()

	var passed := size_7in.x > size_3in.x

	return TestResult.new(
		"centre plate size tracks arm length across frames",
		passed,
		"3in plate side=%.4fm, 7in plate side=%.4fm" % [size_3in.x, size_7in.x]
	)


static func _test_rebuild_no_stale_children(catalog: PartsCatalog) -> TestResult:
	var frame_3in: Dictionary = catalog.get_part("frame_3in_toothpick")
	var frame_7in: Dictionary = catalog.get_part("frame_7in_long_range")

	var model := FrameModel.new()
	model.rebuild(frame_3in)
	var first_count := model.get_child_count()
	var old_m1_node: Node3D = model.arm_tips["M1"]
	var arm_3in_m: float = float(frame_3in["specs"]["arm_mm"]) / 1000.0
	var arm_7in_m: float = float(frame_7in["specs"]["arm_mm"]) / 1000.0

	model.rebuild(frame_7in)
	var second_count := model.get_child_count()

	# "Stale" means the OLD node object itself is still parented, not merely that some new
	# node happens to share a coordinate — the 7in frame's arm midpoint can legitimately
	# land on the 3in frame's old tip position (0.053m either way), which is a coincidence
	# of these two specific frames, not evidence of a leftover child.
	var old_node_still_parented := old_m1_node.get_parent() == model
	var new_m1_pos: Vector3 = model.arm_tips["M1"].position
	var new_m1_matches_new_frame := new_m1_pos.is_equal_approx(MotorLayout.motor_position("M1", arm_7in_m))
	var new_m1_matches_old_frame := new_m1_pos.is_equal_approx(MotorLayout.motor_position("M1", arm_3in_m))

	model.free()

	var passed := first_count == second_count and not old_node_still_parented \
		and new_m1_matches_new_frame and not new_m1_matches_old_frame

	return TestResult.new(
		"rebuild leaves no stale children from the previous frame",
		passed,
		"child count %d -> %d, old node still parented: %s, new M1 pos %s (matches new frame: %s, matches old frame: %s)" % [
			first_count, second_count, old_node_still_parented, new_m1_pos, new_m1_matches_new_frame, new_m1_matches_old_frame
		]
	)


static func _test_missing_catalog_block_does_not_crash() -> TestResult:
	var frame := {
		"part_id": "frame_test_no_catalog",
		"name": "Test Frame No Catalog",
		"category": "frame",
		"mass_g": 100.0,
		"specs": {
			"arm_mm": 100.0,
			"max_prop_inches": 5.0,
			"motor_mount": "16x16"
		}
	}

	var model := FrameModel.new()
	model.rebuild(frame)

	var arm_count := model.arm_tips.size()
	model.free()

	return TestResult.new(
		"missing catalog block does not crash and still produces four arms",
		arm_count == 4,
		"arm_tips.size() == %d" % arm_count
	)
