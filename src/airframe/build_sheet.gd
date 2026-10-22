class_name BuildSheet
extends RefCounted
## The build sheet — airframe gaps G6 and airframe.md §7.5: one printable page that says what to cut,
## what to buy and in what order to put it together, read straight off the document.
##
## ## A pure function, in two layers
##
## `compose` turns a document into plain data (rows and lines); `to_html` turns that data into a page.
## Nothing on the page is typed: plate quantities are `FrameExport.plate_notes`' (the same count the
## DXF notes print), screws and standoffs are `FrameHardware`'s items counted, masses are
## `AirframeProperties` and `FrameHardware.mass_g`, the cutting cost is `CutCost`. So the sheet cannot
## disagree with the cut files or the numbers strip — it is the same computation printed.
##
## ## Why HTML
##
## The cut sheets are SVG because they are drawings printed at 1:1. This is a list — tables of parts and
## a numbered procedure — and HTML is the format every machine prints a table from without a layout
## engine of our own. It is self-contained (inline style, no scripts, no external files) so it opens
## and prints offline.
##
## ## What appears only when it is there
##
## Strap slots and pads, and the camera cage, have sections only when the document has them — a sheet
## that lists "Camera cage: none" on every frame is a line a builder learns to skip, and then skips the
## one time it matters. The assembly order is generated the same way: a step per thing present.

const KIND_LABELS := {
	"standoff_round": "Round standoff",
	"standoff_hex": "Hex standoff",
}


## Everything the sheet shows, as data. Keys:
##   name, plates: [{labels, role, thickness_mm, material, quantity, size_mm (Vector2)}],
##   screws: [{thread_d_mm, length_mm, material, count}],
##   standoffs: [{kind, length_mm, section, material, count}],
##   strap: {} or {plate_label, slots: [{length_mm, width_mm, count}], straps: int, strap_mass_g},
##   pads: [{thickness_mm, material, area_mm2}],
##   cage: {} or {plate_count, spacing_mm, camera_width_mm, thickness_mm},
##   mass: {total_g, hardware_g, typed_strap_g},
##   assembly: PackedStringArray,
##   cost: CutCost.estimate
static func compose(document: AirframeDocument, rates: Dictionary = {}) -> Dictionary:
	var out := {"name": "", "plates": [], "screws": [], "standoffs": [], "strap": {}, "pads": [],
		"cage": {}, "mass": {"total_g": 0.0, "hardware_g": 0.0, "typed_strap_g": 0.0},
		"assembly": PackedStringArray(), "cost": CutCost.estimate(document, rates)}
	if document == null:
		return out
	var materials := FrameMaterials.load_default()
	out["name"] = document.name
	out["plates"] = _plate_rows(document)
	out["screws"] = _screw_rows(document, materials)
	out["standoffs"] = _standoff_rows(document, materials)
	out["strap"] = _strap_section(document)
	out["pads"] = _pad_rows(document, materials)
	out["cage"] = _cage_section(document)
	var typed_strap := 0.0
	for strap in document.straps:
		typed_strap += float(strap.get("mass_g", 0.0))
	out["mass"] = {
		"total_g": AirframeProperties.compute(document, materials).total_mass_g(),
		"hardware_g": FrameHardware.mass_g(document, materials),
		"typed_strap_g": typed_strap,
	}
	out["assembly"] = assembly_order(document)
	return out


# ---------------------------------------------------------------------------
# Rows
# ---------------------------------------------------------------------------

## One row per distinct part, with how many of it — `FrameExport.plate_notes`' quantity, so this and
## the DXF's "qty 1 of 4 identical" are one count.
static func _plate_rows(document: AirframeDocument) -> Array:
	var rows: Array = []
	var row_of: Dictionary = {}
	for note in FrameExport.plate_notes(document):
		var plate: Dictionary = note["plate"]
		var signature := FrameExport.part_signature(document, plate)
		if row_of.has(signature):
			var labels: PackedStringArray = rows[row_of[signature]]["labels"]
			labels.append("%d" % (int(note["index"]) + 1))
			rows[row_of[signature]]["labels"] = labels  # A packed array is a value: write it back.
			continue
		var outline := AirframeDocument.plate_outline(plate)
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for p in outline:
			low = low.min(p)
			high = high.max(p)
		row_of[signature] = rows.size()
		var role := str(note["role"])
		if AirframeDocument.is_upright(plate):
			role += " (upright, cut flat)"
		rows.append({"labels": PackedStringArray(["%d" % (int(note["index"]) + 1)]),
			"role": role, "thickness_mm": float(note["thickness_mm"]),
			"material": str(note["material"]), "quantity": int(note["quantity"]),
			"size_mm": (high - low) if outline.size() >= 3 else Vector2.ZERO})
	return rows


## Screws grouped by thread, length and material, in the order each group first appears.
static func _screw_rows(document: AirframeDocument, materials: FrameMaterials) -> Array:
	var rows: Array = []
	var row_of: Dictionary = {}
	for item in FrameHardware.items_of_kind(document, "screw"):
		var thread := float(item.get("thread_d_mm", 0.0))
		var length := float(item.get("shank_len_mm", 0.0))
		var material := _material_name(materials, str(item.get("material_id", "")))
		var key := "%.2f|%.2f|%s" % [thread, length, material]
		if not row_of.has(key):
			row_of[key] = rows.size()
			rows.append({"thread_d_mm": thread, "length_mm": length, "material": material,
				"count": 0})
		rows[row_of[key]]["count"] = int(rows[row_of[key]]["count"]) + 1
	return rows


## Standoffs grouped by kind, length, section and material.
static func _standoff_rows(document: AirframeDocument, materials: FrameMaterials) -> Array:
	var rows: Array = []
	var row_of: Dictionary = {}
	for item in FrameHardware.standoffs(document):
		var kind := str(item.get("kind", ""))
		var length := float(item.get("length_mm", 0.0))
		var section := ("Ø%s mm" % _trim(float(item.get("outer_d_mm", 0.0)))) if kind == "standoff_round" \
			else ("%s mm A/F" % _trim(float(item.get("across_flats_mm", 0.0))))
		var material := _material_name(materials, str(item.get("material_id", "")))
		var key := "%s|%.2f|%s|%s" % [kind, length, section, material]
		if not row_of.has(key):
			row_of[key] = rows.size()
			rows.append({"kind": kind, "length_mm": length, "section": section,
				"material": material, "count": 0})
		rows[row_of[key]]["count"] = int(rows[row_of[key]]["count"]) + 1
	return rows


## The strap slots (on flat plates — a cage's tilt slot is not a strap slot) and any straps the
## document carries. `{}` when there are neither.
static func _strap_section(document: AirframeDocument) -> Dictionary:
	var slots: Array = []
	var labels := PackedStringArray()
	for index in document.plates.size():
		var plate: Dictionary = document.plates[index]
		if AirframeDocument.is_upright(plate):
			continue
		var found := StrapSlots.slots(plate)
		if found.is_empty():
			continue
		labels.append(ReadyToCut.plate_label(document, index))
		for shape in found:
			var length := float(shape["length_mm"])
			var width := float(shape["width_mm"])
			var matched := false
			for row in slots:
				if absf(float(row["length_mm"]) - length) < 0.05 and absf(float(row["width_mm"]) - width) < 0.05:
					row["count"] = int(row["count"]) + 1
					matched = true
					break
			if not matched:
				slots.append({"length_mm": length, "width_mm": width, "count": 1})
	if slots.is_empty() and document.straps.is_empty():
		return {}
	var strap_mass := 0.0
	for strap in document.straps:
		strap_mass += float(strap.get("mass_g", 0.0))
	return {"plate_label": ", ".join(labels), "slots": slots, "straps": document.straps.size(),
		"strap_mass_g": strap_mass}


static func _pad_rows(document: AirframeDocument, materials: FrameMaterials) -> Array:
	var rows: Array = []
	for pad in document.pads:
		var region := PolygonProps.region_properties(AirframeDocument.plate_outline(pad),
			AirframeDocument.plate_holes(pad))
		rows.append({"thickness_mm": AirframeDocument.plate_thickness_mm(pad),
			"material": _material_name(materials,
				str(pad.get("material_id", AirframeProperties.PAD_DEFAULT_MATERIAL_ID))),
			"area_mm2": absf(float(region.get("area", 0.0)))})
	return rows


## The camera cage, `{}` when the document has no upright plate.
static func _cage_section(document: AirframeDocument) -> Dictionary:
	var count := 0
	var width := 0.0
	var thickness := 0.0
	for plate in document.plates:
		if not AirframeDocument.is_upright(plate):
			continue
		count += 1
		width = maxf(width, float(plate.get(CameraCage.PLATE_CAGE_WIDTH, 0.0)))
		thickness = AirframeDocument.plate_thickness_mm(plate)
	if count == 0:
		return {}
	return {"plate_count": count, "spacing_mm": CameraCage.spacing_mm(document),
		"camera_width_mm": width, "thickness_mm": thickness}


# ---------------------------------------------------------------------------
# Assembly order
# ---------------------------------------------------------------------------

## The order a builder puts this frame together in, a step per thing the document has: bottom plate →
## arms → standoffs → stack → top plate → camera cage → strap. Empty for a document with nothing in it.
static func assembly_order(document: AirframeDocument) -> PackedStringArray:
	var steps := PackedStringArray()
	if document == null:
		return steps
	var by_role := {}
	for index in document.plates.size():
		var plate: Dictionary = document.plates[index]
		var role := "upright" if AirframeDocument.is_upright(plate) else str(plate.get("role", ""))
		var numbers: PackedStringArray = by_role.get(role, PackedStringArray())
		numbers.append("%d" % (index + 1))
		by_role[role] = numbers  # A packed array is a value: write it back.

	if by_role.has(AirframeDocument.ROLE_BOTTOM):
		steps.append("Lay the bottom plate (%s) face down." % _plates_text(by_role[AirframeDocument.ROLE_BOTTOM]))
	if by_role.has(AirframeDocument.ROLE_ARM):
		var arms: PackedStringArray = by_role[AirframeDocument.ROLE_ARM]
		steps.append("Seat the %d arm%s (%s) on %s." % [arms.size(), "" if arms.size() == 1 else "s",
			_plates_text(arms), "the bottom plate" if by_role.has(AirframeDocument.ROLE_BOTTOM)
				else "the frame"])
	if by_role.has(AirframeDocument.ROLE_MID):
		steps.append("Fit the mid plate (%s)." % _plates_text(by_role[AirframeDocument.ROLE_MID]))
	var standoffs := FrameHardware.standoffs(document)
	if not standoffs.is_empty():
		var lengths := PackedStringArray()
		for item in standoffs:
			var text := "%s mm" % _trim(float(item.get("length_mm", 0.0)))
			if not lengths.has(text):
				lengths.append(text)
		steps.append("Screw in the %d standoff%s (%s), clamping the arms." % [standoffs.size(),
			"" if standoffs.size() == 1 else "s", ", ".join(lengths)])
	if _has_stack(document):
		steps.append("Mount the flight stack on its holes, soft-mount grommets in.")
	if by_role.has(AirframeDocument.ROLE_TOP):
		steps.append("Close with the top plate (%s) and its screws." % _plates_text(by_role[AirframeDocument.ROLE_TOP]))
	if by_role.has("upright"):
		steps.append("Fit the camera between the side plates (%s): pivot screw first, then the screw in the tilt slot; set the tilt and tighten." % _plates_text(by_role["upright"]))
	var strap := _strap_section(document)
	if not strap.is_empty() or not document.pads.is_empty():
		var what := "Thread the battery strap through the strap slots"
		if not strap.is_empty() and not str(strap["plate_label"]).is_empty():
			what += " in %s" % strap["plate_label"]
		if strap.is_empty():
			what = "Fit the battery strap"
		if not document.pads.is_empty():
			what += ", with the pad under the pack"
		steps.append(what + ".")
	return steps


## Whether the document carries a stack: a "stack" payload mount, or four bolt holes on one flat
## centre plate (a drawn frame with "+ Stack mount" and no generator).
static func _has_stack(document: AirframeDocument) -> bool:
	for mount in document.payload_mounts:
		if str(mount.get("id", "")) == "stack":
			return true
	for plate in document.plates:
		if AirframeDocument.is_upright(plate) or str(plate.get("role", "")) == AirframeDocument.ROLE_ARM:
			continue
		var bolt_holes := 0
		for hole in AirframeDocument.plate_holes(plate):
			if FrameHardware.bolt_hole_thread_mm(hole) > 0.0:
				bolt_holes += 1
		if bolt_holes >= 4:
			return true
	return false


static func _plates_text(numbers: PackedStringArray) -> String:
	return ("plate " if numbers.size() == 1 else "plates ") + ", ".join(numbers)


# ---------------------------------------------------------------------------
# HTML
# ---------------------------------------------------------------------------

## The printable page.
static func to_html(document: AirframeDocument, rates: Dictionary = {}) -> String:
	var sheet := compose(document, rates)
	var o := PackedStringArray()
	o.append("<!doctype html>")
	o.append('<html lang="en"><head><meta charset="utf-8">')
	o.append('<meta name="viewport" content="width=device-width, initial-scale=1">')
	o.append("<title>%s — build sheet</title>" % _esc(str(sheet["name"])))
	o.append("<style>" +
		"body{font:14px/1.45 -apple-system,'Segoe UI',Helvetica,Arial,sans-serif;color:#111;background:#fff;" +
		"max-width:820px;margin:24px auto;padding:0 16px}" +
		"h1{font-size:22px;margin:0 0 4px}h2{font-size:15px;margin:22px 0 6px;border-bottom:1px solid #999}" +
		"table{border-collapse:collapse;width:100%}th,td{text-align:left;padding:3px 8px 3px 0;" +
		"border-bottom:1px solid #ddd;vertical-align:top}th{font-weight:600}" +
		"td.n,th.n{text-align:right;font-variant-numeric:tabular-nums}.muted{color:#555}" +
		".tier{font-size:12px;color:#7a4b00}ol{padding-left:22px}" +
		"@media print{body{margin:0}h2{break-after:avoid}table{break-inside:avoid}}" +
		"</style></head><body>")
	o.append("<h1>%s</h1>" % _esc(str(sheet["name"])))
	o.append('<p class="muted">Build sheet. Millimetres. Every count and mass below is computed from the frame document, not typed.</p>')

	o.append("<h2 id=\"plates\">Plates to cut</h2>")
	o.append("<table><tr><th>Plate</th><th>Role</th><th class=\"n\">Thickness</th><th>Material</th>" +
		"<th class=\"n\">Qty</th><th class=\"n\">Size</th></tr>")
	for row in sheet["plates"]:
		var size: Vector2 = row["size_mm"]
		o.append("<tr><td>%s</td><td>%s</td><td class=\"n\">%.1f mm</td><td>%s</td><td class=\"n\">%d</td><td class=\"n\">%.1f × %.1f mm</td></tr>" % [
			_esc(", ".join(row["labels"])), _esc(str(row["role"])), float(row["thickness_mm"]),
			_esc(str(row["material"])), int(row["quantity"]), size.x, size.y])
	o.append("</table>")

	o.append("<h2 id=\"hardware\">Hardware</h2>")
	if (sheet["screws"] as Array).is_empty() and (sheet["standoffs"] as Array).is_empty():
		o.append('<p class="muted">No screws or standoffs in this frame.</p>')
	else:
		o.append("<table><tr><th>Item</th><th>Material</th><th class=\"n\">Qty</th></tr>")
		for row in sheet["screws"]:
			o.append("<tr><td>%s</td><td>%s</td><td class=\"n\">%d</td></tr>" % [
				_esc(screw_label(row)), _esc(str(row["material"])), int(row["count"])])
		for row in sheet["standoffs"]:
			o.append("<tr><td>%s</td><td>%s</td><td class=\"n\">%d</td></tr>" % [
				_esc(standoff_label(row)), _esc(str(row["material"])), int(row["count"])])
		o.append("</table>")

	var strap: Dictionary = sheet["strap"]
	if not strap.is_empty() or not (sheet["pads"] as Array).is_empty():
		o.append("<h2 id=\"straps\">Strap slots and pads</h2><ul>")
		if not strap.is_empty():
			for slot in strap["slots"]:
				o.append("<li>%d strap slot%s %.1f × %.1f mm in %s</li>" % [int(slot["count"]),
					"" if int(slot["count"]) == 1 else "s", float(slot["length_mm"]),
					float(slot["width_mm"]), _esc(str(strap["plate_label"]))])
			if int(strap["straps"]) > 0:
				o.append("<li>%d strap%s, %.1f g (published figure)</li>" % [int(strap["straps"]),
					"" if int(strap["straps"]) == 1 else "s", float(strap["strap_mass_g"])])
		for pad in sheet["pads"]:
			o.append("<li id=\"pad\">Pad: %s, %.1f mm thick, %.0f mm²</li>" % [_esc(str(pad["material"])),
				float(pad["thickness_mm"]), float(pad["area_mm2"])])
		o.append("</ul>")

	var cage: Dictionary = sheet["cage"]
	if not cage.is_empty():
		o.append("<h2 id=\"cage\">Camera cage</h2><ul>")
		o.append("<li>%d upright side plates, %.1f mm stock, cut flat</li>" % [int(cage["plate_count"]),
			float(cage["thickness_mm"])])
		if float(cage["spacing_mm"]) > 0.0:
			o.append("<li>%.1f mm clear between the plates%s</li>" % [float(cage["spacing_mm"]),
				(" (cut for a %s mm camera)" % _trim(float(cage["camera_width_mm"])))
					if float(cage["camera_width_mm"]) > 0.0 else ""])
		o.append("<li>M%s pivot and tilt-slot screws, 0–%d° uptilt</li>" % [
			_trim(CameraCage.SCREW_D_MM), int(CameraCage.TILT_MAX_DEG)])
		o.append("</ul>")

	var mass: Dictionary = sheet["mass"]
	o.append("<h2 id=\"mass\">Mass</h2><table>")
	o.append("<tr><td>Frame, as drawn</td><td class=\"n\">%.1f g</td></tr>" % float(mass["total_g"]))
	o.append("<tr><td class=\"muted\">of which hardware (screws, standoffs)</td><td class=\"n\">%.1f g</td></tr>" % float(mass["hardware_g"]))
	if float(mass["typed_strap_g"]) > 0.0:
		o.append("<tr><td class=\"muted\">of which straps (published figure)</td><td class=\"n\">%.1f g</td></tr>" % float(mass["typed_strap_g"]))
	o.append("</table>")

	var steps: PackedStringArray = sheet["assembly"]
	if not steps.is_empty():
		o.append("<h2 id=\"assembly\">Assembly order</h2><ol>")
		for step in steps:
			o.append("<li>%s</li>" % _esc(step))
		o.append("</ol>")

	var cost: Dictionary = sheet["cost"]
	o.append("<h2 id=\"cost\">Cutting cost estimate</h2>")
	if not bool(cost["ok"]):
		o.append('<p class="muted">Nothing to price.</p>')
	else:
		o.append("<p><strong>%s</strong> <span class=\"tier\">%s</span></p>" % [
			_esc(CutCost.range_text(cost)), _esc(str(cost["tier_label"]))])
		o.append("<table><tr><th>Stock</th><th class=\"n\">Parts</th><th class=\"n\">Nest</th>" +
			"<th class=\"n\">Area</th><th class=\"n\">Sheet</th></tr>")
		var symbol := str(cost["symbol"])
		var materials := FrameMaterials.load_default()
		for stock in cost["stocks"]:
			var nest: Vector2 = stock["nest_mm"]
			o.append("<tr><td>%.1f mm %s</td><td class=\"n\">%d</td><td class=\"n\">%.0f × %.0f mm</td><td class=\"n\">%.0f cm²</td><td class=\"n\">%s</td></tr>" % [
				float(stock["thickness_mm"]), _esc(_material_name(materials, str(stock["material_id"]))),
				int(stock["plate_count"]), nest.x, nest.y, float(stock["area_cm2"]),
				_esc(_money_range(symbol, float(stock["low"]), float(stock["high"])))])
		o.append("<tr><td>Cutting, %.2f m of outline and holes</td><td></td><td></td><td></td><td class=\"n\">%s</td></tr>" % [
			float(cost["cut_length_m"]), _esc(_money_range(symbol, float(cost["cut_low"]),
				float(cost["cut_high"])))])
		o.append("</table>")
		o.append(('<p class="tier">Sheet priced from the bounding area of each stock\'s nest (parts at the angle ' +
			'they were drawn), at %s rates, plus every cut\'s length. These are %s: change ' +
			'data/cut_rates.json to your shop\'s figures. Pads are printed and not priced.</p>') % [
			_esc(str(cost["priced_as"])), _esc(str(cost["tier_label"]))])
	o.append("</body></html>")
	return "\n".join(o) + "\n"


## "M3 × 8 mm screw".
static func screw_label(row: Dictionary) -> String:
	return "M%s × %s mm screw" % [_trim(float(row["thread_d_mm"])), _trim(float(row["length_mm"]))]


## "Round standoff Ø5.5 mm × 25 mm".
static func standoff_label(row: Dictionary) -> String:
	return "%s %s × %s mm" % [str(KIND_LABELS.get(str(row["kind"]), "Standoff")), str(row["section"]),
		_trim(float(row["length_mm"]))]


static func _money_range(symbol: String, low: float, high: float) -> String:
	return "%s%.2f–%s%.2f" % [symbol, low, symbol, high]


static func _material_name(materials: FrameMaterials, material_id: String) -> String:
	var record: Dictionary = materials.get_material(material_id)
	return str(record.get("name", material_id)) if not record.is_empty() else material_id


static func _trim(value: float) -> String:
	var text := "%.1f" % value
	return text.trim_suffix(".0")


static func _esc(text: String) -> String:
	return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")
