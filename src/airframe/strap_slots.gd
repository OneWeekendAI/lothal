class_name StrapSlots
extends RefCounted
## Battery strap slots — airframe.md §6.4, "the one that actually fails". Pure geometry on an
## `AirframeDocument`: no Build, no node.
##
## ## A slot is a hole, and is found by its shape
##
## There is no "slot" record in the document. A strap slot is a HOLE in a plate — the same reversed
## polygon a bolt hole is, subtracted from the plate's area by the same integrals, exported in the same
## DXF — so it costs the mass and the cut file nothing new. What makes a hole a slot is its shape: long
## enough to pass a strap and much longer than it is wide. `measure()` reads that off the polygon (its
## principal axes), so a slot a builder drew, a slot the preset generator cut and a slot imported from
## an SVG are found by one rule, and a round bolt hole or a lightening hole never is.
##
## ## The three checks (all EXACT tier, §8 — geometry against a stated strap)
##
##   - NO_STRAP_SLOTS: the plate the pack straps to has no slot at all. "A frame designed from scratch
##     with no strap slots is a real mistake with a real, purely geometric check."
##   - STRAP_SLOT_NARROW: a slot shorter than the strap is wide (plus clearance), or narrower than the
##     strap is thick (plus clearance). The strap does not go through.
##   - STRAP_SLOT_OFF_PACK: a slot whose centre is not under the pack's footprint. A strap through it
##     cannot wrap the pack; it pulls the pack sideways or misses it.
##
## The strap's width is the builder's per-drone guess (BatteryPad's slot setting, a 20 mm strap by
## default) and its thickness BatteryPad's; this file takes both as numbers and says so in the
## messages.

## A hole is a strap slot when it is at least this long… (BatteryPad's narrowest strap, 8 mm: no strap
## narrower than that is sold, so no hole shorter than it can be for one.)
const MIN_SLOT_LENGTH_MM := 8.0
## …and at least this many times longer than it is wide. A round hole is 1; a strap slot on a real
## top plate is 5-8. Two keeps a fat, short slot a slot and every round hole not one.
const MIN_ASPECT := 2.0

## What a cut slot needs on each side of the strap, mm. A GUESS: carbon is cut to about ±0.1 mm and a
## strap folds, so half a millimetre a side is room to thread it, not a tolerance anyone published.
const CUT_CLEARANCE_MM := 0.5

## The slot the preset generators cut into a top plate: a 20 mm strap's slot, as cut on common 5" top
## plates (22 × 3.5 mm). GUESSES, like the generator's arm width — the catalog publishes no slot.
const PRESET_SLOT_LENGTH_MM := 22.0
const PRESET_SLOT_WIDTH_MM := 3.5
## Carbon left between a slot and a stack hole, and the stack holes' radius (the generators' M3 bore).
const PRESET_WEB_MM := 1.5
const PRESET_STACK_HOLE_R_MM := 1.6

const NO_STRAP_SLOTS := &"no_strap_slots"
const STRAP_SLOT_NARROW := &"strap_slot_narrow"
const STRAP_SLOT_OFF_PACK := &"strap_slot_off_pack"


## A rectangular slot as a HOLE: centred on `centre`, `length_mm` along `angle_rad` (0 = across the
## frame, along u), `width_mm` across it, wound clockwise — opposite to an outline, which is how
## PolygonProps subtracts it (§3.1).
##
## `corner_radius_mm` rounds the four corners (G3): a slot is routed with a round bit, which cannot cut
## a sharp inside corner, so a slot meant to be cut is drawn with the fillet the bit leaves. Zero keeps
## the sharp rectangle — the exact shape the slot measurements are proven against.
static func make_slot(centre: Vector2, length_mm: float, width_mm: float,
		angle_rad: float = 0.0, corner_radius_mm: float = 0.0) -> PackedVector2Array:
	var along := Vector2(cos(angle_rad), sin(angle_rad)) * length_mm * 0.5
	var across := Vector2(-sin(angle_rad), cos(angle_rad)) * width_mm * 0.5
	var radius := minf(corner_radius_mm, minf(length_mm, width_mm) * 0.5)
	if radius <= 0.0:
		# Clockwise in a y-down-agnostic sense: the reverse of the counter-clockwise corner order.
		return PolygonProps.reversed(PackedVector2Array([
			centre - along - across, centre + along - across,
			centre + along + across, centre - along + across]))
	# Counter-clockwise in the slot's own axes, one quarter arc per corner, then reversed to a hole.
	var half := Vector2(length_mm * 0.5 - radius, width_mm * 0.5 - radius)
	var local := PackedVector2Array()
	var corners := [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y),
		Vector2(-half.x, half.y)]
	for index in 4:
		var arc := PolygonProps.tessellate_arc(corners[index], radius, PI + index * PI * 0.5, PI * 0.5)
		local.append_array(arc)
	var out := PackedVector2Array()
	for point in local:
		out.append(centre + point.rotated(angle_rad))
	return PolygonProps.reversed(out)


## The two slots the preset generators cut into a top plate: across the frame, either side of the
## centre, inside the stack bolt pattern (so they clear the four stack holes by a web of carbon) and
## therefore under any pack centred on the plate. Empty when the plate cannot take them.
static func preset_slots(plate_side_mm: float, stack_pitch_mm: float) -> Array:
	var out: Array = []
	var v := stack_pitch_mm * 0.5 - PRESET_STACK_HOLE_R_MM - PRESET_WEB_MM - PRESET_SLOT_WIDTH_MM * 0.5
	var fits_across := PRESET_SLOT_LENGTH_MM + 2.0 * PRESET_WEB_MM <= plate_side_mm
	if v <= PRESET_SLOT_WIDTH_MM * 0.5 + PRESET_WEB_MM * 0.5 or not fits_across:
		return out
	for side in [-1.0, 1.0]:
		# Rounded to the default bit, so a preset is ready to cut as generated (G3).
		out.append(make_slot(Vector2(0.0, side * v), PRESET_SLOT_LENGTH_MM, PRESET_SLOT_WIDTH_MM,
			0.0, AirframeDocument.DEFAULT_CUTTING_BIT_MM * 0.5))
	return out


## A hole's shape off its own polygon: `{centre, length_mm, width_mm, axis}` along its principal axes,
## and `is_slot` by the two thresholds above. Principal axes from the vertex covariance, then the
## extents projected on them — exact for a rectangle at any angle, and a fair reading of a rounded or
## tessellated slot.
static func measure(hole: PackedVector2Array) -> Dictionary:
	if hole.size() < 3:
		return {"is_slot": false, "centre": Vector2.ZERO, "length_mm": 0.0, "width_mm": 0.0,
			"axis": Vector2.RIGHT}
	var centre := PolygonProps.centroid(hole)
	var sxx := 0.0
	var syy := 0.0
	var sxy := 0.0
	for p in hole:
		var d := p - centre
		sxx += d.x * d.x
		syy += d.y * d.y
		sxy += d.x * d.y
	var angle := 0.5 * atan2(2.0 * sxy, sxx - syy)
	var axis := Vector2(cos(angle), sin(angle))
	var normal := Vector2(-axis.y, axis.x)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in hole:
		var d := p - centre
		var a := d.dot(axis)
		var b := d.dot(normal)
		lo = Vector2(minf(lo.x, a), minf(lo.y, b))
		hi = Vector2(maxf(hi.x, a), maxf(hi.y, b))
	var extent := hi - lo
	var length := maxf(extent.x, extent.y)
	var width := minf(extent.x, extent.y)
	if extent.y > extent.x:
		axis = normal
	return {"is_slot": length >= MIN_SLOT_LENGTH_MM and width > 0.0 and length / width >= MIN_ASPECT,
		"centre": centre, "length_mm": length, "width_mm": width, "axis": axis}


## Every strap slot in one plate, measured, in hole order.
static func slots(plate: Dictionary) -> Array:
	var out: Array = []
	for hole in AirframeDocument.plate_holes(plate):
		var shape := measure(hole)
		if bool(shape["is_slot"]):
			out.append(shape)
	return out


## The plate a pack on `mount_id` straps to: the top plate for "strap_top" (and anything else), the
## bottom plate for "strap_bottom" — the highest / lowest plate of that role when there are several.
## `{}` for a document with no such plate (a moulded frame, or a drawing with no centre plates yet).
static func seat_plate(document: AirframeDocument, mount_id: String = "strap_top") -> Dictionary:
	if document == null:
		return {}
	var role := AirframeDocument.ROLE_BOTTOM if mount_id == "strap_bottom" else AirframeDocument.ROLE_TOP
	var best: Dictionary = {}
	for plate in document.plates:
		if str(plate.get("role", "")) != role:
			continue
		if best.is_empty():
			best = plate
			continue
		var z := AirframeDocument.plate_z_mm(plate)
		var best_z := AirframeDocument.plate_z_mm(best)
		if (role == AirframeDocument.ROLE_TOP and z > best_z) or (role == AirframeDocument.ROLE_BOTTOM and z < best_z):
			best = plate
	return best


## The length a slot must have to pass a strap of `strap_width_mm`, and the width to pass its
## thickness — each with CUT_CLEARANCE_MM either side.
static func needed_length_mm(strap_width_mm: float) -> float:
	return strap_width_mm + 2.0 * CUT_CLEARANCE_MM


static func needed_width_mm(strap_thickness_mm: float) -> float:
	return strap_thickness_mm + 2.0 * CUT_CLEARANCE_MM


## The three checks against the plate the pack straps to. `pack_rect_mm` is the pack's footprint in
## plan (u across, v fore-aft, mm); a zero-area rect skips the under-the-pack check. Empty for a
## document with no seat plate — a moulded frame has nothing to cut a slot into, and saying so on
## every whoop would be the cinelifter mistake (a warning for building the thing correctly).
static func warnings(document: AirframeDocument, mount_id: String, pack_rect_mm: Rect2,
		strap_width_mm: float, strap_thickness_mm: float) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var plate := seat_plate(document, mount_id)
	if plate.is_empty():
		return out
	var where := "bottom" if mount_id == "strap_bottom" else "top"
	var found := slots(plate)
	if found.is_empty():
		out.append(BuildWarning.limiting(NO_STRAP_SLOTS,
			"The %s plate the pack straps to has no strap slots. A strap needs a slot cut through the plate to pass round it, at least %.0f mm long for a %.0f mm strap; without one the pack is held by friction and tape. Add two slots under the pack." % [
				where, needed_length_mm(strap_width_mm), strap_width_mm],
			{"plate": where, "strap_width_mm": strap_width_mm}))
		return out
	var need_l := needed_length_mm(strap_width_mm)
	var need_w := needed_width_mm(strap_thickness_mm)
	var narrow: Dictionary = {}
	for shape in found:
		if float(shape["length_mm"]) < need_l or float(shape["width_mm"]) < need_w:
			if narrow.is_empty() or float(shape["length_mm"]) < float(narrow["length_mm"]):
				narrow = shape
	if not narrow.is_empty():
		out.append(BuildWarning.limiting(STRAP_SLOT_NARROW,
			"A strap slot in the %s plate is %.1f × %.1f mm; a %.0f mm strap %.1f mm thick needs %.1f × %.1f mm to pass (%.1f mm clearance a side, a guess). The strap will not go through." % [
				where, float(narrow["length_mm"]), float(narrow["width_mm"]), strap_width_mm,
				strap_thickness_mm, need_l, need_w, CUT_CLEARANCE_MM],
			{"slot_mm": float(narrow["length_mm"]), "needed_mm": need_l,
				"slot_width_mm": float(narrow["width_mm"]), "needed_width_mm": need_w}))
	if pack_rect_mm.get_area() > 0.0:
		var off: Array = []
		for shape in found:
			if not pack_rect_mm.has_point(shape["centre"]):
				off.append(shape)
		if not off.is_empty():
			var first: Dictionary = off[0]
			var centre: Vector2 = first["centre"]
			out.append(BuildWarning.limiting(STRAP_SLOT_OFF_PACK,
				"%d of the %s plate's %d strap slots %s not under the pack: the one at (%.0f, %.0f) mm is outside its %.0f × %.0f mm footprint. A strap through it cannot wrap the pack; it pulls it sideways or misses it." % [
					off.size(), where, found.size(), "is" if off.size() == 1 else "are", centre.x, centre.y,
					pack_rect_mm.size.x, pack_rect_mm.size.y],
				{"off": off.size(), "slots": found.size()}))
	return out
