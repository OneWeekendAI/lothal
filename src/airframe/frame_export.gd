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
## Not a sheet layout: the Export menu's "one STL per printable part" (`write_parts`).
const LAYOUT_PARTS := "parts"

## G3 — the ready-to-cut extras. A DXF layer a cutter reads as "not a cut": the per-plate notes and
## the sheet header. Holes flagged countersunk go on `<ROLE>_COUNTERSINK` instead of `<ROLE>_HOLES`,
## so they are still cut (every layer is) and the shop can see which ones take a second operation.
const DXF_NOTES_LAYER := "NOTES"
const DXF_COUNTERSINK_SUFFIX := "_COUNTERSINK"
const DXF_NOTE_HEIGHT_MM := 2.5
## SVG notes: line pitch of the notes block, and the colour of the countersink marker — not black,
## because black on this sheet means "cut here" and a countersink ring is not a cut.
const SVG_NOTE_LINE_MM := 5.0
const COUNTERSINK_COLOUR := "#1f5fbf"
## A 90° countersink for a flat-head screw is about twice the clearance hole across; the marker ring
## is drawn there so it reads as the cone's rim on a 1:1 print. A drawing convention, not a spec.
const COUNTERSINK_MARK_RATIO := 2.0


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

	var notes := plate_notes(document)
	var base_span := span
	var note_lines := _svg_note_lines(document, notes)
	span.y += SVG_NOTE_LINE_MM * float(note_lines.size() + 1)

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
	out.append(_countersink_marks(placed))
	out.append(_plate_numbers(placed, notes))
	if include_dimensions:
		out.append(_dimension_block(document, origin, base_span, bounds))
	out.append(_notes_block(note_lines, origin, base_span))
	out.append('</svg>')
	return "\n".join(out)


## One plate on its own sheet, for the case where a cutter wants a file per part.
static func plate_to_svg(document: AirframeDocument, plate_index: int) -> String:
	if document == null or plate_index < 0 or plate_index >= document.plates.size():
		return ""
	var single := AirframeDocument.new()
	single.name = "%s — plate %d" % [document.name, plate_index + 1]
	single.material_id = document.material_id
	single.cutting_bit_mm = document.cutting_bit_mm
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
	var notes := plate_notes(document)
	var placed := _placed_plates(document, layout)
	var any_countersunk := false
	for entry in placed:
		var plate: Dictionary = entry["plate"]
		var offset: Vector2 = entry["offset"]
		var layer := str(plate.get("role", "plate")).to_upper()
		out.append(_dxf_polyline(AirframeDocument.plate_outline(plate), offset, layer))
		var holes := AirframeDocument.plate_holes(plate)
		for hole_index in holes.size():
			var countersunk := AirframeDocument.hole_is_countersunk(plate, hole_index)
			any_countersunk = any_countersunk or countersunk
			out.append(_dxf_polyline(holes[hole_index], offset,
				layer + (DXF_COUNTERSINK_SUFFIX if countersunk else "_HOLES")))
	# Notes last, on their own layer: one line under each plate, then the sheet header under all.
	var bounds := _bounds_of(placed)
	for entry in placed:
		var note := _note_for(notes, entry["plate"])
		if note.is_empty():
			continue
		var box := _points_bounds(AirframeDocument.plate_outline(entry["plate"]))
		var at: Vector2 = box[0] + (entry["offset"] as Vector2) - Vector2(0.0, DXF_NOTE_HEIGHT_MM * 1.6)
		out.append(_dxf_text(str(note["text"]), at, DXF_NOTE_HEIGHT_MM))
	var header_at: Vector2 = bounds[0] - Vector2(0.0, DXF_NOTE_HEIGHT_MM * 4.0)
	for line in _sheet_header_lines(document, notes, any_countersunk):
		out.append(_dxf_text(line, header_at, DXF_NOTE_HEIGHT_MM))
		header_at.y -= DXF_NOTE_HEIGHT_MM * 1.6
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


## R12 TEXT on the notes layer. ASCII only: an R12 file is read in the machine's ANSI code page, and a
## UTF-8 dash comes out as three characters of noise on a shop's controller.
static func _dxf_text(text: String, at: Vector2, height_mm: float) -> String:
	return "0\nTEXT\n8\n%s\n10\n%.5f\n20\n%.5f\n30\n0.0\n40\n%.3f\n1\n%s" % [
		DXF_NOTES_LAYER, at.x, at.y, height_mm, _ascii(text)]


static func _ascii(text: String) -> String:
	var out := ""
	for index in text.length():
		var code := text.unicode_at(index)
		out += text[index] if code >= 32 and code < 127 else "-"
	return out


# ---------------------------------------------------------------------------
# Plate notes (G3) — what the shop needs to know beside the geometry
# ---------------------------------------------------------------------------

## One note per plate: {"index", "label", "role", "thickness_mm", "material", "quantity", "bit_mm",
## "countersunk", "text"}. `quantity` is how many plates in this document are the same part — same
## role, stock, thickness, area, perimeter and hole count — so four radially replicated arms say
## "1 of 4 identical" and the shop can cut them as a batch. The sheet still draws every one of them.
static func plate_notes(document: AirframeDocument) -> Array:
	var out: Array = []
	if document == null:
		return out
	var materials := FrameMaterials.load_default()
	var bit := ReadyToCut.bit_diameter_mm(document)
	var signatures: Array = []
	var counts: Dictionary = {}
	for plate in document.plates:
		var signature := _part_signature(document, plate)
		signatures.append(signature)
		counts[signature] = int(counts.get(signature, 0)) + 1
	for index in document.plates.size():
		var plate: Dictionary = document.plates[index]
		var material_id := document.plate_material_id(plate)
		var record: Dictionary = materials.get_material(material_id)
		var material := str(record.get("name", material_id)) if record != null else material_id
		var quantity: int = counts[signatures[index]]
		var countersunk := 0
		for hole_index in (plate.get("holes", []) as Array).size():
			if AirframeDocument.hole_is_countersunk(plate, hole_index):
				countersunk += 1
		var label := ReadyToCut.plate_label(document, index)
		var text := "%s - %.1f mm %s - qty 1 of %d identical - %.2f mm bit" % [
			label, AirframeDocument.plate_thickness_mm(plate), material, quantity, bit]
		if countersunk > 0:
			text += " - %d countersunk hole%s" % [countersunk, "" if countersunk == 1 else "s"]
		var upright := AirframeDocument.is_upright(plate)
		if upright:
			# G5: the shop cuts it flat like any plate; the note says it is not one, and where it goes.
			text += " - upright side plate, cut flat, stands %.1f mm %s of centre" % [
				absf(AirframeDocument.plate_x_mm(plate)),
				"right" if AirframeDocument.plate_x_mm(plate) >= 0.0 else "left"]
		out.append({
			"upright": upright,
			"index": index, "label": label, "role": str(plate.get("role", "")),
			"thickness_mm": AirframeDocument.plate_thickness_mm(plate), "material": material,
			"quantity": quantity, "bit_mm": bit, "countersunk": countersunk, "text": text,
			"plate": plate,
		})
	return out


## The bounding rectangle of `plates` laid out as the cut sheet lays them (`LAYOUT_NEST`), mm — the
## stock a shop has to put on the bed for them (airframe gaps G6 prices it). The same arrangement the
## exported cut sheet draws, so the estimate and the file describe one sheet.
static func nest_rect_mm(plates: Array) -> Rect2:
	var temp := AirframeDocument.new()
	temp.plates = plates
	var placed := _placed_plates(temp, LAYOUT_NEST)
	if placed.is_empty():
		return Rect2()
	var bounds := _bounds_of(placed)
	return Rect2(bounds[0], (bounds[1] as Vector2) - (bounds[0] as Vector2))


## "Same part" for counting quantities: role, stock, thickness, area, perimeter and hole count.
static func part_signature(document: AirframeDocument, plate: Dictionary) -> String:
	return _part_signature(document, plate)


static func _part_signature(document: AirframeDocument, plate: Dictionary) -> String:
	var outline := AirframeDocument.plate_outline(plate)
	var perimeter := 0.0
	for i in outline.size():
		perimeter += outline[i].distance_to(outline[(i + 1) % outline.size()])
	var region := PolygonProps.region_properties(outline, AirframeDocument.plate_holes(plate))
	return "%s|%s|%.2f|%.0f|%.0f|%d" % [str(plate.get("role", "")), document.plate_material_id(plate),
		AirframeDocument.plate_thickness_mm(plate), absf(float(region.get("area", 0.0))),
		perimeter, (plate.get("holes", []) as Array).size()]


static func _note_for(notes: Array, plate: Dictionary) -> Dictionary:
	for note in notes:
		if is_same(note["plate"], plate):
			return note
	return {}


static func _sheet_header_lines(document: AirframeDocument, notes: Array,
		any_countersunk: bool) -> PackedStringArray:
	var lines := PackedStringArray()
	var bit := ReadyToCut.bit_diameter_mm(document)
	lines.append("%s - %d parts - millimetres, 1:1 - cut with a %.4f mm (%s) end mill" % [
		document.name, notes.size(), bit, _bit_label(bit)])
	lines.append("Layer NOTES is text, not a cut.")
	if any_countersunk:
		lines.append("Holes on *%s layers: cut through, then countersink 90 deg for flat-head screws."
			% DXF_COUNTERSINK_SUFFIX)
	return lines


## "1/16 in, typical shop value" for the default; the inch fraction for the other common bits.
static func _bit_label(diameter_mm: float) -> String:
	if absf(diameter_mm - AirframeDocument.DEFAULT_CUTTING_BIT_MM) < 1e-4:
		return "1/16 in, a typical shop value"
	if absf(diameter_mm - 3.175) < 1e-4:
		return "1/8 in"
	if absf(diameter_mm - 0.79375) < 1e-4:
		return "1/32 in"
	return "set by the builder"


static func _svg_note_lines(document: AirframeDocument, notes: Array) -> PackedStringArray:
	var lines := PackedStringArray()
	if document == null or notes.is_empty():
		return lines
	var any_countersunk := false
	for note in notes:
		any_countersunk = any_countersunk or int(note["countersunk"]) > 0
	lines.append_array(_sheet_header_lines(document, notes, false))
	lines.remove_at(1)  # The DXF layer line means nothing on paper.
	for note in notes:
		lines.append(str(note["text"]))
	lines.append("Legend: black hairline = cut." + (
		" Dashed blue ring = countersink this hole 90 deg after cutting." if any_countersunk else ""))
	return lines


static func _notes_block(lines: PackedStringArray, origin: Vector2, base_span: Vector2) -> String:
	if lines.is_empty():
		return ""
	var out := PackedStringArray()
	out.append('<g id="notes" font-family="sans-serif" font-size="3.2" fill="#000000" stroke="none">')
	var y := origin.y + base_span.y + SVG_NOTE_LINE_MM * 0.6
	for line in lines:
		out.append('<text x="%.3f" y="%.3f">%s</text>' % [origin.x + 3.0, y, _escaped(line)])
		y += SVG_NOTE_LINE_MM
	out.append('</g>')
	return "\n".join(out)


## Each plate's number at its bounding-box centre, so the notes block's "Plate 3" is findable.
static func _plate_numbers(placed: Array, notes: Array) -> String:
	var out := PackedStringArray()
	out.append('<g id="plate-numbers" font-family="sans-serif" font-size="4" fill="#777777" ' +
		'stroke="none" text-anchor="middle">')
	for entry in placed:
		var note := _note_for(notes, entry["plate"])
		if note.is_empty():
			continue
		var box := _points_bounds(AirframeDocument.plate_outline(entry["plate"]))
		var centre: Vector2 = (box[0] + box[1]) * 0.5 + (entry["offset"] as Vector2)
		out.append('<text x="%.3f" y="%.3f">%d</text>' % [centre.x, centre.y,
			int(note["index"]) + 1])
	out.append('</g>')
	return "\n".join(out)


## A dashed ring round every countersunk hole — `<circle>`, never `<path>`, so it is not a contour.
static func _countersink_marks(placed: Array) -> String:
	var out := PackedStringArray()
	out.append('<g id="countersinks" fill="none" stroke="%s" stroke-width="0.25" ' % COUNTERSINK_COLOUR
		+ 'stroke-dasharray="0.8 0.6">')
	var count := 0
	for entry in placed:
		var plate: Dictionary = entry["plate"]
		var holes := AirframeDocument.plate_holes(plate)
		for hole_index in holes.size():
			if not AirframeDocument.hole_is_countersunk(plate, hole_index):
				continue
			var hole: PackedVector2Array = holes[hole_index]
			var centre := PolygonProps.centroid(hole) + (entry["offset"] as Vector2)
			var radius := sqrt(absf(PolygonProps.area(hole)) / PI)
			out.append('<circle cx="%.3f" cy="%.3f" r="%.3f"/>' % [centre.x, centre.y,
				radius * COUNTERSINK_MARK_RATIO])
			count += 1
	out.append('</g>')
	return "\n".join(out) if count > 0 else ""


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
##
## One solid PER PLATE, holes cut through, at its assembly height: the drawing of the aircraft, where
## arms that share a layer with the bottom plate still overlap it. `PrintedParts` reads this per plate
## and relies on the per-plate count. What goes to a printer is `write_parts`, which merges a layer.
static func to_stl(document: AirframeDocument) -> String:
	var out := PackedStringArray()
	out.append("solid %s" % document.name.replace(" ", "_"))
	for part in printable_parts(document, false):
		for triangle in part_triangles(part, float(part["z_mm"])):
			_facet(out, triangle[0], triangle[1], triangle[2])
	out.append("endsolid")
	return "\n".join(out) + "\n"


# ---------------------------------------------------------------------------
# Printable parts — what comes off a printer bed, one closed solid each
# ---------------------------------------------------------------------------

## The parts a printer makes, one closed solid each, holes cut through.
##
## ## Why a plate is not always a part
##
## The document's arms start at the centre and the bottom plate sits at the same height and
## thickness as them, because "on a bolted frame the arm and the bottom plate ARE the same layer of
## the sandwich, and on a unibody the arms are that plate" (AirframeDocument). For a cutter that is
## harmless — each outline is its own contour. For a printer it is not: four arms that each reach
## the centre, emitted as four solids, are four bodies occupying the same space, and opposite arms
## share their root corners, which a slicer reads as edges with four faces. Printed as drawn they
## cannot even be assembled. So FLAT PLATES OF ONE LAYER — same height, same thickness, same
## material — THAT OVERLAP are merged into one part (the unibody), and every hole of every member is
## cut through it: a stack hole lies under an arm's root, and a hole only one member carries is
## still a hole in the part that gets printed.
##
## Upright plates (G5) are one part each, laid flat where `_upright_laid_flat` puts them; pads are
## one part each. Each entry: `{"name", "plates" (indices into document.plates, empty for a pad),
## "outlines" (Array of counter-clockwise PackedVector2Array), "holes" (Array of clockwise
## PackedVector2Array), "thickness_mm", "z_mm" (assembly height; 0 for an upright), "upright"}`.
##
## `merge_layers` false keeps every flat plate its own part — the assembly drawing's form (`to_stl`).
static func printable_parts(document: AirframeDocument, merge_layers: bool = true) -> Array:
	var parts: Array = []
	if document == null:
		return parts
	for list in PlateLayers.flat_groups(document, merge_layers):
		var index := int(list[0])
		if not PlateLayers.solid_plate(document.plates[index]):
			continue
		var plates: Array = []
		for member in list:
			plates.append(document.plates[member])
		var region := PlateLayers.region_of(plates)
		var first: Dictionary = document.plates[index]
		parts.append({
			"name": PlateLayers.name_of(plates),
			"plates": list.duplicate(),
			"outlines": region["outlines"],
			"holes": region["holes"],
			"thickness_mm": AirframeDocument.plate_thickness_mm(first),
			"z_mm": AirframeDocument.plate_z_mm(first),
			"upright": false,
		})

	for pad in document.pads:
		if not PlateLayers.solid_plate(pad):
			continue
		var region := PlateLayers.region_of([pad])
		parts.append({"name": "pad", "plates": [], "outlines": region["outlines"],
			"holes": region["holes"], "thickness_mm": AirframeDocument.plate_thickness_mm(pad),
			"z_mm": AirframeDocument.plate_z_mm(pad), "upright": false})

	for entry in _upright_laid_flat(document):
		var plate: Dictionary = entry["plate"]
		if not PlateLayers.solid_plate(plate):
			continue
		var offset: Vector2 = entry["offset"]
		var moved := plate.duplicate()
		moved["outline"] = AirframeDocument.flatten(_shifted(AirframeDocument.plate_outline(plate),
			offset))
		var holes: Array = []
		for hole in AirframeDocument.plate_holes(plate):
			holes.append(AirframeDocument.flatten(_shifted(hole, offset)))
		moved["holes"] = holes
		var region := PlateLayers.region_of([moved])
		parts.append({"name": "side", "plates": [document.plates.find(plate)],
			"outlines": region["outlines"], "holes": region["holes"],
			"thickness_mm": AirframeDocument.plate_thickness_mm(plate), "z_mm": 0.0,
			"upright": true})
	return parts


## One part as triangles (`StlWriter`'s form: an Array of 3-point PackedVector3Array), its
## underside at `z0_mm`. Outward-wound: caps by an explicit orientation test, walls by the outline
## being counter-clockwise and every hole clockwise, which `printable_parts` guarantees. Empty when
## a cap cannot be triangulated — `StlWriter.write` then refuses the part rather than writing it.
static func part_triangles(part: Dictionary, z0_mm: float = 0.0) -> Array:
	var out: Array = []
	var thickness := float(part.get("thickness_mm", 0.0))
	if thickness <= 0.0:
		return out
	var z1 := z0_mm + thickness
	var holes: Array = part.get("holes", [])
	for outline in part.get("outlines", []):
		var mine: Array = []
		for hole in holes:
			if Geometry2D.is_point_in_polygon((hole as PackedVector2Array)[0], outline):
				mine.append(hole)
		var cap := cap_triangles(outline, mine)
		if cap.is_empty():
			return []
		var index := 0
		while index + 2 < cap.size():
			var a := cap[index]
			var b := cap[index + 1]
			var c := cap[index + 2]
			out.append(PackedVector3Array([Vector3(a.x, a.y, z1), Vector3(b.x, b.y, z1),
				Vector3(c.x, c.y, z1)]))
			out.append(PackedVector3Array([Vector3(c.x, c.y, z0_mm), Vector3(b.x, b.y, z0_mm),
				Vector3(a.x, a.y, z0_mm)]))
			index += 3
		for loop in [outline] + mine:
			var points: PackedVector2Array = loop
			for vertex in points.size():
				var p0 := points[vertex]
				var p1 := points[(vertex + 1) % points.size()]
				out.append(PackedVector3Array([Vector3(p0.x, p0.y, z0_mm), Vector3(p1.x, p1.y, z0_mm),
					Vector3(p1.x, p1.y, z1)]))
				out.append(PackedVector3Array([Vector3(p0.x, p0.y, z0_mm), Vector3(p1.x, p1.y, z1),
					Vector3(p0.x, p0.y, z1)]))
	return out


## One part as an ASCII STL, LAID ON THE BED: underside at z = 0, which is how it is printed.
static func part_to_stl(part: Dictionary, solid_name: String) -> String:
	return StlWriter.to_ascii(solid_name, part_triangles(part, 0.0))


## Every printable part to its own STL in `directory`, `<base>-part-NN-<name>.stl`, each through
## `StlWriter.write` — so a part that is not a closed, outward-wound solid is REFUSED with a reason
## instead of written. Returns `[{path, name, ok, reason, volume_mm3}]`.
static func write_parts(document: AirframeDocument, directory: String, base_name: String) -> Array:
	var results: Array = []
	DirAccess.make_dir_recursive_absolute(directory)
	var number := 0
	for part in printable_parts(document):
		number += 1
		var label := "%s-part-%02d-%s" % [base_name, number, str(part["name"])]
		var path := directory.path_join(label + ".stl")
		var written := StlWriter.write(label, part_triangles(part, 0.0), path)
		results.append({"path": path, "name": str(part["name"]), "ok": bool(written["ok"]),
			"reason": str(written["reason"]), "volume_mm3": float(written["volume_mm3"])})
	return results


## A cap — the face of a plate with holes — as a flat list of counter-clockwise triangles, three
## points each. Holes are joined to the outline by a zero-width bridge (a "keyhole") so the
## outline-only triangulator `PlateMesh` uses can cut them; the bridge's two copies of each edge
## land in two triangles wound opposite ways, so they are interior edges and the solid stays
## closed. Checked by AREA, which is the property that matters: the triangles must cover exactly the
## outline minus its holes, and empty is returned when they do not.
static func cap_triangles(outline: PackedVector2Array, holes: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var polygon := keyhole(outline, holes)
	if polygon.is_empty():
		return out
	var indices := Geometry2D.triangulate_polygon(polygon)
	var triangles: Array = []
	var tri := 0
	while tri + 2 < indices.size():
		var a := polygon[indices[tri]]
		var b := polygon[indices[tri + 1]]
		var c := polygon[indices[tri + 2]]
		if (b - a).cross(c - a) < -2.0 * StlWriter.MIN_TRIANGLE_AREA_MM2:
			triangles.append([a, c, b])
		else:
			triangles.append([a, b, c])
		tri += 3
	if not _split_slivers(triangles):
		return out
	var covered := 0.0
	for triangle in triangles:
		var a: Vector2 = triangle[0]
		var b: Vector2 = triangle[1]
		var c: Vector2 = triangle[2]
		out.append(a)
		out.append(b)
		out.append(c)
		covered += (b - a).cross(c - a) * 0.5
	var expected := absf(PolygonProps.area(outline))
	for hole in holes:
		expected -= absf(PolygonProps.area(hole))
	if out.is_empty() or absf(covered - expected) > maxf(1.0e-6, expected * 1.0e-6):
		return PackedVector2Array()
	return out


## The outline with every hole joined to it by a zero-width bridge: one counter-clockwise loop an
## outline-only triangulator can fill. Empty when a hole has no clear line to the outline.
static func keyhole(outline: PackedVector2Array, holes: Array) -> PackedVector2Array:
	var polygon := _ccw(outline)
	var ordered: Array = []
	for hole in holes:
		ordered.append(_cw(hole))
	# Rightmost hole first, so every bridge reaches outward over holes not yet joined.
	ordered.sort_custom(func(a: PackedVector2Array, b: PackedVector2Array) -> bool:
		return _max_x(a) > _max_x(b))
	for index in ordered.size():
		var remaining: Array = ordered.slice(index + 1)
		polygon = _bridged(polygon, ordered[index], remaining, outline, ordered)
		if polygon.is_empty():
			return polygon
	return polygon


## Removes zero-area triangles without opening the surface. The triangulator can return a "triangle"
## whose three corners lie on one line — collinear points of two different holes, joined through a
## bridge, do it — and dropping it would leave its two short edges with no cap on that side. Instead
## the sliver (u, w, b), with b between u and w, is folded into the triangle across its long edge
## (w, u, d): that one is split at b into (w, b, d) and (b, u, d), which covers the same area and
## meets every neighbour the two old triangles met. False when a sliver has no neighbour to fold
## into, or the folding does not finish — the caller then refuses the cap.
static func _split_slivers(triangles: Array) -> bool:
	var guard := triangles.size() * 4 + 8
	while guard > 0:
		guard -= 1
		var sliver := -1
		for index in triangles.size():
			var candidate: Array = triangles[index]
			var p0: Vector2 = candidate[0]
			if absf(((candidate[1] as Vector2) - p0).cross((candidate[2] as Vector2) - p0)) * 0.5 \
					< StlWriter.MIN_TRIANGLE_AREA_MM2:
				sliver = index
				break
		if sliver < 0:
			return true
		var t: Array = triangles[sliver]
		# The long edge u→w, in the sliver's own order; b is the corner between its ends.
		var longest := 0
		for k in 3:
			if (t[(k + 1) % 3] as Vector2).distance_squared_to(t[k]) \
					> (t[(longest + 1) % 3] as Vector2).distance_squared_to(t[longest]):
				longest = k
		var u: Vector2 = t[longest]
		var w: Vector2 = t[(longest + 1) % 3]
		var b: Vector2 = t[(longest + 2) % 3]
		var across := -1
		var d := Vector2.ZERO
		for index in triangles.size():
			if index == sliver:
				continue
			var n: Array = triangles[index]
			for k in 3:
				if n[k] == w and n[(k + 1) % 3] == u:
					across = index
					d = n[(k + 2) % 3]
			if across >= 0:
				break
		if across < 0:
			return false
		var keep: Array = []
		for index in triangles.size():
			if index != sliver and index != across:
				keep.append(triangles[index])
		keep.append([w, b, d])
		keep.append([b, u, d])
		triangles.assign(keep)
	return false


static func _bridged(polygon: PackedVector2Array, hole: PackedVector2Array, remaining: Array,
		outline: PackedVector2Array, all_holes: Array) -> PackedVector2Array:
	var start := 0
	for index in hole.size():
		if hole[index].x > hole[start].x:
			start = index
	var from := hole[start]
	var order: Array = []
	for index in polygon.size():
		order.append(index)
	order.sort_custom(func(a: int, b: int) -> bool:
		return polygon[a].distance_squared_to(from) < polygon[b].distance_squared_to(from))
	for index in order:
		var to := polygon[index]
		# A vertex already used by an earlier bridge appears twice; which copy the new bridge
		# belongs to depends on the wedge, so such vertices are simply not candidates.
		if polygon.count(to) > 1:
			continue
		if not _bridge_clear(from, to, [polygon, hole] + remaining):
			continue
		var middle := (from + to) * 0.5
		if not Geometry2D.is_point_in_polygon(middle, outline):
			continue
		var inside_hole := false
		for other in all_holes:
			if Geometry2D.is_point_in_polygon(middle, other):
				inside_hole = true
				break
		if inside_hole:
			continue
		var out := PackedVector2Array()
		for i in index + 1:
			out.append(polygon[i])
		for step in hole.size() + 1:
			out.append(hole[(start + step) % hole.size()])
		out.append(to)
		for i in range(index + 1, polygon.size()):
			out.append(polygon[i])
		return out
	return PackedVector2Array()


static func _bridge_clear(from: Vector2, to: Vector2, loops: Array) -> bool:
	for loop in loops:
		var points: PackedVector2Array = loop
		for index in points.size():
			var a := points[index]
			var b := points[(index + 1) % points.size()]
			if a == from or a == to or b == from or b == to:
				continue
			if Geometry2D.segment_intersects_segment(from, to, a, b) != null:
				return false
	return true


static func _ccw(points: PackedVector2Array) -> PackedVector2Array:
	return PlateLayers.ccw(points)


static func _cw(points: PackedVector2Array) -> PackedVector2Array:
	return PlateLayers.cw(points)


static func _max_x(points: PackedVector2Array) -> float:
	var best := -INF
	for point in points:
		best = maxf(best, point.x)
	return best


static func _shifted(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points:
		out.append(point + offset)
	return out


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
		"html": text = BuildSheet.to_html(document)
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
			if not AirframeDocument.is_upright(plate):
				out.append({"plate": plate, "offset": Vector2.ZERO})
		out.append_array(_upright_laid_flat(document))
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


## Upright plates (G5), LAID FLAT beside the rest: a side plate's outline is already its cut shape in
## its own plane, so on a sheet it goes down as drawn — but in an assembly drawing its own (s, h)
## coordinates would land on top of the plan view, so it is set out in a row to the right of the flat
## plates, `NEST_GAP_MM` apart. The STL uses the same places, at z = 0, so a slicer or CAM import sees
## every part flat and none inside another.
static func _upright_laid_flat(document: AirframeDocument) -> Array:
	var out: Array = []
	var flat_high := -INF
	var flat_low_y := INF
	for plate in document.plates:
		if AirframeDocument.is_upright(plate):
			continue
		for point in AirframeDocument.plate_outline(plate):
			flat_high = maxf(flat_high, point.x)
			flat_low_y = minf(flat_low_y, point.y)
	for pad in document.pads:
		for point in AirframeDocument.plate_outline(pad):
			flat_high = maxf(flat_high, point.x)
			flat_low_y = minf(flat_low_y, point.y)
	var cursor := Vector2(flat_high + NEST_GAP_MM if is_finite(flat_high) else 0.0,
		flat_low_y if is_finite(flat_low_y) else 0.0)
	for plate in document.plates:
		if not AirframeDocument.is_upright(plate):
			continue
		var points := AirframeDocument.plate_outline(plate)
		if points.size() < 3:
			continue
		var box := _points_bounds(points)
		out.append({"plate": plate, "offset": cursor - (box[0] as Vector2)})
		cursor.x += ((box[1] as Vector2) - (box[0] as Vector2)).x + NEST_GAP_MM
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
