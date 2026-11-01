class_name FrameTools
extends RefCounted
## The Design Space's frame edits (PLAN Section 4): drill, pocket, fill, plate thickness and arm
## width, on the fitted frame's own AirframeDocument. Pure functions, no Node.
##
## Every operation is a VERDICT first: `{ok, reason}`, where a refusal carries one line saying why
## and leaves the document exactly as it was. The `*_verdict` functions never write; the matching
## operation runs its verdict and writes only on `ok`.
##
## Holes are named. A plate carries `hole_names`, parallel to `holes`: a pick proxy's name where the
## GLB has one (`pick_hole_arm_FL_2`), or what occupies the hole (`motor_bore_FL`, `motor_bolt_FL_1`,
## `standoff_3`). A drilled hole or cut pocket gets the next free proxy name for its plate, so the
## 3D side can make it pickable (for Fill) under a name that resolves to it.
##
## What is NOT modelled (plan §4.3), and what the mass change therefore leaves out: CG and inertia
## stay "frame mass treated as centred" (Section 11); no stiffness or strength change; no fatigue or
## crack growth at a new hole; no machining tolerance or chamfer.

## ISO 273 close-fit clearance holes, the sizes the catalog's own motor holes use.
const DRILL_SIZES := {"M2": 2.2, "M3": 3.2}
const FREE_MIN_D_MM := 1.0
const FREE_MAX_D_MM := 10.0
## Fine enough that a drilled hole's tessellated area is within 0.5% of pi r^2 at 3 mm.
const DRILL_CHORD_TOLERANCE_MM := 0.005
## ASSUMPTION, not a sourced figure: the narrowest carbon web a pocket may leave to an edge or to
## another cut. Thinner webs in 3K twill crack at the first knock.
const MIN_WEB_MM := 2.0
const THICKNESS_MIN_MM := 1.0
const THICKNESS_MAX_MM := 8.0
## Arm width as a multiple of the arm as drawn.
const ARM_WIDTH_MIN := 0.7
const ARM_WIDTH_MAX := 1.3
const WIDTH_SCALE_KEY := "width_scale"
const NAMES_KEY := "hole_names"

## Shown beside the frame tools: what an edit's numbers do not include.
const NOT_MODELLED := ["CG/inertia: frame treated as centred", "no stiffness change",
	"no strength or fatigue", "no tolerance or chamfer"]


static func ok() -> Dictionary:
	return {"ok": true, "reason": ""}


static func refuse(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


# ---------------------------------------------------------------------------
# Names
# ---------------------------------------------------------------------------

## The hole names of a plate, padded so they always parallel `holes`.
static func hole_names(plate: Dictionary) -> Array:
	var names: Array = (plate.get(NAMES_KEY, []) as Array).duplicate()
	var count := (plate.get("holes", []) as Array).size()
	while names.size() < count:
		names.append("")
	names.resize(count)
	return names


## The plate's mesh name in the GLB (frame_arm_FL), or "".
static func plate_mesh(plate: Dictionary) -> String:
	return str(plate.get("mesh", ""))


## Which plate a GLB mesh name is: -1 if none.
static func plate_of_mesh(document: AirframeDocument, mesh_name: String) -> int:
	if document == null or mesh_name == "":
		return -1
	for i in document.plates.size():
		if plate_mesh(document.plates[i]) == mesh_name:
			return i
	return -1


## Which (plate, hole) a pick proxy name is: Vector2i(-1, -1) if none.
static func hole_of_proxy(document: AirframeDocument, proxy_name: String) -> Vector2i:
	if document == null or proxy_name == "":
		return Vector2i(-1, -1)
	for i in document.plates.size():
		var at := hole_names(document.plates[i]).find(proxy_name)
		if at >= 0:
			return Vector2i(i, at)
	return Vector2i(-1, -1)


## The plate in words: "arm", "top plate", "bottom plate".
static func plate_noun(plate: Dictionary) -> String:
	match str(plate.get("role", "")):
		AirframeDocument.ROLE_ARM: return "arm"
		AirframeDocument.ROLE_TOP: return "top plate"
		AirframeDocument.ROLE_BOTTOM: return "bottom plate"
	return "plate"


## A hole in words, for a refusal: "the motor pad's screw hole", "pocket 2".
static func hole_label(plate: Dictionary, hole_index: int) -> String:
	var name := str(hole_names(plate)[hole_index]) if hole_index < hole_names(plate).size() else ""
	if name.begins_with("motor_bore"):
		return "the motor's centre bore"
	if name.begins_with("motor_bolt"):
		return "the motor pad's screw hole"
	if name.begins_with("standoff"):
		return "a standoff screw hole"
	if name.begins_with("pick_pocket_"):
		return "pocket %s" % name.get_slice("_", name.get_slice_count("_") - 1)
	if name.begins_with("pick_hole_"):
		return "hole %s" % name.get_slice("_", name.get_slice_count("_") - 1)
	return "an existing cut"


static func is_pocket(plate: Dictionary, hole_index: int) -> bool:
	return str(hole_names(plate)[hole_index]).begins_with("pick_pocket_")


## Whether a cut is held to the web rule rather than the 1.5x-diameter bolt rule: a pocket, or the
## motor's centre bore (a shaft clearance, not a bolt hole, so nothing tears out of its edge).
static func is_webbed(plate: Dictionary, hole_index: int) -> bool:
	return is_pocket(plate, hole_index) or str(hole_names(plate)[hole_index]).begins_with("motor_bore")


## The next free proxy name of `kind` ("hole" or "pocket") on a plate.
static func next_name(plate: Dictionary, kind: String) -> String:
	var owner := str(plate.get("owner", "plate"))
	var prefix := "pick_%s_%s_" % [kind, owner]
	var top := 0
	for name in hole_names(plate):
		if str(name).begins_with(prefix):
			top = maxi(top, int(str(name).substr(prefix.length())))
	return prefix + str(top + 1)


# ---------------------------------------------------------------------------
# Drill
# ---------------------------------------------------------------------------

## Whether a `d_mm` hole may be drilled at `centre` (plate plan mm). Never writes.
static func drill_verdict(document: AirframeDocument, plate_index: int, centre: Vector2,
		d_mm: float) -> Dictionary:
	var gate := _plate_gate(document, plate_index)
	if not gate["ok"]:
		return gate
	if not is_finite(d_mm) or d_mm < FREE_MIN_D_MM or d_mm > FREE_MAX_D_MM:
		return refuse("A drilled hole must be %.1f to %.1f mm across." % [FREE_MIN_D_MM, FREE_MAX_D_MM])
	var plate: Dictionary = document.plates[plate_index]
	var noun := plate_noun(plate)
	var outline := AirframeDocument.plate_outline(plate)
	if not Geometry2D.is_point_in_polygon(centre, outline):
		return refuse("That point is off the %s: there is no material there to drill." % noun)
	var holes := AirframeDocument.plate_holes(plate)
	var r := d_mm * 0.5
	for i in holes.size():
		var hole: PackedVector2Array = holes[i]
		if Geometry2D.is_point_in_polygon(centre, hole):
			return refuse("That point is inside %s: there is no material there to drill." % hole_label(plate, i))
		if PolygonProps.distance_to_boundary(hole, centre) < r:
			return refuse("That hole would cut through %s." % hole_label(plate, i))
	var need := HardwareMass.EDGE_DISTANCE_RATIO * d_mm
	var edge := PolygonProps.distance_to_boundary(outline, centre)
	if edge < need:
		return refuse("Too close to the %s's edge: a %.1f mm hole needs %.1f mm (1.5x diameter) from its centre to the edge, and this is %.1f mm." % [
			noun, d_mm, need, edge])
	for i in holes.size():
		var gap := PolygonProps.distance_to_boundary(holes[i], centre)
		if gap < need:
			return refuse("Too close to %s: a %.1f mm hole needs %.1f mm (1.5x diameter) from its centre to any cut, and this is %.1f mm." % [
				hole_label(plate, i), d_mm, need, gap])
	return ok()


## Drills the hole if the verdict allows it. The hole is wound opposite to the outline (it subtracts)
## and named with the plate's next free proxy name.
static func drill(document: AirframeDocument, plate_index: int, centre: Vector2, d_mm: float) -> Dictionary:
	var verdict := drill_verdict(document, plate_index, centre, d_mm)
	if not verdict["ok"]:
		return verdict
	var circle := PolygonProps.tessellate_circle(centre, d_mm * 0.5, DRILL_CHORD_TOLERANCE_MM, true)
	_append_cut(document.plates[plate_index], circle, "hole")
	return verdict


# ---------------------------------------------------------------------------
# Pocket
# ---------------------------------------------------------------------------

## A rectangle pocket, `size` mm across, turned `angle_rad`, as a cut polygon (clockwise).
static func rect_pocket(centre: Vector2, size: Vector2, angle_rad: float = 0.0) -> PackedVector2Array:
	var h := size.abs() * 0.5
	var out := PackedVector2Array()
	for corner in [Vector2(-h.x, -h.y), Vector2(-h.x, h.y), Vector2(h.x, h.y), Vector2(h.x, -h.y)]:
		out.append(centre + (corner as Vector2).rotated(angle_rad))
	return PlateLayers.cw(out)


## A slot pocket from `a` to `b`, `width_mm` wide with round ends, as a cut polygon (clockwise).
static func slot_pocket(a: Vector2, b: Vector2, width_mm: float) -> PackedVector2Array:
	var r := absf(width_mm) * 0.5
	if r <= 0.0:
		return PackedVector2Array()
	var axis := b - a
	var angle := axis.angle() if axis.length() > 1.0e-9 else 0.0
	var out := PackedVector2Array()
	out.append_array(PolygonProps.tessellate_arc(b, r, angle - PI * 0.5, PI, DRILL_CHORD_TOLERANCE_MM * 4.0))
	out.append_array(PolygonProps.tessellate_arc(a, r, angle + PI * 0.5, PI, DRILL_CHORD_TOLERANCE_MM * 4.0))
	return PlateLayers.cw(out)


## Whether `pocket` (a closed polygon, plate plan mm) may be cut. Never writes.
static func pocket_verdict(document: AirframeDocument, plate_index: int, cut: PackedVector2Array) -> Dictionary:
	var gate := _plate_gate(document, plate_index)
	if not gate["ok"]:
		return gate
	if cut.size() < 3 or absf(PolygonProps.area(cut)) < 1.0e-6:
		return refuse("A pocket needs an area: drag out a rectangle or a slot.")
	var plate: Dictionary = document.plates[plate_index]
	var noun := plate_noun(plate)
	var outline := PlateLayers.ccw(AirframeDocument.plate_outline(plate))
	var shape := PlateLayers.ccw(cut)
	if Geometry2D.intersect_polygons(outline, shape).is_empty():
		return refuse("That pocket is off the %s." % noun)
	var pieces := 0
	for piece in Geometry2D.clip_polygons(outline, shape):
		if PolygonProps.area(piece) > 0.0:
			pieces += 1
	if pieces > 1:
		return refuse("That pocket would cut the %s in two." % noun)
	for point in shape:
		if not Geometry2D.is_point_in_polygon(point, outline):
			return refuse("That pocket breaks through the %s's edge: a pocket must be closed." % noun)
	var holes := AirframeDocument.plate_holes(plate)
	for i in holes.size():
		var hole := PlateLayers.ccw(holes[i])
		if not Geometry2D.intersect_polygons(shape, hole).is_empty():
			return refuse("That pocket would cut through %s." % hole_label(plate, i))
	var web := _polygon_gap(shape, outline)
	if web < MIN_WEB_MM:
		return refuse("That pocket leaves a %.1f mm web to the %s's edge, under the %.1f mm assumed minimum." % [
			web, noun, MIN_WEB_MM])
	for i in holes.size():
		var gap := _polygon_gap(shape, holes[i])
		if gap < MIN_WEB_MM:
			return refuse("That pocket leaves a %.1f mm web to %s, under the %.1f mm assumed minimum." % [
				gap, hole_label(plate, i), MIN_WEB_MM])
	return ok()


static func pocket(document: AirframeDocument, plate_index: int, shape: PackedVector2Array) -> Dictionary:
	var verdict := pocket_verdict(document, plate_index, shape)
	if not verdict["ok"]:
		return verdict
	_append_cut(document.plates[plate_index], PlateLayers.cw(shape), "pocket")
	return verdict


# ---------------------------------------------------------------------------
# Fill
# ---------------------------------------------------------------------------

## Whether hole `hole_index` (a hole or a pocket) may be filled back in. Never writes.
static func fill_verdict(document: AirframeDocument, plate_index: int, hole_index: int) -> Dictionary:
	var gate := _plate_gate(document, plate_index)
	if not gate["ok"]:
		return gate
	var plate: Dictionary = document.plates[plate_index]
	if hole_index < 0 or hole_index >= (plate.get("holes", []) as Array).size():
		return refuse("There is no such hole to fill.")
	var name := str(hole_names(plate)[hole_index])
	if name.begins_with("motor_"):
		return refuse("The motor is bolted through that hole; it cannot be filled.")
	if name.begins_with("standoff"):
		return refuse("A standoff screw goes through that hole; it cannot be filled.")
	return ok()


static func fill(document: AirframeDocument, plate_index: int, hole_index: int) -> Dictionary:
	var verdict := fill_verdict(document, plate_index, hole_index)
	if not verdict["ok"]:
		return verdict
	var plate: Dictionary = document.plates[plate_index]
	var holes: Array = plate["holes"]
	var names := hole_names(plate)
	holes.remove_at(hole_index)
	names.remove_at(hole_index)
	plate["holes"] = holes
	plate[NAMES_KEY] = names
	# A countersink flag indexes holes, so the indices after the filled one move down by one.
	if plate.has(AirframeDocument.PLATE_COUNTERSUNK_HOLES):
		var kept: Array = []
		for entry in plate[AirframeDocument.PLATE_COUNTERSUNK_HOLES]:
			if int(entry) < hole_index:
				kept.append(int(entry))
			elif int(entry) > hole_index:
				kept.append(int(entry) - 1)
		plate[AirframeDocument.PLATE_COUNTERSUNK_HOLES] = kept
	return verdict


# ---------------------------------------------------------------------------
# Thickness and arm width
# ---------------------------------------------------------------------------

## Thickness changes no edge distance, so only the bounds can refuse it.
static func thickness_verdict(document: AirframeDocument, plate_index: int, thickness_mm: float) -> Dictionary:
	var gate := _plate_gate(document, plate_index)
	if not gate["ok"]:
		return gate
	if not is_finite(thickness_mm) or thickness_mm < THICKNESS_MIN_MM or thickness_mm > THICKNESS_MAX_MM:
		return refuse("Plate thickness must be %.1f to %.1f mm." % [THICKNESS_MIN_MM, THICKNESS_MAX_MM])
	return ok()


static func set_thickness(document: AirframeDocument, plate_index: int, thickness_mm: float) -> Dictionary:
	var verdict := thickness_verdict(document, plate_index, thickness_mm)
	if verdict["ok"]:
		(document.plates[plate_index] as Dictionary)["thickness_mm"] = thickness_mm
	return verdict


## The arm's width now, as a multiple of the arm as drawn.
static func arm_width(document: AirframeDocument, plate_index: int) -> float:
	if document == null or plate_index < 0 or plate_index >= document.plates.size():
		return 1.0
	return float((document.plates[plate_index] as Dictionary).get(WIDTH_SCALE_KEY, 1.0))


## The arm's outline at width `scale` (of as drawn): every vertex BEHIND the motor centre moves
## across the arm axis by scale/current; the motor pad (at and beyond the tip) stays as drawn, so
## the motor still bolts on. Holes stay where they are.
static func arm_outline_at(plate: Dictionary, scale: float) -> PackedVector2Array:
	var root := AirframeDocument.point_of(plate.get("root_point", [0.0, 0.0]))
	var tip := AirframeDocument.point_of(plate.get("tip_point", [0.0, 0.0]))
	var axis := (tip - root).normalized()
	var across := Vector2(-axis.y, axis.x)
	var factor := scale / float(plate.get(WIDTH_SCALE_KEY, 1.0))
	var tip_along := (tip - root).dot(axis)
	var out := PackedVector2Array()
	for point in AirframeDocument.plate_outline(plate):
		var along := (point - root).dot(axis)
		if along < tip_along - 1.0e-6:
			var off := (point - root).dot(across)
			out.append(root + axis * along + across * off * factor)
		else:
			out.append(point)
	return out


static func arm_width_verdict(document: AirframeDocument, plate_index: int, scale: float) -> Dictionary:
	var gate := _plate_gate(document, plate_index)
	if not gate["ok"]:
		return gate
	var plate: Dictionary = document.plates[plate_index]
	if str(plate.get("role", "")) != AirframeDocument.ROLE_ARM or not plate.has("tip_point"):
		return refuse("Only an arm has a width to change.")
	if not is_finite(scale) or scale < ARM_WIDTH_MIN or scale > ARM_WIDTH_MAX:
		return refuse("Arm width must be %d%% to %d%% of the arm as drawn." % [
			roundi(ARM_WIDTH_MIN * 100.0), roundi(ARM_WIDTH_MAX * 100.0)])
	var before := AirframeDocument.plate_outline(plate)
	var after := arm_outline_at(plate, scale)
	var holes := AirframeDocument.plate_holes(plate)
	for i in holes.size():
		var hole: PackedVector2Array = holes[i]
		for point in hole:
			if not Geometry2D.is_point_in_polygon(point, after):
				return refuse("That width would leave %s outside the arm." % hole_label(plate, i))
		# A breach the arm as drawn already has (the motor pad's screw holes sit 3.7 mm in) is not
		# this edit's to refuse; making one, or making one worse, is.
		var need := MIN_WEB_MM if is_webbed(plate, i) else HardwareMass.EDGE_DISTANCE_RATIO * _diameter(hole)
		var now := _edge_measure(plate, i, hole, before)
		var then := _edge_measure(plate, i, hole, after)
		if then < need and then < now - 1.0e-6:
			return refuse("That width leaves %s %.1f mm from the arm's edge, under the %.1f mm it needs." % [
				hole_label(plate, i), then, need])
	return ok()


static func set_arm_width(document: AirframeDocument, plate_index: int, scale: float) -> Dictionary:
	var verdict := arm_width_verdict(document, plate_index, scale)
	if not verdict["ok"]:
		return verdict
	var plate: Dictionary = document.plates[plate_index]
	plate["outline"] = AirframeDocument.flatten(arm_outline_at(plate, scale))
	plate[WIDTH_SCALE_KEY] = scale
	return verdict


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _plate_gate(document: AirframeDocument, plate_index: int) -> Dictionary:
	if document == null:
		return refuse("This frame has no editable drawing.")
	if plate_index < 0 or plate_index >= document.plates.size():
		return refuse("Pick a plate or an arm first.")
	if AirframeDocument.is_upright(document.plates[plate_index]):
		return refuse("Upright plates are edited in the plan editor.")
	return ok()


static func _append_cut(plate: Dictionary, points: PackedVector2Array, kind: String) -> void:
	var name := next_name(plate, kind)
	var names := hole_names(plate)
	var holes: Array = plate.get("holes", [])
	holes.append(AirframeDocument.flatten(points))
	names.append(name)
	plate["holes"] = holes
	plate[NAMES_KEY] = names


## A hole's centre, as the mean of its vertices (exact for a regular tessellated circle).
static func centre_of(hole: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for point in hole:
		sum += point
	return sum / maxf(hole.size(), 1)


static func _diameter(hole: PackedVector2Array) -> float:
	var c := centre_of(hole)
	var sum := 0.0
	for point in hole:
		sum += point.distance_to(c)
	return 2.0 * sum / maxf(hole.size(), 1)


## The edge figure the rules use for one cut: a round hole's centre-to-edge distance, a pocket's web.
static func _edge_measure(plate: Dictionary, index: int, hole: PackedVector2Array,
		outline: PackedVector2Array) -> float:
	if is_webbed(plate, index):
		return _polygon_gap(hole, outline)
	return PolygonProps.distance_to_boundary(outline, centre_of(hole))


## The narrowest gap between two non-crossing polygons' boundaries.
static func _polygon_gap(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var best := INF
	for point in a:
		best = minf(best, PolygonProps.distance_to_boundary(b, point))
	for point in b:
		best = minf(best, PolygonProps.distance_to_boundary(a, point))
	return best
