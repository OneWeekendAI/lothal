class_name FrameExport
extends RefCounted
## Getting a frame OUT of Lothal: a sheet you can print at 1:1, outlines a cutter can read, and a
## solid another program can open.
##
## ## Why this exists at all
##
## A frame you cannot cut is a drawing, not a design. Every other number this room computes — mass,
## inertia, the arm's first mode — is a claim about a part that does not exist yet, and the only
## way anybody finds out whether the claim was right is by having the part made. So export is not a
## convenience feature bolted on at the end; it is the step that closes the loop the whole room is
## built around, and it is the reason the plan view was made to draw the physics' own polygons
## rather than a prettier stand-in. What you print IS what was weighed.
##
## ## Formats, and why these three
##
##   - **SVG** — because it is the only vector format a browser, a phone and every drawing program
##     open without asking, and because it can be printed at exactly 1:1. That last property is
##     what makes the paper sheet useful: you lay a cut plate on the print and see whether it is
##     right, which is a check no on-screen dimension can give you.
##   - **DXF** — because that is what a CNC router, a waterjet and every carbon-cutting service
##     take. Emitted in the R12 entity form deliberately: it is the oldest and therefore the most
##     universally readable dialect, and a frame outline needs nothing newer than a polyline.
##   - **STL** — because it is the assembly, and the assembly is what you check for fit against a
##     stack, a camera or a printed part somebody modelled elsewhere.
##
## JSON is not in this list because the document IS JSON — `AirframeDocument.save_to` already
## writes the whole thing, unknown fields and all, and a second "export to JSON" would be a worse
## copy of it.
##
## ## Units, stated once and never converted twice
##
## The document is millimetres. SVG is emitted with a `mm` viewBox and explicit `width`/`height` in
## mm, so 1 user unit = 1 mm and a printer at 100% produces a 1:1 sheet. DXF is unitless by
## convention and every tool that reads one assumes millimetres for this kind of part, so the
## numbers go out unchanged. STL is likewise millimetres, which is what every slicer and CAD import
## dialog defaults to.

## Margin around a cut sheet, mm. Printers cannot print to the edge, and a plate that lands in the
## unprintable band comes out silently truncated — which on a 1:1 sheet is a part cut short.
const SHEET_MARGIN_MM := 12.0
## Gap between plates on a nested cut sheet, mm. Enough for a cutter's kerf and a pair of hands.
const NEST_GAP_MM := 8.0
## Stroke width of a cut line, mm. Thin, because on a 1:1 print the line's own width is an error
## against the part: 0.2 mm is about as fine as a domestic printer resolves.
const CUT_STROKE_MM := 0.2

## What a sheet is FOR, which decides how the plates are arranged on it.
##
##   - `LAYOUT_ASSEMBLY` puts every plate where the document puts it: the frame as it will be, for
##     checking a stack against a print or handing somebody a drawing of the aircraft.
##   - `LAYOUT_NEST` separates the plates into a grid: the sheet you cut from, where two plates
##     overlapping means two parts a cutter cannot tell apart.
const LAYOUT_ASSEMBLY := "assembly"
const LAYOUT_NEST := "nest"


# ---------------------------------------------------------------------------
# SVG
# ---------------------------------------------------------------------------

## The printable sheet.
##
## `include_dimensions` adds the overall span and a scale bar. On by default for the same reason the
## canvas draws a scale bar: a drawing that leaves the building without a dimension on it is a
## drawing somebody will scale by eye.
static func to_svg(
	document: AirframeDocument,
	layout: String = LAYOUT_ASSEMBLY,
	include_dimensions: bool = true
) -> String:
	var placed := _placed_plates(document, layout)
	var bounds := _bounds_of(placed)
	var origin: Vector2 = bounds[0] - Vector2.ONE * SHEET_MARGIN_MM
	var span: Vector2 = (bounds[1] - bounds[0]) + Vector2.ONE * SHEET_MARGIN_MM * 2.0
	if span.x <= 0.0 or span.y <= 0.0:
		span = Vector2(100.0, 100.0)

	var out := PackedStringArray()
	out.append('<?xml version="1.0" encoding="UTF-8"?>')
	# width/height in mm AND a matching viewBox: together they are what makes a print 1:1. A
	# viewBox on its own scales to whatever the page is, which is precisely the thing this sheet
	# must not do.
	out.append(('<svg xmlns="http://www.w3.org/2000/svg" width="%.3fmm" height="%.3fmm" ' +
		'viewBox="%.3f %.3f %.3f %.3f">') % [
			span.x, span.y, origin.x, origin.y, span.x, span.y])
	out.append('<title>%s</title>' % _escaped(document.name))
	# Black hairlines on nothing: a cut file has no fill, because a filled region tells a cutter to
	# engrave it. The plate bodies below are drawn with `fill="none"` for exactly that reason, and
	# the holes are the same colour and the same stroke — a hole is a cut, not a decoration.
	out.append('<g fill="none" stroke="#000000" stroke-width="%.3f">' % CUT_STROKE_MM)

	for entry in placed:
		var plate: Dictionary = entry["plate"]
		var offset: Vector2 = entry["offset"]
		out.append('<path d="%s"/>' % _path_of(AirframeDocument.plate_outline(plate), offset))
		for hole in AirframeDocument.plate_holes(plate):
			out.append('<path d="%s"/>' % _path_of(hole, offset))

	out.append('</g>')
	if include_dimensions:
		out.append(_dimension_block(document, origin, span, bounds))
	out.append('</svg>')
	return "\n".join(out)


## One plate on its own sheet, for the case where a cutter wants a file per part.
static func plate_to_svg(document: AirframeDocument, plate_index: int) -> String:
	if document == null or plate_index < 0 or plate_index >= document.plates.size():
		return ""
	var single := AirframeDocument.new()
	single.name = "%s — plate %d" % [document.name, plate_index + 1]
	single.material_id = document.material_id
	single.plates = [document.plates[plate_index]]
	return to_svg(single, LAYOUT_NEST, true)


static func _dimension_block(
	document: AirframeDocument, origin: Vector2, span: Vector2, bounds: Array
) -> String:
	var size: Vector2 = bounds[1] - bounds[0]
	var text_y := origin.y + span.y - 3.0
	var lines := PackedStringArray()
	lines.append('<g font-family="sans-serif" font-size="4" fill="#000000" stroke="none">')
	lines.append('<text x="%.3f" y="%.3f">%s — %.1f × %.1f mm — %d plates — 1:1</text>' % [
		origin.x + 3.0, text_y, _escaped(document.name), size.x, size.y,
		document.plates.size()])
	lines.append('</g>')
	# A 50 mm bar, drawn as a cut-coloured line but outside every part, so a print that came out at
	# 97% is measurable with a ruler rather than trusted.
	# Ten millimetres above the caption, which is more than the 4 mm text is tall: at 6 mm the bar's
	# left tick landed inside the caption's last characters on a wide sheet.
	var bar_y := text_y - 10.0
	# Drawn as <line> elements rather than as a path, so that "one <path> per contour" stays a true
	# statement about the file: a cutter's importer and a reader counting parts both take every path
	# in the document as something to cut, and a scale bar is neither.
	lines.append('<g stroke="#000000" stroke-width="0.3">')
	for segment in [[origin.x + 3.0, bar_y, origin.x + 53.0, bar_y],
			[origin.x + 3.0, bar_y - 1.5, origin.x + 3.0, bar_y + 1.5],
			[origin.x + 53.0, bar_y - 1.5, origin.x + 53.0, bar_y + 1.5]]:
		lines.append('<line x1="%.3f" y1="%.3f" x2="%.3f" y2="%.3f"/>' % segment)
	lines.append('</g>')
	lines.append('<g font-family="sans-serif" font-size="3" fill="#000000" stroke="none">' +
		'<text x="%.3f" y="%.3f">50 mm</text></g>' % [origin.x + 56.0, bar_y + 1.0])
	return "\n".join(lines)


static func _path_of(points: PackedVector2Array, offset: Vector2) -> String:
	if points.size() < 2:
		return ""
	var out := PackedStringArray()
	for index in points.size():
		var point := points[index] + offset
		out.append("%s %.4f %.4f" % ["M" if index == 0 else "L", point.x, point.y])
	out.append("Z")
	return " ".join(out)


# ---------------------------------------------------------------------------
# DXF
# ---------------------------------------------------------------------------

## Every plate outline and hole as R12 polylines, one layer per plate role.
##
## THE HOLES KEEP THEIR OWN WINDING and are emitted as separate closed polylines rather than being
## merged into the outline. A cutter treats every closed contour as a cut and works out inside from
## outside by nesting, which is the same rule `PolygonProps` integrates by — so the file a machine
## reads and the polygon the mass was computed from agree about what is material without either
## needing a boolean operation.
static func to_dxf(document: AirframeDocument, layout: String = LAYOUT_NEST) -> String:
	var out := PackedStringArray()
	out.append("0\nSECTION\n2\nENTITIES")
	for entry in _placed_plates(document, layout):
		var plate: Dictionary = entry["plate"]
		var offset: Vector2 = entry["offset"]
		var layer := str(plate.get("role", "plate")).to_upper()
		out.append(_dxf_polyline(AirframeDocument.plate_outline(plate), offset, layer))
		for hole in AirframeDocument.plate_holes(plate):
			out.append(_dxf_polyline(hole, offset, "%s_HOLES" % layer))
	out.append("0\nENDSEC\n0\nEOF")
	return "\n".join(out) + "\n"


static func _dxf_polyline(points: PackedVector2Array, offset: Vector2, layer: String) -> String:
	if points.size() < 3:
		return ""
	var out := PackedStringArray()
	# 70/1 is the closed flag. Without it a cutter leaves the last edge uncut and the part stays
	# attached to the sheet by one tab — a failure that looks like a success right up to the moment
	# somebody tries to lift the plate out.
	out.append("0\nPOLYLINE\n8\n%s\n66\n1\n70\n1" % layer)
	for point in points:
		var moved := point + offset
		out.append("0\nVERTEX\n8\n%s\n10\n%.5f\n20\n%.5f\n30\n0.0" % [layer, moved.x, moved.y])
	out.append("0\nSEQEND\n8\n%s" % layer)
	return "\n".join(out)


# ---------------------------------------------------------------------------
# STL
# ---------------------------------------------------------------------------

## The assembly as a solid, in millimetres, in the document's own coordinates.
##
## ASCII rather than binary: an STL of a frame is a few hundred kilobytes either way, and a text
## file is one a human can open, diff and check the first triangle of. The project's standing rule
## about a binary a pull request cannot review applies here too.
##
## Z IS UP IN THE FILE, not in Godot's world. Every tool that opens an STL of a flat part expects
## the part to lie in XY, so the document's `(u, v, z)` goes out unrotated — which is the natural
## form and also the one where a plate's thickness is the Z extent.
static func to_stl(document: AirframeDocument) -> String:
	var out := PackedStringArray()
	out.append("solid %s" % document.name.replace(" ", "_"))
	for plate in document.plates:
		_append_plate_solid(out, plate)
	for pad in document.pads:
		_append_plate_solid(out, pad)
	out.append("endsolid")
	return "\n".join(out) + "\n"


static func _append_plate_solid(out: PackedStringArray, plate: Dictionary) -> void:
	var outline := AirframeDocument.plate_outline(plate)
	var thickness := AirframeDocument.plate_thickness_mm(plate)
	if outline.size() < 3 or thickness <= 0.0:
		return
	var z0 := AirframeDocument.plate_z_mm(plate)
	var z1 := z0 + thickness

	# The caps come from the same triangulator `PlateMesh` uses, so the exported solid and the
	# on-screen one are the same tessellation rather than two that can disagree.
	var indices := Geometry2D.triangulate_polygon(outline)
	var index := 0
	while index + 2 < indices.size():
		var a := outline[indices[index]]
		var b := outline[indices[index + 1]]
		var c := outline[indices[index + 2]]
		_facet(out, Vector3(a.x, a.y, z1), Vector3(b.x, b.y, z1), Vector3(c.x, c.y, z1))
		# The bottom face is the same triangle wound the other way, which is what makes its normal
		# point down. A cap emitted with both faces the same way round is a solid every slicer
		# reports as non-manifold.
		_facet(out, Vector3(c.x, c.y, z0), Vector3(b.x, b.y, z0), Vector3(a.x, a.y, z0))
		index += 3

	for vertex in outline.size():
		var p0 := outline[vertex]
		var p1 := outline[(vertex + 1) % outline.size()]
		_facet(out, Vector3(p0.x, p0.y, z0), Vector3(p1.x, p1.y, z0), Vector3(p1.x, p1.y, z1))
		_facet(out, Vector3(p0.x, p0.y, z0), Vector3(p1.x, p1.y, z1), Vector3(p0.x, p0.y, z1))


static func _facet(out: PackedStringArray, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	out.append("facet normal %.6f %.6f %.6f" % [normal.x, normal.y, normal.z])
	out.append("  outer loop")
	for point in [a, b, c]:
		out.append("    vertex %.5f %.5f %.5f" % [point.x, point.y, point.z])
	out.append("  endloop")
	out.append("endfacet")


# ---------------------------------------------------------------------------
# Writing, and the arrangement both vector formats share
# ---------------------------------------------------------------------------

## Writes one of the three formats to a path, chosen by extension. Returns whether it landed —
## said out loud by the caller, because a save that failed silently is an evening lost.
static func write(document: AirframeDocument, path: String, layout: String = LAYOUT_NEST) -> bool:
	var text := ""
	match path.get_extension().to_lower():
		"svg": text = to_svg(document, layout)
		"dxf": text = to_dxf(document, layout)
		"stl": text = to_stl(document)
		_: return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


## Where each plate sits on the sheet: itself for an assembly drawing, or a slot in a grid for a
## cut sheet.
##
## The grid is packed by bounding box in document order, which is the plain answer rather than the
## clever one, and every part keeps the ROTATION IT WAS DRAWN AT.
##
## That last part is not laziness, and it is the reason a tighter pack is not simply better. The
## frame materials here are anisotropic — `FrameMaterials.modulus_at_angle_gpa` exists because a 3K
## twill 0/90 plate is stiffer along its weave than across it — so an arm turned 40° to pack neatly
## is an arm cut off-axis, and it comes back from the cutter looking perfect and bending more than
## the beam model said it would. A nester that rotated parts would have to carry the fibre direction
## with each one, which is a feature, not a packing tweak. Until then the sheet wastes stock and
## every part is cut on the axis it was designed on.
static func _placed_plates(document: AirframeDocument, layout: String) -> Array:
	var out: Array = []
	if document == null:
		return out
	if layout != LAYOUT_NEST:
		for plate in document.plates:
			out.append({"plate": plate, "offset": Vector2.ZERO})
		return out

	var cursor := Vector2.ZERO
	var row_height := 0.0
	var row_limit := 0.0
	for plate in document.plates:
		var points := AirframeDocument.plate_outline(plate)
		if points.size() < 3:
			continue
		var box := _points_bounds(points)
		var extent: Vector2 = box[1] - box[0]
		row_limit = maxf(row_limit, extent.x)
		# One column per plate would make a metre-long sheet for an octocopter; the row wraps at
		# four times the widest part seen so far, which keeps a sheet roughly page-shaped whatever
		# the frame is.
		if cursor.x > 0.0 and cursor.x + extent.x > row_limit * 4.0:
			cursor = Vector2(0.0, cursor.y + row_height + NEST_GAP_MM)
			row_height = 0.0
		out.append({"plate": plate, "offset": cursor - box[0]})
		cursor.x += extent.x + NEST_GAP_MM
		row_height = maxf(row_height, extent.y)
	return out


static func _bounds_of(placed: Array) -> Array:
	var lowest := Vector2(INF, INF)
	var highest := Vector2(-INF, -INF)
	for entry in placed:
		var points := AirframeDocument.plate_outline(entry["plate"])
		for point in points:
			var moved: Vector2 = point + (entry["offset"] as Vector2)
			lowest = lowest.min(moved)
			highest = highest.max(moved)
	if not is_finite(lowest.x):
		return [Vector2.ZERO, Vector2.ZERO]
	return [lowest, highest]


static func _points_bounds(points: PackedVector2Array) -> Array:
	var lowest := Vector2(INF, INF)
	var highest := Vector2(-INF, -INF)
	for point in points:
		lowest = lowest.min(point)
		highest = highest.max(point)
	return [lowest, highest]


## XML text content, escaped. A frame called `Bob's <5"> build` is a frame somebody will name, and
## an unescaped apostrophe in a title is a file no viewer opens.
static func _escaped(text: String) -> String:
	return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;") \
		.replace('"', "&quot;")
