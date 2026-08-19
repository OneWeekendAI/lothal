class_name FastenersDetails
extends AirframePanel
## The Fasteners tab — airframe.md §5. The screws and standoffs a frame needs, what they weigh,
## how tall they make the stack, and the three ways a bolted joint is wrong before it is flown.
##
## ## Why this deserves a tab of its own
##
## Twenty-odd screws and eight standoffs on a 5" build come to 8–15 g. That is more than a camera,
## and until this tab it was invisible in the app: inside a frame's published mass if the vendor
## counted the hardware bag, and missing entirely if they did not, with no way to tell which. §5's
## whole argument is that the fix is not a hundred JSON rows nobody maintains but an integral of
## geometry times a density — and once it is computed, showing it costs one panel.
##
## ## The checks warn and never block
##
## Lothal's standing rule (parts.md, labs-and-sim.md §2.1): a builder who wants a 4 mm screw in a
## 3 mm plate gets one, and gets told. So the check rows report a state and a number; nothing here
## refuses a selection, and nothing here turns red as a substitute for saying what is wrong.
##
## Every figure is for the generated preset, which carries the standoff and screw geometry
## `AirframeDocument.from_catalog_frame` derives (§5.1). A frame with no plate geometry — the
## moulded whoops — has no bolted joint to describe, and the rows say so rather than reporting zero.

const SPEC_ROWS := [
	{"key": "standoffs", "label": "Standoffs"},
	{"key": "screws", "label": "Screws"},
	{"key": "hardware_mass", "label": "Hardware mass"},
	{"key": "hardware_share", "label": "Share of frame mass"},
	# ---- WHAT THE JOINT SETS (§5.2, §5.3) ----
	{"key": "stack_height", "label": "Stack height"},
	{"key": "cg_height", "label": "Top plate above datum"},
	{"key": "engagement", "label": "Motor screw engagement"},
	{"key": "checks", "label": "Assembly checks"},
]


func _init() -> void:
	super(SPEC_ROWS)


## Every hardware item of one kind, from the generated document.
func _items_of_kind(kind: String) -> Array:
	var out: Array = []
	if _document == null:
		return out
	for item in _document.hardware:
		if str(item.get("kind", "")) == kind:
			out.append(item)
	return out


## Grams of one hardware item, through HardwareMass and never through a table. The density comes
## from FrameMaterials by the item's own `material_id`, so an aluminium standoff and a titanium one
## differ here without anything in this file knowing the difference.
func _item_mass_g(item: Dictionary) -> float:
	var density := materials().density(str(item.get("material_id", "")))
	if density <= 0.0:
		return 0.0
	match str(item.get("kind", "")):
		"standoff_round":
			return HardwareMass.standoff_round_mass_g(
				float(item.get("outer_d_mm", 0.0)), float(item.get("bore_d_mm", 0.0)),
				float(item.get("length_mm", 0.0)), density)
		"standoff_hex":
			return HardwareMass.standoff_hex_mass_g(
				float(item.get("across_flats_mm", 0.0)), float(item.get("bore_d_mm", 0.0)),
				float(item.get("length_mm", 0.0)), density)
		"screw":
			return HardwareMass.screw_mass_g(
				float(item.get("thread_d_mm", 0.0)), float(item.get("shank_len_mm", 0.0)),
				float(item.get("head_d_mm", 0.0)), float(item.get("head_h_mm", 0.0)), density)
	return 0.0


func _total_hardware_mass_g() -> float:
	var total := 0.0
	if _document == null:
		return total
	for item in _document.hardware:
		total += _item_mass_g(item)
	return total


func row_text(key: String) -> String:
	var standoffs := _items_of_kind("standoff_round")
	var screws := _items_of_kind("screw")

	match key:
		"standoffs":
			if standoffs.is_empty():
				return "— (no bolted joint modelled)"
			var first: Dictionary = standoffs[0]
			var record := materials().get_material(str(first.get("material_id", "")))
			return "%d × %.0f mm  (%.0f mm OD, %s)" % [
				standoffs.size(), float(first.get("length_mm", 0.0)),
				float(first.get("outer_d_mm", 0.0)),
				str(record.get("name", first.get("material_id", "?")))]

		"screws":
			if screws.is_empty():
				return "— (no bolted joint modelled)"
			# Grouped by thread size, because "20 × M3" is the line on a build sheet and "20 screws"
			# is not. A frame with both M2 motor screws and M3 plate screws prints both.
			var by_thread: Dictionary = {}
			for item in screws:
				var thread := float(item.get("thread_d_mm", 0.0))
				by_thread[thread] = int(by_thread.get(thread, 0)) + 1
			var parts: Array[String] = []
			for thread in by_thread:
				parts.append("%d × M%.0f" % [int(by_thread[thread]), float(thread)])
			return ", ".join(parts)

		"hardware_mass":
			var total := _total_hardware_mass_g()
			if total <= 0.0:
				return "— (no bolted joint modelled)"
			return "%.1f g" % total

		"hardware_share":
			var total := _total_hardware_mass_g()
			if total <= 0.0 or _props == null or _props.total_mass_g() <= 0.0:
				return "—"
			# The point of the row: this is usually more than a camera, and it is the part of a
			# frame's mass nobody can see on a spec sheet.
			return "%.0f%% of the computed %.0f g" % [
				total / _props.total_mass_g() * 100.0, _props.total_mass_g()]

		"stack_height":
			var plate_t := _structural_plate_thickness_mm()
			if standoffs.is_empty() or plate_t <= 0.0:
				return "— (no bolted joint modelled)"
			var lengths: Array = []
			for item in standoffs:
				lengths.append(float(item.get("length_mm", 0.0)))
			# One standoff length and two plates — the sandwich a bolted frame is. Through
			# HardwareMass rather than added here, so this row and §5.2's sum cannot diverge.
			return "%.1f mm" % HardwareMass.stack_height_mm(
				[lengths[0]], [plate_t, plate_t])

		"cg_height":
			if _document == null or _document.plates.is_empty():
				return "—"
			# §5.2: stack height moves the CG off the thrust plane, which couples pitch into roll.
			# The top plate's z is the tallest thing the document knows and is the honest proxy
			# until the pack and the stack are positioned in it.
			var top_z := 0.0
			for plate in _document.plates:
				top_z = maxf(top_z, AirframeDocument.plate_z_mm(plate))
			if top_z <= 0.0:
				return "—"
			return "%.1f mm" % top_z

		"engagement":
			var arm_t := _arm_thickness_mm()
			if screws.is_empty() or arm_t <= 0.0:
				return "— (no bolted joint modelled)"
			# The motor screw into the arm plate: the joint that carries every newton the motor
			# makes, and the one where 1×d of engagement is a hard boundary rather than a rule of
			# thumb. A screw shorter than that strips the thread out of the carbon.
			var motor_screw: Dictionary = screws[0]
			var thread_d := float(motor_screw.get("thread_d_mm", 0.0))
			var warning := HardwareMass.thread_engagement_warning(
				float(motor_screw.get("shank_len_mm", 0.0)), thread_d, arm_t)
			var engagement := minf(float(motor_screw.get("shank_len_mm", 0.0)), arm_t)
			var state := "ok" if warning == null else BuildWarning.severity_name(warning.severity)
			return "%.1f mm into %.1f mm arm  (%.1f×d, %s)" % [
				engagement, arm_t, engagement / thread_d if thread_d > 0.0 else 0.0, state]

		"checks":
			if screws.is_empty():
				return "— (no bolted joint modelled)"
			# The three checks of §5.3, run over the joint the preset generates. Reported as a
			# count and the worst message rather than as a colour: the severity scale is
			# BuildWarning's and it distinguishes "the thread strips" from "the edge margin binds",
			# which a red dot cannot.
			var warnings := _joint_warnings(screws)
			if warnings.is_empty():
				return "3 of 3 pass  (engagement, bottoming out, edge distance)"
			var worst: BuildWarning = BuildWarning.by_severity(warnings)[0]
			return "%d of 3 flagged — %s" % [warnings.size(), worst.message]

	return super(key)


## The §5.3 checks for the frame's motor joint, measured off the frame.
##
## THE EDGE MARGIN IS NOW MEASURED, NOT DERIVED. It used to be half of
## `AirframeDocument.MOUNT_EDGE_MARGIN_MM` — the padding the preset generator puts around a motor
## pad — which is exactly right for a generated preset and says nothing whatsoever about a frame
## somebody drew, where the margin is wherever they put the hole. `PolygonProps.distance_to_boundary`
## measures from the real bolt hole to the real outline, which is what `HardwareMass` asked for in
## the first place.
func _joint_warnings(screws: Array) -> Array[BuildWarning]:
	var empty: Array[BuildWarning] = []
	var arm_t := _arm_thickness_mm()
	if screws.is_empty() or arm_t <= 0.0:
		return empty
	var edge_distance := _motor_hole_edge_distance_mm()
	if edge_distance <= 0.0:
		return empty
	var screw: Dictionary = screws[0]
	return HardwareMass.joint_warnings(
		float(screw.get("shank_len_mm", 0.0)),
		float(screw.get("thread_d_mm", 0.0)),
		arm_t, arm_t, edge_distance)


## The thinnest bolt hole margin on the arm: for every hole in the first arm plate, the distance
## from the hole's centre to the plate's outline. The worst one is the one that tears out.
func _motor_hole_edge_distance_mm() -> float:
	var plates := arm_plates()
	if plates.is_empty():
		return 0.0
	var plate: Dictionary = plates[0]
	var outline := AirframeDocument.plate_outline(plate)
	var holes := AirframeDocument.plate_holes(plate)
	if outline.size() < 3 or holes.is_empty():
		return 0.0
	var worst := INF
	for hole in holes:
		var centre := PolygonProps.centroid(hole)
		worst = minf(worst, PolygonProps.distance_to_boundary(outline, centre))
	return 0.0 if worst == INF else worst


## The stock the structural (non-arm) plates are cut from. The thinnest, because the stack sandwich
## is only as tall as the plates it actually clamps and a thicker side plate is not in that stack.
func _structural_plate_thickness_mm() -> float:
	if _document == null:
		return 0.0
	var thinnest := INF
	for plate in _document.plates:
		if str(plate.get("role", "")) == AirframeDocument.ROLE_ARM:
			continue
		var thickness := AirframeDocument.plate_thickness_mm(plate)
		if thickness > 0.0:
			thinnest = minf(thinnest, thickness)
	return 0.0 if thinnest == INF else thinnest


## The stock the arms are cut from — the plate a motor screw threads into, which is the joint that
## carries every newton the motor makes.
func _arm_thickness_mm() -> float:
	var plates := arm_plates()
	if plates.is_empty():
		return 0.0
	return AirframeDocument.plate_thickness_mm(plates[0])
