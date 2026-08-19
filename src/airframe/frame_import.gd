class_name FrameImport
extends RefCounted
## Getting an outline INTO Lothal: an SVG a builder drew in Illustrator or Inkscape, or a DXF that
## came off a cutting service, read back as plates this room can weigh, measure and cut again.
##
## ## Why this is the other half of FrameExport
##
## `FrameExport`'s header says a frame you cannot cut is a drawing. The converse is what this file
## is for: an outline somebody already drew is, to Lothal, only a picture — it has no mass, no
## inertia, no first mode, and no warning about a bolt hole 2 mm from an edge. Import is what turns
## that picture into geometry the physics integrates, and from that moment every number in the room
## is about the part the builder actually intends to cut rather than about a stand-in they redrew
## by hand from it.
##
## It is deliberately the exact inverse of the export path: what `to_svg` writes, `from_svg` reads
## back, and `tests/test_frame_import.gd` asserts the round trip lands within a twentieth of a
## millimetre. That is the one property that makes this file trustworthy without a corpus of
## third-party files to test against — the writer and the reader agree, in mm, on Lothal's own
## output, and every other file is read by the same code path.
##
## ## Units, which are the whole risk
##
## Everything else here is polygon arithmetic that either works or visibly does not. The unit
## decision is the one that fails SILENTLY: an outline read at the wrong scale looks completely
## normal on a canvas that fits it to the window, and comes out of the cutter 33% too big.
##
## So the scale is derived, never assumed, and the assumption that remains is SAID OUT LOUD:
##
##   - SVG with a real `width`/`height` in mm/cm/in and a `viewBox` — the form `to_svg` writes —
##     scales user units to mm exactly. Nothing is assumed.
##   - SVG in `px`, or with no units at all, is read at 96 dpi (the CSS reference pixel, which is
##     what every drawing program means by an unqualified number today) and `note` comes back
##     saying so, with the resulting span in mm. The caller is expected to show it: a builder who
##     sees "span 118.4 mm" knows within a second whether the file was read right.
##   - DXF is unitless by convention and every tool that reads one for this kind of part assumes
##     millimetres — the same assumption `to_dxf` makes when it writes one. Numbers go in unchanged.
##
## ## What is deliberately NOT read
##
##   - **SVG `<text>`, strokes, styles, fills.** A cut file is geometry; a label is not a part.
##   - **DXF `SPLINE`.** A file containing one is REFUSED with a sentence naming the problem,
##     rather than imported with the spline edges quietly missing. A plate short one edge still
##     closes into a plausible polygon — it draws fine, weighs almost right, and is wrong in a way
##     nobody catches until it is cut. Refusing is the only honest option, and "re-export with
##     splines converted to polylines" is a thing every CAD program does in one checkbox.
##   - **Arm centrelines.** An imported outline is never `ROLE_ARM`. `ArmProfile` measures a beam
##     along an authored root→tip axis, and no SVG says which end of a shape is bolted to the
##     middle of an aircraft. An imported plate can be turned into an arm by the builder, who
##     knows; guessing would put a stiffness figure on screen that was derived from a direction
##     this file invented.

## Chord tolerance for every curve flattened here, mm. Half the 0.2 mm cut stroke `FrameExport`
## draws with, so the flattening error is finer than the line the cutter follows — the error is
## inside the kerf rather than added to it.
const CHORD_TOLERANCE_MM := 0.1

## The CSS reference pixel. 25.4/96 mm per px, used only where the file declines to say.
const MM_PER_PX := 25.4 / 96.0

## How near two endpoints must be to be the same point when chaining loose DXF segments into a
## loop, mm. A cutter's own tolerance is an order finer than this; a CAD export that lands its
## endpoints further apart than 0.05 mm has an actual gap in it.
const JOIN_TOLERANCE_MM := 0.05

## Under this many square millimetres a closed loop is treated as noise rather than as a part: a
## stray click in a drawing program, or a degenerate hole. 0.25 mm² is a half-millimetre square,
## which is smaller than any real feature on a frame.
const MIN_LOOP_AREA_MM2 := 0.25


# ---------------------------------------------------------------------------
# The public door
# ---------------------------------------------------------------------------

## Reads a file. Returns `{"loops": Array[PackedVector2Array], "note": String, "error": String}`.
##
## A non-empty `error` means NOTHING was read and the caller must not touch the document — every
## failure below is atomic for that reason. A half-imported frame is worse than a refused one,
## because it is a frame the builder will keep editing.
static func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("There is no file at %s." % path)
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return _failure("%s is empty." % path.get_file())
	match path.get_extension().to_lower():
		"svg": return from_svg(text)
		"dxf": return from_dxf(text)
	return _failure("Lothal reads SVG and DXF outlines; %s is neither." % path.get_file())


## The loops of a file as plates, ready to append to a document.
##
## Nesting is resolved here and nowhere else: a loop that lies inside another is that plate's HOLE,
## and it is emitted with the negative-area winding `PolygonProps` subtracts with. Get this wrong
## and a frame's bolt holes add mass instead of removing it, which is a mistake no picture shows.
##
## Depth is counted, not assumed to be one level: a loop inside a hole is an island — a real thing
## in a cut part — and comes back as its own plate. Odd depth is a hole, even depth is a plate.
static func plates_from_loops(
	loops: Array,
	thickness_mm: float = FrameEdits.DEFAULT_PLATE_THICKNESS_MM,
	z_mm: float = 0.0,
	role: String = AirframeDocument.ROLE_BOTTOM
) -> Array:
	var kept: Array = []
	for loop in loops:
		var points: PackedVector2Array = loop
		if points.size() >= 3 and absf(PolygonProps.area(points)) >= MIN_LOOP_AREA_MM2:
			kept.append(points)

	var depths: Array = []
	for index in kept.size():
		depths.append(_containment_depth(kept, index))

	# Outer loops first, so a hole always finds its plate already appended.
	var plates: Array = []
	var plate_of_loop := {}
	for index in kept.size():
		if int(depths[index]) % 2 != 0:
			continue
		plate_of_loop[index] = plates.size()
		plates.append(AirframeDocument.make_plate(
			_wound(kept[index], true), [], absf(thickness_mm), z_mm, role))

	for index in kept.size():
		if int(depths[index]) % 2 == 0:
			continue
		var parent := _closest_container(kept, index)
		if parent < 0 or not plate_of_loop.has(parent):
			continue
		var plate: Dictionary = plates[int(plate_of_loop[parent])]
		var holes: Array = plate.get("holes", [])
		holes.append(AirframeDocument.flatten(_wound(kept[index], false)))
		plate["holes"] = holes

	return plates


## Appends a file's plates to a document, centred on the document's origin.
##
## CENTRED, not left where the file put them. An SVG's coordinates are wherever the drawing program's
## artboard happened to be — commonly a corner hundreds of millimetres away, and on an A4 artboard
## always at least 100 mm off. Dropped at their file position, imported plates land outside the view
## of a canvas framed on the existing frame, and the import reads as having done nothing at all.
##
## Returns `{"first_index": int, "count": int, "span_mm": Vector2}`; `count` is zero when the file
## held no closed loop big enough to be a part.
static func into_document(
	document: AirframeDocument,
	loops: Array,
	thickness_mm: float = FrameEdits.DEFAULT_PLATE_THICKNESS_MM
) -> Dictionary:
	var empty := {"first_index": -1, "count": 0, "span_mm": Vector2.ZERO}
	if document == null:
		return empty
	var plates := plates_from_loops(loops, thickness_mm)
	if plates.is_empty():
		return empty

	var lowest := Vector2(INF, INF)
	var highest := Vector2(-INF, -INF)
	for plate in plates:
		for point in AirframeDocument.plate_outline(plate):
			lowest = lowest.min(point)
			highest = highest.max(point)
	var shift := -(lowest + highest) * 0.5

	var first := document.plates.size()
	for plate in plates:
		document.plates.append(_shifted_plate(plate, shift))
	return {
		"first_index": first,
		"count": plates.size(),
		"span_mm": highest - lowest,
	}


# ---------------------------------------------------------------------------
# SVG
# ---------------------------------------------------------------------------

## Every closed loop in an SVG, in millimetres.
##
## Read with `XMLParser` rather than a regular expression over the text: an SVG's geometry is
## nested inside `<g>` elements that each carry a transform, and a scanner that finds `d="..."`
## strings without their ancestry reads every group's contents at the wrong place. The transform
## stack below is the whole reason this is a parse and not a search.
static func from_svg(text: String) -> Dictionary:
	var parser := XMLParser.new()
	if parser.open_buffer(text.to_utf8_buffer()) != OK:
		return _failure("That SVG could not be read as XML.")

	var loops: Array = []
	var note := ""
	var scale := Transform2D.IDENTITY
	var found_root := false
	var stack: Array[Transform2D] = [Transform2D.IDENTITY]

	while parser.read() == OK:
		var type := parser.get_node_type()
		if type == XMLParser.NODE_ELEMENT_END:
			if stack.size() > 1:
				stack.pop_back()
			continue
		if type != XMLParser.NODE_ELEMENT:
			continue

		var name := parser.get_node_name().to_lower()
		var attributes := _attributes(parser)
		var self_closing := parser.is_empty()

		if name == "svg" and not found_root:
			found_root = true
			var unit := _svg_unit_scale(attributes)
			scale = unit["transform"]
			note = str(unit["note"])
			stack[0] = scale
			continue

		var here: Transform2D = (stack[stack.size() - 1] as Transform2D) \
			* _transform_of(str(attributes.get("transform", "")))
		if not self_closing and (name == "g" or name == "svg" or name == "a"):
			stack.append(here)
			continue

		for loop in _svg_element_loops(name, attributes):
			var moved := PackedVector2Array()
			for point in loop:
				moved.append(here * point)
			loops.append(moved)

		if not self_closing:
			stack.append(here)

	if not found_root:
		return _failure("That file has no <svg> element.")
	if loops.is_empty():
		return _failure("That SVG has no closed outline in it — only open lines, text or images.")

	var span := _span_of(loops)
	if note != "":
		note = "%s Span reads %.1f × %.1f mm." % [note, span.x, span.y]
	return {"loops": loops, "note": note, "error": ""}


## What the root element says one user unit is worth, in mm, as a scale transform plus the sentence
## the caller should show when the file did not actually say.
##
## THERE IS NO Y FLIP, and that is a decision rather than an omission. SVG's Y runs down the page,
## and so does the document's `v` — `PlanTransform`'s header fixes `+v` as DOWN so a frame draws
## nose-up the way every product photo shows it. The two conventions already agree, so a shape
## arrives the way round it was drawn, and Lothal's own SVG round-trips through this file unchanged.
## A flip inserted "for correctness" here would mirror every import, which is invisible on the
## symmetric plates that are most of them and wrong-handed on the ones that are not.
static func _svg_unit_scale(attributes: Dictionary) -> Dictionary:
	var view_box := _floats(str(attributes.get("viewbox", "")))
	var width := _length_mm(str(attributes.get("width", "")))
	var height := _length_mm(str(attributes.get("height", "")))

	var scale := Vector2.ONE * MM_PER_PX
	var note := "Read at 96 dpi — that file states no real-world size."
	if view_box.size() == 4 and float(view_box[2]) > 0.0 and float(view_box[3]) > 0.0:
		if float(width["mm"]) > 0.0 and float(height["mm"]) > 0.0:
			scale = Vector2(float(width["mm"]) / float(view_box[2]),
				float(height["mm"]) / float(view_box[3]))
			note = "" if bool(width["explicit"]) else \
				"Read at 96 dpi — that file's size is in pixels."
		else:
			scale = Vector2.ONE * MM_PER_PX
	elif float(width["mm"]) > 0.0 and bool(width["explicit"]):
		# Real-world width, no viewBox: user units ARE the stated unit, so the numbers are already
		# in that unit and only the unit's size matters.
		scale = Vector2.ONE * (float(width["mm"]) / maxf(float(width["value"]), 1.0e-9))
		note = ""

	# The viewBox origin is subtracted before scaling, so a file whose artboard starts at
	# (-150, -150) lands where it was drawn rather than 150 mm away in both axes.
	var origin := Vector2.ZERO
	if view_box.size() == 4:
		origin = Vector2(float(view_box[0]), float(view_box[1]))
	var transform := Transform2D(0.0, scale, 0.0, -origin * scale)
	return {"transform": transform, "note": note}


## A length with its unit — `{"mm": float, "value": float, "explicit": bool}`. `explicit` is false
## for a bare number or `px`, which is exactly the case the caller must warn about.
static func _length_mm(text: String) -> Dictionary:
	var trimmed := text.strip_edges().to_lower()
	if trimmed.is_empty():
		return {"mm": 0.0, "value": 0.0, "explicit": false}
	var digits := ""
	for index in trimmed.length():
		var character := trimmed[index]
		if character.is_valid_int() or character == "." or character == "-" or character == "+" \
				or character == "e":
			digits += character
		else:
			break
	if digits.is_empty():
		return {"mm": 0.0, "value": 0.0, "explicit": false}
	var value := float(digits)
	var unit := trimmed.substr(digits.length()).strip_edges()
	match unit:
		"mm": return {"mm": value, "value": value, "explicit": true}
		"cm": return {"mm": value * 10.0, "value": value, "explicit": true}
		"m": return {"mm": value * 1000.0, "value": value, "explicit": true}
		"in": return {"mm": value * 25.4, "value": value, "explicit": true}
		"pt": return {"mm": value * 25.4 / 72.0, "value": value, "explicit": true}
		"pc": return {"mm": value * 25.4 / 6.0, "value": value, "explicit": true}
	return {"mm": value * MM_PER_PX, "value": value, "explicit": false}


## The loops one geometry element contributes, in its own user units.
static func _svg_element_loops(name: String, attributes: Dictionary) -> Array:
	match name:
		"path":
			return _svg_path_loops(str(attributes.get("d", "")))
		"polygon", "polyline":
			var points := _point_list(str(attributes.get("points", "")))
			return [points] if points.size() >= 3 else []
		"rect":
			var x := float(attributes.get("x", "0"))
			var y := float(attributes.get("y", "0"))
			var w := float(attributes.get("width", "0"))
			var h := float(attributes.get("height", "0"))
			if w <= 0.0 or h <= 0.0:
				return []
			return [PackedVector2Array([Vector2(x, y), Vector2(x + w, y),
				Vector2(x + w, y + h), Vector2(x, y + h)])]
		"circle":
			var r := float(attributes.get("r", "0"))
			if r <= 0.0:
				return []
			return [PolygonProps.tessellate_circle(
				Vector2(float(attributes.get("cx", "0")), float(attributes.get("cy", "0"))),
				r, CHORD_TOLERANCE_MM)]
		"ellipse":
			var rx := float(attributes.get("rx", "0"))
			var ry := float(attributes.get("ry", "0"))
			if rx <= 0.0 or ry <= 0.0:
				return []
			var centre := Vector2(float(attributes.get("cx", "0")),
				float(attributes.get("cy", "0")))
			var unit_circle := PolygonProps.tessellate_circle(
				Vector2.ZERO, maxf(rx, ry), CHORD_TOLERANCE_MM)
			var out := PackedVector2Array()
			for point in unit_circle:
				out.append(centre + Vector2(point.x / maxf(rx, ry) * rx,
					point.y / maxf(rx, ry) * ry))
			return [out]
	return []


## The closed subpaths of one `d` attribute.
##
## An unclosed subpath of three or more points is CLOSED rather than dropped. A drawing program
## that omits the final `Z` on a shape whose ends coincide is common enough to be the normal case,
## and the alternative — silently discarding the plate — is a frame with a part missing.
static func _svg_path_loops(d: String) -> Array:
	var tokens := _path_tokens(d)
	var loops: Array = []
	var current := PackedVector2Array()
	var cursor := Vector2.ZERO
	var start := Vector2.ZERO
	var last_control := Vector2.ZERO
	var command := ""
	var index := 0

	while index < tokens.size():
		var token: String = tokens[index]
		if not _is_number(token):
			command = token
			index += 1
			if command.to_upper() == "Z":
				if current.size() >= 3:
					loops.append(current)
				current = PackedVector2Array()
				cursor = start
				continue
			continue
		if command.is_empty():
			index += 1
			continue

		var relative := command == command.to_lower()
		var base := cursor if relative else Vector2.ZERO
		match command.to_upper():
			"M":
				if current.size() >= 3:
					loops.append(current)
				current = PackedVector2Array()
				cursor = base + Vector2(float(tokens[index]), float(tokens[index + 1]))
				start = cursor
				current.append(cursor)
				index += 2
				# Every coordinate pair after a moveto is an implicit lineto.
				command = "l" if relative else "L"
			"L":
				cursor = base + Vector2(float(tokens[index]), float(tokens[index + 1]))
				current.append(cursor)
				index += 2
			"H":
				cursor = Vector2((cursor.x if relative else 0.0) + float(tokens[index]), cursor.y)
				current.append(cursor)
				index += 1
			"V":
				cursor = Vector2(cursor.x, (cursor.y if relative else 0.0) + float(tokens[index]))
				current.append(cursor)
				index += 1
			"C", "S":
				var c1: Vector2
				var c2: Vector2
				if command.to_upper() == "C":
					c1 = base + Vector2(float(tokens[index]), float(tokens[index + 1]))
					c2 = base + Vector2(float(tokens[index + 2]), float(tokens[index + 3]))
					cursor = base + Vector2(float(tokens[index + 4]), float(tokens[index + 5]))
					index += 6
				else:
					c1 = cursor * 2.0 - last_control
					c2 = base + Vector2(float(tokens[index]), float(tokens[index + 1]))
					cursor = base + Vector2(float(tokens[index + 2]), float(tokens[index + 3]))
					index += 4
				_append_cubic(current, current[current.size() - 1], c1, c2, cursor)
				last_control = c2
			"Q", "T":
				var control: Vector2
				if command.to_upper() == "Q":
					control = base + Vector2(float(tokens[index]), float(tokens[index + 1]))
					cursor = base + Vector2(float(tokens[index + 2]), float(tokens[index + 3]))
					index += 4
				else:
					control = cursor * 2.0 - last_control
					cursor = base + Vector2(float(tokens[index]), float(tokens[index + 1]))
					index += 2
				var from: Vector2 = current[current.size() - 1]
				# A quadratic IS a cubic with both controls a third of the way in.
				_append_cubic(current, from, from + (control - from) * (2.0 / 3.0),
					cursor + (control - cursor) * (2.0 / 3.0), cursor)
				last_control = control
			"A":
				var radii := Vector2(float(tokens[index]), float(tokens[index + 1]))
				var rotation := deg_to_rad(float(tokens[index + 2]))
				var large := float(tokens[index + 3]) != 0.0
				var sweep := float(tokens[index + 4]) != 0.0
				var to := base + Vector2(float(tokens[index + 5]), float(tokens[index + 6]))
				_append_svg_arc(current, cursor, to, radii, rotation, large, sweep)
				cursor = to
				index += 7
			_:
				index += 1

	if current.size() >= 3:
		loops.append(current)
	return loops


static func _append_cubic(
	out: PackedVector2Array, a: Vector2, c1: Vector2, c2: Vector2, b: Vector2
) -> void:
	# Segment count from the control polygon's length against the chord tolerance: a nearly straight
	# curve gets two segments and a tight one gets many, which is the same sagitta logic
	# `PolygonProps.tessellate_arc` uses expressed for a curve with no single radius.
	var rough := a.distance_to(c1) + c1.distance_to(c2) + c2.distance_to(b)
	var steps := clampi(int(ceil(sqrt(rough / maxf(CHORD_TOLERANCE_MM, 1.0e-6)))), 2, 256)
	for step in range(1, steps + 1):
		var t := float(step) / float(steps)
		var u := 1.0 - t
		out.append(a * (u * u * u) + c1 * (3.0 * u * u * t) + c2 * (3.0 * u * t * t)
			+ b * (t * t * t))


## SVG's endpoint-parameterised arc, converted to a centre and swept.
##
## The conversion is the one in the SVG specification's implementation notes, including the radii
## correction: an arc whose radii are too small to reach its endpoint is legal in a file and is
## drawn by scaling both radii up until it fits. Skipping that step turns such an arc into a NaN,
## and a NaN vertex propagates through every integral in the room as a mass of NaN grams.
static func _append_svg_arc(
	out: PackedVector2Array,
	from: Vector2,
	to: Vector2,
	radii: Vector2,
	rotation: float,
	large_arc: bool,
	sweep: bool
) -> void:
	var rx := absf(radii.x)
	var ry := absf(radii.y)
	if rx <= 0.0 or ry <= 0.0 or from.is_equal_approx(to):
		out.append(to)
		return

	var cos_phi := cos(rotation)
	var sin_phi := sin(rotation)
	var mid := (from - to) * 0.5
	var x1 := cos_phi * mid.x + sin_phi * mid.y
	var y1 := -sin_phi * mid.x + cos_phi * mid.y

	var lambda := (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
	if lambda > 1.0:
		var stretch := sqrt(lambda)
		rx *= stretch
		ry *= stretch

	var numerator := maxf(rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1, 0.0)
	var denominator := rx * rx * y1 * y1 + ry * ry * x1 * x1
	var factor := 0.0 if denominator <= 0.0 else sqrt(numerator / denominator)
	if large_arc == sweep:
		factor = -factor
	var cx1 := factor * rx * y1 / ry
	var cy1 := -factor * ry * x1 / rx
	var centre := Vector2(cos_phi * cx1 - sin_phi * cy1, sin_phi * cx1 + cos_phi * cy1) \
		+ (from + to) * 0.5

	var start := Vector2((x1 - cx1) / rx, (y1 - cy1) / ry).angle()
	var finish := Vector2((-x1 - cx1) / rx, (-y1 - cy1) / ry).angle()
	var delta := finish - start
	if not sweep and delta > 0.0:
		delta -= TAU
	elif sweep and delta < 0.0:
		delta += TAU

	var steps := clampi(int(ceil(absf(delta) / TAU * maxf(
		float(PolygonProps.tessellate_circle(Vector2.ZERO, maxf(rx, ry),
			CHORD_TOLERANCE_MM).size()), 8.0))), 2, 512)
	for step in range(1, steps + 1):
		var angle := start + delta * (float(step) / float(steps))
		var point := Vector2(rx * cos(angle), ry * sin(angle))
		out.append(centre + Vector2(cos_phi * point.x - sin_phi * point.y,
			sin_phi * point.x + cos_phi * point.y))


# ---------------------------------------------------------------------------
# DXF
# ---------------------------------------------------------------------------

## Every closed loop in a DXF, in millimetres.
##
## R12's entity forms are what this reads, because they are what `FrameExport.to_dxf` writes and
## what every cutting service still accepts: `POLYLINE`/`VERTEX`, `LWPOLYLINE`, `LINE`, `CIRCLE`
## and `ARC`. Loose `LINE`s and `ARC`s are chained into loops by their endpoints, which is the form
## most CAD programs export a sketch in.
static func from_dxf(text: String) -> Dictionary:
	var pairs := _dxf_pairs(text)
	if pairs.is_empty():
		return _failure("That DXF has no group codes in it.")

	var loops: Array = []
	var open_segments: Array = []
	var has_spline := false

	var index := 0
	while index < pairs.size():
		var pair: Array = pairs[index]
		if int(pair[0]) != 0:
			index += 1
			continue
		var entity := str(pair[1]).to_upper()
		var body := _dxf_entity_body(pairs, index + 1)
		var end: int = body["end"]
		var fields: Array = body["fields"]
		match entity:
			"SPLINE":
				has_spline = true
			"LWPOLYLINE":
				var polyline := _dxf_lwpolyline(fields)
				if bool(polyline["closed"]):
					loops.append(polyline["points"])
				else:
					open_segments.append(polyline["points"])
			"POLYLINE":
				var gathered := _dxf_polyline(pairs, end)
				end = int(gathered["end"])
				if bool(gathered["closed"]):
					loops.append(gathered["points"])
				else:
					open_segments.append(gathered["points"])
			"LINE":
				var a := Vector2(_field(fields, 10), _field(fields, 20))
				var b := Vector2(_field(fields, 11), _field(fields, 21))
				if not a.is_equal_approx(b):
					open_segments.append(PackedVector2Array([a, b]))
			"CIRCLE":
				var radius := _field(fields, 40)
				if radius > 0.0:
					loops.append(PolygonProps.tessellate_circle(
						Vector2(_field(fields, 10), _field(fields, 20)), radius,
						CHORD_TOLERANCE_MM))
			"ARC":
				var arc_radius := _field(fields, 40)
				var start := deg_to_rad(_field(fields, 50))
				var finish := deg_to_rad(_field(fields, 51))
				var sweep := finish - start
				if sweep <= 0.0:
					sweep += TAU
				if arc_radius > 0.0:
					open_segments.append(PolygonProps.tessellate_arc(
						Vector2(_field(fields, 10), _field(fields, 20)), arc_radius,
						start, sweep, CHORD_TOLERANCE_MM))
		index = maxi(end, index + 1)

	if has_spline:
		# Refused, not partially read. See this file's header: a plate missing one edge closes into
		# a polygon that looks right and is not the part.
		return _failure("That DXF contains SPLINE entities Lothal does not read. " +
			"Re-export it with curves converted to polylines.")

	loops.append_array(_chained_loops(open_segments))
	if loops.is_empty():
		return _failure("That DXF has no closed outline in it.")
	return {"loops": loops, "note": "", "error": ""}


## Every (group code, value) pair in the file, in order. A DXF is nothing but this list, and doing
## the tokenising once means every entity reader below is a loop over an array rather than its own
## line-counting state machine.
static func _dxf_pairs(text: String) -> Array:
	var lines := text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	var out: Array = []
	var index := 0
	while index + 1 < lines.size():
		var code := lines[index].strip_edges()
		if code.is_empty() or not code.is_valid_int():
			index += 1
			continue
		out.append([int(code), lines[index + 1].strip_edges()])
		index += 2
	return out


## The pairs of one entity: everything up to the next `0` group code.
static func _dxf_entity_body(pairs: Array, from: int) -> Dictionary:
	var fields: Array = []
	var index := from
	while index < pairs.size() and int((pairs[index] as Array)[0]) != 0:
		fields.append(pairs[index])
		index += 1
	return {"fields": fields, "end": index}


## The first value of a group code in an entity's fields, as a float.
static func _field(fields: Array, code: int, fallback: float = 0.0) -> float:
	for pair in fields:
		if int((pair as Array)[0]) == code:
			return float(str((pair as Array)[1]))
	return fallback


## An LWPOLYLINE: 10/20 pairs in order, an optional 42 bulge per vertex, 70 bit 1 for closed.
##
## Bulge is read rather than ignored: it is how a DXF says "this edge is an arc", and every
## fillet a builder puts on a plate corner in CAD comes out as one. Dropping it turns a rounded
## corner into a sharp one — a small area error everywhere, and a real error at a bolt hole.
static func _dxf_lwpolyline(fields: Array) -> Dictionary:
	var points := PackedVector2Array()
	var bulges := PackedFloat64Array()
	var closed := false
	var pending_x := 0.0
	var has_x := false
	for pair in fields:
		var code := int((pair as Array)[0])
		var value := str((pair as Array)[1])
		match code:
			70: closed = (int(value) & 1) != 0
			10:
				pending_x = float(value)
				has_x = true
			20:
				if has_x:
					points.append(Vector2(pending_x, float(value)))
					while bulges.size() < points.size() - 1:
						bulges.append(0.0)
					has_x = false
			42:
				while bulges.size() < points.size() - 1:
					bulges.append(0.0)
				if bulges.size() == points.size() - 1:
					bulges.append(float(value))
	while bulges.size() < points.size():
		bulges.append(0.0)
	return {"points": _with_bulges(points, bulges, closed), "closed": closed}


## A POLYLINE's VERTEX entities, up to its SEQEND.
static func _dxf_polyline(pairs: Array, from: int) -> Dictionary:
	var points := PackedVector2Array()
	var bulges := PackedFloat64Array()
	var closed := false
	# The closed flag lives on the POLYLINE header, which is the body just consumed by the caller.
	var index := from
	var header := from - 1
	while header >= 0 and int((pairs[header] as Array)[0]) != 0:
		if int((pairs[header] as Array)[0]) == 70:
			closed = (int(str((pairs[header] as Array)[1])) & 1) != 0
		header -= 1

	while index < pairs.size():
		var pair: Array = pairs[index]
		if int(pair[0]) != 0:
			index += 1
			continue
		var entity := str(pair[1]).to_upper()
		if entity == "SEQEND":
			index += 1
			break
		if entity != "VERTEX":
			break
		var body := _dxf_entity_body(pairs, index + 1)
		var fields: Array = body["fields"]
		points.append(Vector2(_field(fields, 10), _field(fields, 20)))
		bulges.append(_field(fields, 42))
		index = int(body["end"])
	return {"points": _with_bulges(points, bulges, closed), "closed": closed, "end": index}


## A polyline with its bulge arcs expanded. Bulge is tan(sweep/4) — the DXF convention — so the
## sweep and therefore the radius follow from the chord and that one number.
static func _with_bulges(
	points: PackedVector2Array, bulges: PackedFloat64Array, closed: bool
) -> PackedVector2Array:
	var any := false
	for bulge in bulges:
		if absf(bulge) > 1.0e-9:
			any = true
			break
	if not any or points.size() < 2:
		return points

	var out := PackedVector2Array()
	var count := points.size()
	var last := count if closed else count - 1
	for index in last:
		var a := points[index]
		var b := points[(index + 1) % count]
		out.append(a)
		var bulge: float = bulges[index] if index < bulges.size() else 0.0
		if absf(bulge) <= 1.0e-9 or a.is_equal_approx(b):
			continue
		var sweep := 4.0 * atan(bulge)
		var chord := a.distance_to(b)
		var radius := chord / (2.0 * sin(absf(sweep) * 0.5))
		var mid := (a + b) * 0.5
		var normal := (b - a).normalized().orthogonal()
		var height := radius * cos(absf(sweep) * 0.5)
		var centre := mid + normal * (height * signf(sweep))
		var arc := PolygonProps.tessellate_arc(centre, radius,
			(a - centre).angle(), sweep, CHORD_TOLERANCE_MM)
		for step in range(1, arc.size() - 1):
			out.append(arc[step])
	if not closed:
		out.append(points[count - 1])
	return out


## Loose segments joined end to end into closed loops. A run that never closes is dropped: an open
## chain is a sketch line, not a part, and closing it by force invents an edge nobody drew.
static func _chained_loops(segments: Array) -> Array:
	var pool: Array = []
	for segment in segments:
		if (segment as PackedVector2Array).size() >= 2:
			pool.append(segment)

	var loops: Array = []
	while not pool.is_empty():
		var chain: PackedVector2Array = pool.pop_front()
		var extended := true
		while extended:
			extended = false
			var tail: Vector2 = chain[chain.size() - 1]
			if tail.distance_to(chain[0]) <= JOIN_TOLERANCE_MM and chain.size() >= 4:
				break
			for index in pool.size():
				var candidate: PackedVector2Array = pool[index]
				var head: Vector2 = candidate[0]
				var end: Vector2 = candidate[candidate.size() - 1]
				if tail.distance_to(head) <= JOIN_TOLERANCE_MM:
					for step in range(1, candidate.size()):
						chain.append(candidate[step])
				elif tail.distance_to(end) <= JOIN_TOLERANCE_MM:
					for step in range(candidate.size() - 2, -1, -1):
						chain.append(candidate[step])
				else:
					continue
				pool.remove_at(index)
				extended = true
				break
		if chain.size() >= 4 and chain[chain.size() - 1].distance_to(chain[0]) \
				<= JOIN_TOLERANCE_MM:
			chain.remove_at(chain.size() - 1)
			loops.append(chain)
	return loops


# ---------------------------------------------------------------------------
# Shared
# ---------------------------------------------------------------------------

static func _failure(message: String) -> Dictionary:
	return {"loops": [], "note": "", "error": message}


## A loop wound the way its job needs: positive area for an outline, negative for a hole. Both
## `PolygonProps` and every mass integral in the room read the SIGN, so this is not cosmetic —
## see `FrameEdits.add_rectangle`'s note for what a reversed outline weighs.
static func _wound(points: PackedVector2Array, counter_clockwise: bool) -> PackedVector2Array:
	var positive := PolygonProps.area(points) > 0.0
	if positive == counter_clockwise:
		return points
	var out := PackedVector2Array()
	for index in range(points.size() - 1, -1, -1):
		out.append(points[index])
	return out


## How many other loops contain this one. Even means a plate, odd means a hole — which is the rule
## every fill engine uses, and the one that makes an island inside a cut-out come out as a part.
static func _containment_depth(loops: Array, index: int) -> int:
	var depth := 0
	var point: Vector2 = (loops[index] as PackedVector2Array)[0]
	for other in loops.size():
		if other == index:
			continue
		if Geometry2D.is_point_in_polygon(point, loops[other]):
			depth += 1
	return depth


## The smallest loop containing this one — its parent in the nesting.
static func _closest_container(loops: Array, index: int) -> int:
	var best := -1
	var best_area := INF
	var point: Vector2 = (loops[index] as PackedVector2Array)[0]
	for other in loops.size():
		if other == index:
			continue
		if not Geometry2D.is_point_in_polygon(point, loops[other]):
			continue
		var area := absf(PolygonProps.area(loops[other]))
		if area < best_area:
			best_area = area
			best = other
	return best


static func _shifted_plate(plate: Dictionary, shift: Vector2) -> Dictionary:
	var out := plate.duplicate(true)
	out["outline"] = AirframeDocument.flatten(
		_shifted(AirframeDocument.plate_outline(plate), shift))
	var holes: Array = []
	for hole in AirframeDocument.plate_holes(plate):
		holes.append(AirframeDocument.flatten(_shifted(hole, shift)))
	out["holes"] = holes
	return out


static func _shifted(points: PackedVector2Array, shift: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points:
		out.append(point + shift)
	return out


static func _span_of(loops: Array) -> Vector2:
	var lowest := Vector2(INF, INF)
	var highest := Vector2(-INF, -INF)
	for loop in loops:
		for point in loop:
			lowest = lowest.min(point)
			highest = highest.max(point)
	if not is_finite(lowest.x) or not is_finite(highest.x):
		return Vector2.ZERO
	return highest - lowest


static func _attributes(parser: XMLParser) -> Dictionary:
	var out := {}
	for index in parser.get_attribute_count():
		out[parser.get_attribute_name(index).to_lower()] = parser.get_attribute_value(index)
	return out


## An SVG `transform` list, applied left to right as the specification requires.
static func _transform_of(text: String) -> Transform2D:
	if text.strip_edges().is_empty():
		return Transform2D.IDENTITY
	var out := Transform2D.IDENTITY
	var cursor := 0
	while true:
		var open := text.find("(", cursor)
		if open < 0:
			break
		var close := text.find(")", open)
		if close < 0:
			break
		var name := text.substr(cursor, open - cursor).strip_edges().to_lower()
		name = name.lstrip(", \t\n")
		var values := _floats(text.substr(open + 1, close - open - 1))
		out *= _one_transform(name, values)
		cursor = close + 1
	return out


static func _one_transform(name: String, values: Array) -> Transform2D:
	match name:
		"translate":
			return Transform2D(0.0, Vector2(float(values[0]) if values.size() > 0 else 0.0,
				float(values[1]) if values.size() > 1 else 0.0))
		"scale":
			var sx: float = float(values[0]) if values.size() > 0 else 1.0
			var sy: float = float(values[1]) if values.size() > 1 else sx
			return Transform2D(Vector2(sx, 0.0), Vector2(0.0, sy), Vector2.ZERO)
		"rotate":
			var angle := deg_to_rad(float(values[0]) if values.size() > 0 else 0.0)
			if values.size() >= 3:
				var about := Vector2(float(values[1]), float(values[2]))
				return Transform2D(0.0, about) * Transform2D(angle, Vector2.ZERO) \
					* Transform2D(0.0, -about)
			return Transform2D(angle, Vector2.ZERO)
		"matrix":
			if values.size() >= 6:
				return Transform2D(
					Vector2(float(values[0]), float(values[1])),
					Vector2(float(values[2]), float(values[3])),
					Vector2(float(values[4]), float(values[5])))
	return Transform2D.IDENTITY


## Numbers out of an SVG attribute, separated by anything that is not part of one.
static func _floats(text: String) -> Array:
	var out: Array = []
	for token in _path_tokens(text):
		if _is_number(token):
			out.append(float(token))
	return out


static func _point_list(text: String) -> PackedVector2Array:
	var numbers := _floats(text)
	var out := PackedVector2Array()
	var index := 0
	while index + 1 < numbers.size():
		out.append(Vector2(float(numbers[index]), float(numbers[index + 1])))
		index += 2
	return out


## Path data as commands and numbers.
##
## Hand-written rather than a regex because SVG number syntax has two forms a split cannot handle:
## a minus sign is a separator as well as a sign (`10-5` is two numbers), and an exponent's minus
## is neither (`1e-5` is one). Both appear in real files from real drawing programs.
static func _path_tokens(text: String) -> Array:
	var out: Array = []
	var current := ""
	var index := 0
	while index < text.length():
		var character := text[index]
		if character.is_valid_int() or character == ".":
			current += character
		elif character == "-" or character == "+":
			if current.is_empty() or current.ends_with("e") or current.ends_with("E"):
				current += character
			else:
				if not current.is_empty():
					out.append(current)
				current = character
		elif character == "e" or character == "E":
			if current.is_empty():
				if not current.is_empty():
					out.append(current)
				current = ""
			else:
				current += character
		elif character == " " or character == "," or character == "\t" or character == "\n" \
				or character == "\r":
			if not current.is_empty():
				out.append(current)
			current = ""
		else:
			if not current.is_empty():
				out.append(current)
			current = ""
			out.append(character)
		index += 1
	if not current.is_empty():
		out.append(current)
	return out


static func _is_number(token: String) -> bool:
	return token.is_valid_float() or token.is_valid_int()
