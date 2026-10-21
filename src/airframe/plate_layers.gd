class_name PlateLayers
extends RefCounted
## Which plates are ONE piece of material: flat plates on one layer — same height, same thickness, same
## material — whose outlines overlap. A generated frame's arms all reach the centre and its bottom plate
## sits on their layer, so as plates they overlap; as material they are one unibody. Two readers need
## that answer and must agree on it: `FrameExport` prints the union as one part, and
## `AirframeProperties` weighs the union once rather than the overlap twice.

## A vertex closer than this to the line through its neighbours is on a straight edge, for a printed
## part (`_simplified`). A micron: far below any nozzle, far above float rounding in a union.
const COLLINEAR_MM := 1.0e-3


## Flat (not upright) plates as groups of indices into `document.plates`, each group in document order
## and the groups in order of their first plate. `merge` false gives every plate its own group. A plate
## with no outline or no thickness is always on its own.
static func flat_groups(document: AirframeDocument, merge: bool = true) -> Array:
	var flat: Array[int] = []
	for index in document.plates.size():
		if not AirframeDocument.is_upright(document.plates[index]):
			flat.append(index)
	var group := {}
	for index in flat:
		group[index] = index
	if merge:
		for a in flat.size():
			for b in range(a + 1, flat.size()):
				var pa: Dictionary = document.plates[flat[a]]
				var pb: Dictionary = document.plates[flat[b]]
				if not solid_plate(pa) or not solid_plate(pb) or not same_layer(document, pa, pb):
					continue
				if Geometry2D.intersect_polygons(ccw(AirframeDocument.plate_outline(pa)),
						ccw(AirframeDocument.plate_outline(pb))).is_empty():
					continue
				group[_root_of(group, flat[a])] = _root_of(group, flat[b])
	var members := {}
	for index in flat:
		var root := _root_of(group, index)
		if not members.has(root):
			members[root] = []
		(members[root] as Array).append(index)
	var out: Array = []
	for index in flat:
		var list: Array = members[_root_of(group, index)]
		if int(list[0]) == index:
			out.append(list.duplicate())
	return out


## The union of plates' outlines and every hole that falls in it. Holes that overlap merge; a hole
## that crosses the edge becomes a notch in the outline.
static func region_of(plates: Array) -> Dictionary:
	var outlines: Array = []
	var holes: Array = []
	for plate in plates:
		var merged := ccw(AirframeDocument.plate_outline(plate))
		var keep: Array = []
		for existing in outlines:
			if Geometry2D.intersect_polygons(existing, merged).is_empty():
				keep.append(existing)
				continue
			var best := PackedVector2Array()
			for piece in Geometry2D.merge_polygons(existing, merged):
				if PolygonProps.area(piece) < 0.0:
					holes.append(ccw(piece))
				elif PolygonProps.area(piece) > PolygonProps.area(best):
					best = piece
			merged = best
		keep.append(merged)
		outlines = keep
	for plate in plates:
		for hole in AirframeDocument.plate_holes(plate):
			holes.append(ccw(hole))

	var interior: Array = []
	for hole in holes:
		for index in outlines.size():
			var outline: PackedVector2Array = outlines[index]
			var overlap := Geometry2D.intersect_polygons(outline, hole)
			if overlap.is_empty():
				continue
			var inside := true
			for point in hole:
				if not Geometry2D.is_point_in_polygon(point, outline):
					inside = false
					break
			if inside:
				interior.append(hole)
			else:
				var pieces: Array = []
				for piece in Geometry2D.clip_polygons(outline, hole):
					if PolygonProps.area(piece) > 0.0:
						pieces.append(piece)
				outlines.remove_at(index)
				outlines.append_array(pieces)
			break
	# Overlapping holes become one.
	var joined: Array = []
	for hole in interior:
		var merged: PackedVector2Array = hole
		var keep: Array = []
		for existing in joined:
			if Geometry2D.intersect_polygons(existing, merged).is_empty():
				keep.append(existing)
				continue
			for piece in Geometry2D.merge_polygons(existing, merged):
				if PolygonProps.area(piece) > 0.0:
					merged = piece
		keep.append(merged)
		joined = keep
	var cw_holes: Array = []
	for hole in joined:
		cw_holes.append(cw(simplified(hole)))
	var ccw_outlines: Array = []
	for outline in outlines:
		ccw_outlines.append(ccw(simplified(outline)))
	return {"outlines": ccw_outlines, "holes": cw_holes}


## A loop without repeated points or points on a straight run. A union leaves a vertex wherever two
## outlines crossed, and one that lands on a straight edge makes a cap triangle of zero area: dropped,
## it leaves the wall edges beside it with no cap to meet; kept, it is a facet a slicer rejects. Taking
## the vertex out of the loop removes the choice — the wall and the cap both skip it.
static func simplified(points: PackedVector2Array) -> PackedVector2Array:
	var out := points
	var changed := true
	while changed and out.size() > 3:
		changed = false
		for index in out.size():
			var before := out[(index - 1 + out.size()) % out.size()]
			var here := out[index]
			var after := out[(index + 1) % out.size()]
			var span := after - before
			var off_line := absf(span.cross(here - before)) / maxf(span.length(), 1.0e-12)
			if here.distance_to(before) < COLLINEAR_MM or off_line < COLLINEAR_MM:
				out = out.duplicate()
				out.remove_at(index)
				changed = true
				break
	return out


static func solid_plate(plate: Dictionary) -> bool:
	return AirframeDocument.plate_outline(plate).size() >= 3 \
		and AirframeDocument.plate_thickness_mm(plate) > 0.0


static func same_layer(document: AirframeDocument, a: Dictionary, b: Dictionary) -> bool:
	return absf(AirframeDocument.plate_z_mm(a) - AirframeDocument.plate_z_mm(b)) < 1.0e-6 \
		and absf(AirframeDocument.plate_thickness_mm(a) - AirframeDocument.plate_thickness_mm(b)) \
			< 1.0e-6 \
		and document.plate_material_id(a) == document.plate_material_id(b)


static func _root_of(group: Dictionary, index: int) -> int:
	var at := index
	while int(group[at]) != at:
		at = int(group[at])
	return at


## "bottom", "top", or for a merged layer its roles in order: "bottom+4arm".
static func name_of(plates: Array) -> String:
	var counts := {}
	for plate in plates:
		var role := str(plate.get("role", "plate"))
		counts[role] = int(counts.get(role, 0)) + 1
	var names := PackedStringArray()
	for role in [AirframeDocument.ROLE_BOTTOM, AirframeDocument.ROLE_MID, AirframeDocument.ROLE_TOP,
			AirframeDocument.ROLE_ARM]:
		if counts.has(role):
			var count := int(counts[role])
			names.append(role if count == 1 else "%d%s" % [count, role])
			counts.erase(role)
	for role in counts:
		names.append(str(role))
	return "+".join(names)


static func ccw(points: PackedVector2Array) -> PackedVector2Array:
	return PolygonProps.reversed(points) if PolygonProps.area(points) < 0.0 else points


static func cw(points: PackedVector2Array) -> PackedVector2Array:
	return PolygonProps.reversed(points) if PolygonProps.area(points) > 0.0 else points
