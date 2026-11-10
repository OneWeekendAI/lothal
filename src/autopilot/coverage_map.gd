class_name CoverageMap
extends RefCounted
## SR5.3: the union of photo footprints as a raster, with a per-cell COUNT of how many images cover the cell. A cell is MAPPED
## when its count reaches the required overlap (`required` images, 1 = seen at least once, 2 = in at least two photos, ...).
## The area of what was mapped is cells x cell area, read from the flown footprints (precision rule P1): never field / swath.
## Cells are horizontal (map projection) squares of `cell_m` in the sim's XZ plane; on sloping ground this is the map area, not
## the surface area. m2 -> acres / hectares goes through Geodesy so the conversion factors live in one place.

var cell_m := 1.0
var x0 := 0.0
var z0 := 0.0
var cols := 0
var rows := 0
var count := PackedInt32Array()
var images := 0


static func covering(bounds: Rect2, p_cell_m: float = 1.0) -> CoverageMap:
	var m := CoverageMap.new()
	m.cell_m = p_cell_m
	m.x0 = bounds.position.x
	m.z0 = bounds.position.y
	m.cols = maxi(1, int(ceil(bounds.size.x / p_cell_m)))
	m.rows = maxi(1, int(ceil(bounds.size.y / p_cell_m)))
	m.count.resize(m.cols * m.rows)
	return m


func _centre(col: int, row: int) -> Vector2:
	return Vector2(x0 + (col + 0.5) * cell_m, z0 + (row + 0.5) * cell_m)


## Adds one photo: every cell whose centre lies inside the (convex) footprint quadrilateral (either winding) gets +1.
func add_footprint(corners: PackedVector2Array) -> void:
	if corners.size() != 4:
		return
	images += 1
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in corners:
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	var c0 := maxi(0, int(floor((lo.x - x0) / cell_m)))
	var c1 := mini(cols - 1, int(floor((hi.x - x0) / cell_m)))
	var r0 := maxi(0, int(floor((lo.y - z0) / cell_m)))
	var r1 := mini(rows - 1, int(floor((hi.y - z0) / cell_m)))
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			if _inside_convex(corners, _centre(c, r)):
				count[r * cols + c] += 1


static func _inside_convex(p: PackedVector2Array, pt: Vector2) -> bool:
	var pos := false
	var neg := false
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		var cr := (b.x - a.x) * (pt.y - a.y) - (b.y - a.y) * (pt.x - a.x)
		if cr > 0.0:
			pos = true
		elif cr < 0.0:
			neg = true
	return not (pos and neg)


func overlap_at(x: float, z: float) -> int:
	var c := int(floor((x - x0) / cell_m))
	var r := int(floor((z - z0) / cell_m))
	if c < 0 or r < 0 or c >= cols or r >= rows:
		return 0
	return count[r * cols + c]


## Cells mapped (count >= required), optionally only those whose centre is inside `polygon` (an empty polygon means all cells).
func mapped_cells(required: int = 1, polygon: PackedVector2Array = PackedVector2Array()) -> int:
	var n := 0
	for r in rows:
		for c in cols:
			if count[r * cols + c] >= required and (polygon.size() < 3 or Geometry2D.is_point_in_polygon(_centre(c, r), polygon)):
				n += 1
	return n


## {m2, acres, hectares, cells, required}: the mapped area. Acres and hectares come from Geodesy.
func mapped_area(required: int = 1, polygon: PackedVector2Array = PackedVector2Array()) -> Dictionary:
	var cells := mapped_cells(required, polygon)
	var m2 := float(cells) * cell_m * cell_m
	return {"m2": m2, "acres": Geodesy.m2_to_acres(m2), "hectares": Geodesy.m2_to_hectares(m2), "cells": cells, "required": required}


## Cells inside `polygon` that are NOT mapped: {m2, cells}.
func hole_area(required: int, polygon: PackedVector2Array) -> Dictionary:
	var inside := 0
	for r in rows:
		for c in cols:
			if Geometry2D.is_point_in_polygon(_centre(c, r), polygon):
				inside += 1
	var cells := inside - mapped_cells(required, polygon)
	return {"m2": float(cells) * cell_m * cell_m, "cells": cells}


## Mean number of photos per cell over the cells whose centre is inside `polygon` (an empty polygon means all cells). 0 when there are none.
func mean_count(polygon: PackedVector2Array = PackedVector2Array()) -> float:
	var total := 0
	var cells := 0
	for r in rows:
		for c in cols:
			if polygon.size() < 3 or Geometry2D.is_point_in_polygon(_centre(c, r), polygon):
				total += count[r * cols + c]
				cells += 1
	return float(total) / float(cells) if cells > 0 else 0.0
