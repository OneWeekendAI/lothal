class_name FrameHardware
extends RefCounted
## The screws and standoffs of one `AirframeDocument` — airframe.md §5 — as pure functions, so the
## Lab list's "Screws & standoffs" row and the Fasteners page read ONE computation.
##
## This was the Fasteners tab's private arithmetic. The row could not reach it (a row is a function
## of data, not of a panel), so the row said "derived from the frame" and stayed green while the page
## under it flagged a hole too close to the plate edge. Lifting it here is what lets both say the
## same thing: `mass_g` for the row's number and the page's "Hardware mass", `joint_warnings` for the
## row's ⚠ and the page's "Why?".


## Every hardware item of one kind (`screw`, `standoff_round`, `standoff_hex`), in document order.
static func items_of_kind(document: AirframeDocument, kind: String) -> Array:
	var out: Array = []
	if document == null:
		return out
	for item in document.hardware:
		if str(item.get("kind", "")) == kind:
			out.append(item)
	return out


## Every standoff, round or hex.
static func standoffs(document: AirframeDocument) -> Array:
	return items_of_kind(document, "standoff_round") + items_of_kind(document, "standoff_hex")


## Grams of one hardware item, through HardwareMass and never through a table. The density comes
## from FrameMaterials by the item's own `material_id`.
static func item_mass_g(item: Dictionary, materials: FrameMaterials) -> float:
	var density := materials.density(str(item.get("material_id", "")))
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


## Grams of all the hardware the document carries. Zero for a frame with no bolted joint.
static func mass_g(document: AirframeDocument, materials: FrameMaterials) -> float:
	var total := 0.0
	if document == null:
		return total
	for item in document.hardware:
		total += item_mass_g(item, materials)
	return total


## "M3 · 4 standoffs": the thread sizes, then the standoff count. "" for no bolted joint.
static func choice(document: AirframeDocument) -> String:
	var threads: Array = []
	for item in items_of_kind(document, "screw"):
		var label := "M%s" % _trim(float(item.get("thread_d_mm", 0.0)))
		if not threads.has(label):
			threads.append(label)
	var count := standoffs(document).size()
	if threads.is_empty() and count == 0:
		return ""
	var parts: Array[String] = []
	if not threads.is_empty():
		parts.append("/".join(threads))
	if count > 0:
		parts.append("%d standoff%s" % [count, "" if count == 1 else "s"])
	return " · ".join(parts)


## "24 × M3": screws grouped by thread size, the line on a build sheet. "" for none.
static func screw_summary(document: AirframeDocument) -> String:
	var by_thread: Dictionary = {}
	for item in items_of_kind(document, "screw"):
		var thread := float(item.get("thread_d_mm", 0.0))
		by_thread[thread] = int(by_thread.get(thread, 0)) + 1
	var parts: Array[String] = []
	for thread in by_thread:
		parts.append("%d × M%.0f" % [int(by_thread[thread]), float(thread)])
	return ", ".join(parts)


## The §5.3 checks for the frame's motor joint, measured off the frame: thread engagement, bottoming
## out, and the hole-to-edge margin (measured from the real hole to the real outline). Most severe
## first; empty for a frame with no screws or no measurable arm.
static func joint_warnings(document: AirframeDocument) -> Array[BuildWarning]:
	var empty: Array[BuildWarning] = []
	var screws := items_of_kind(document, "screw")
	var arm_t := arm_thickness_mm(document)
	if screws.is_empty() or arm_t <= 0.0:
		return empty
	var edge_distance := motor_hole_edge_distance_mm(document)
	if edge_distance <= 0.0:
		return empty
	var screw: Dictionary = screws[0]
	return HardwareMass.joint_warnings(
		float(screw.get("shank_len_mm", 0.0)),
		float(screw.get("thread_d_mm", 0.0)),
		arm_t, arm_t, edge_distance)


static func arm_plates(document: AirframeDocument) -> Array:
	var out: Array = []
	if document == null:
		return out
	for plate in document.plates:
		if str(plate.get("role", "")) == AirframeDocument.ROLE_ARM:
			out.append(plate)
	return out


## The stock the arms are cut from — the plate a motor screw threads into.
static func arm_thickness_mm(document: AirframeDocument) -> float:
	var plates := arm_plates(document)
	if plates.is_empty():
		return 0.0
	return AirframeDocument.plate_thickness_mm(plates[0])


## The thinnest bolt-hole margin on the first arm plate: hole centre to the plate's outline. The
## worst one is the one that tears out. Zero when there is nothing to measure.
static func motor_hole_edge_distance_mm(document: AirframeDocument) -> float:
	var hole := worst_edge_hole(document)
	return float(hole.get("distance_mm", 0.0))


## `{centre_mm: Vector2, distance_mm}` of the first arm's hole nearest its plate edge, or `{}`.
## The centre is what the Screws & standoffs page marks on its drawing.
static func worst_edge_hole(document: AirframeDocument) -> Dictionary:
	var plates := arm_plates(document)
	if plates.is_empty():
		return {}
	var plate: Dictionary = plates[0]
	var outline := AirframeDocument.plate_outline(plate)
	var holes := AirframeDocument.plate_holes(plate)
	if outline.size() < 3 or holes.is_empty():
		return {}
	var worst := INF
	var at := Vector2.ZERO
	for hole in holes:
		var centre := PolygonProps.centroid(hole)
		var distance := PolygonProps.distance_to_boundary(outline, centre)
		if distance < worst:
			worst = distance
			at = centre
	if worst == INF:
		return {}
	return {"centre_mm": at, "distance_mm": worst}


# ---------------------------------------------------------------------------
# Bolt holes off the arms: stack mounts and any other drilled hole (airframe gaps G2)
# ---------------------------------------------------------------------------

## Standard metric threads a frame is bolted with, smallest first. A round hole is read as a bolt
## hole for the largest of these whose clearance it matches.
const BOLT_THREADS_MM := [2.0, 2.5, 3.0, 4.0]
## How much looser than a close clearance (`AirframeDocument.BOLT_CLEARANCE_MM`) a hole may be drilled
## and still be read as that screw's hole. Half a millimetre covers a "normal" fit; past it a round
## hole is a lightening hole and nobody bolts through it.
const BOLT_HOLE_LOOSE_MM := 0.5
## A hole is round when its two principal extents agree to this fraction. A tessellated circle
## reads above 0.98; a strap slot reads below 0.5.
const ROUND_HOLE_MIN_RATIO := 0.9


## The screw a hole was drilled for, read off its shape: the thread diameter when the hole is round
## and its diameter is that screw's clearance (close to `BOLT_HOLE_LOOSE_MM` over), else 0.
##
## FOUND BY SHAPE, as `StrapSlots` finds a slot: there is no "bolt hole" record in the document, so a
## stack hole cut by "+ Stack mount", one a preset cut and one a builder drilled by hand are all found
## by one rule. The SCREW's diameter comes back, not the hole's — `HardwareMass.hole_to_edge_warning`
## is written on the bolt, and reading it off the clearance hole would loosen it by the clearance.
static func bolt_hole_thread_mm(hole: PackedVector2Array) -> float:
	var shape := StrapSlots.measure(hole)
	var length := float(shape["length_mm"])
	if length <= 0.0 or float(shape["width_mm"]) / length < ROUND_HOLE_MIN_RATIO:
		return 0.0
	var centre: Vector2 = shape["centre"]
	var radius := 0.0
	for p in hole:
		radius = maxf(radius, p.distance_to(centre))
	var diameter := radius * 2.0
	var best := 0.0
	for thread in BOLT_THREADS_MM:
		var close := float(thread) + AirframeDocument.BOLT_CLEARANCE_MM
		if diameter >= close - 0.05 and diameter <= close + BOLT_HOLE_LOOSE_MM:
			best = float(thread)
	return best


## `{plate_index, centre_mm, distance_mm, thread_d_mm}` of the bolt hole on a NON-ARM plate whose
## edge margin is smallest against the 1.5×d it needs, or `{}` when there is none.
##
## Arm plates are left to `joint_warnings`, which checks them against the motor screws the document
## carries; reading them here too would say the same tear-out twice. Everything else — the centre
## plates' stack holes above all — had no edge check until this, which is why a stack mount placed
## near a plate edge on a drawn frame said nothing.
static func worst_mount_hole(document: AirframeDocument) -> Dictionary:
	var worst: Dictionary = {}
	if document == null:
		return worst
	var worst_ratio := INF
	for index in document.plates.size():
		var plate: Dictionary = document.plates[index]
		if str(plate.get("role", "")) == AirframeDocument.ROLE_ARM:
			continue
		var outline := AirframeDocument.plate_outline(plate)
		if outline.size() < 3:
			continue
		for hole in AirframeDocument.plate_holes(plate):
			var thread := bolt_hole_thread_mm(hole)
			if thread <= 0.0:
				continue
			var centre := PolygonProps.centroid(hole)
			var distance := PolygonProps.distance_to_boundary(outline, centre)
			var ratio := distance / (HardwareMass.EDGE_DISTANCE_RATIO * thread)
			if ratio < worst_ratio:
				worst_ratio = ratio
				worst = {"plate_index": index, "centre_mm": centre, "distance_mm": distance,
					"thread_d_mm": thread}
	return worst


## The §5.3 hole-to-edge check on every bolt hole off the arms — at most one warning, the worst hole,
## so four stack holes on one tight plate are one thing to fix and not four lines. Empty when every
## margin holds.
static func mount_hole_warnings(document: AirframeDocument) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var worst := worst_mount_hole(document)
	if worst.is_empty():
		return out
	var warning := HardwareMass.hole_to_edge_warning(
		float(worst["distance_mm"]), float(worst["thread_d_mm"]))
	if warning != null:
		out.append(warning)
	return out


static func _trim(value: float) -> String:
	var text := "%.1f" % value
	return text.trim_suffix(".0")
