class_name DesignBuildSheet
extends RefCounted
## THE DESIGN SPACE'S BUILD SHEET — "Export build sheet…" in the drone menu. One Markdown file a builder can
## print or send, in the format `ConfigSheet` and `PackSheet` already write (a dated Markdown file with a
## deterministic body; the date is one line of its own).
##
## It arranges and never recomputes. Every figure is read off the session's `Build` at the moment of writing:
## the five readouts through `DesignSession.readouts_of` and printed by `DesignSpace.format_readout` (the very
## function the readout panel prints with, so the sheet's Weight line is the panel's Weight line character for
## character), the warnings through `Build.warnings()` verbatim, the harness through `Harness`'s own accessors.
## The "(est.)" labels are the panel's: "Flight (est.)" and "Top speed (est.)".
##
## The parts table is the grouped `Build.mass_parts()` and its total is the SUM of its rows; nothing is derived by
## subtraction, so the total agreeing with the Weight readout is a check and not a construction.

const EXTENSION := "md"
## The readouts in the panel's order, with the panel's own captions.
const FIGURES := [["auw_g", "Weight"], ["thrust_to_weight", "Thrust : weight"], ["hover_throttle", "Hover"],
	["flight_time_min", "Flight (est.)"], ["top_speed_kmh", "Top speed (est.)"]]


## "<project> build sheet.md", safe on a disk.
static func default_name(project_name: String) -> String:
	var shown := project_name.strip_edges()
	if shown == "":
		shown = "Untitled"
	for bad in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		shown = shown.replace(bad, "_")
	return "%s build sheet.%s" % [shown, EXTENSION]


## The parts table as data: [{category, name, qty, mass_g, source}], grouped from `Build.mass_parts()` — the very
## list `MassProperties.compute` turns into the all-up weight and the inertia. Nothing is derived by subtraction:
## every entry of that list lands in exactly one row, so the rows' sum is the all-up weight by the model's own
## bookkeeping and a dropped or double-counted entry shows up as a total that disagrees with the Weight readout.
static func part_rows(session: DesignSession, catalog: PartsCatalog, b: Build) -> Array:
	var names := {}
	for category in ProjectSchema.all_categories():
		var part := catalog.get_part(String(session.selection.get(category, "")))
		if not part.is_empty():
			names[category] = [String(part.get("name", "")), source_of(String(session.selection[category]), part)]
	var component_labels := {}
	for category in Build.OPTIONAL_COMPONENTS:
		if b.components.has(category):
			component_labels[str((b.components[category] as Dictionary).get("name", category))] = category
	# Row order is the order of first appearance in this table.
	var order := ["motor", "frame", "frame_edit", "battery", "flight_controller", "esc", "camera", "vtx",
		"antenna", "receiver", "gps", "buzzer", "h_wires", "h_connector", "h_capacitor", "h_straps", "h_sundries", "soft_mounts", "guard", "payload", "other"]
	var grams := {}
	var counts := {}
	for part in b.mass_parts():
		var label := String(part.label)
		var key := "other"
		if label.begins_with("Motor + prop"):
			key = "motor"
		elif label == "Frame":
			key = "frame"
		elif label == "Pack":
			key = "battery"
		elif label == "Flight controller":
			key = "flight_controller"
		elif label == "ESC":
			key = "esc"
		elif component_labels.has(label):
			key = component_labels[label]
		elif label.begins_with("Payload"):
			key = "payload"
		elif label == "Connector":
			key = "h_connector"
		elif label == "Main lead" or label.begins_with("Motor lead"):
			key = "h_wires"
		elif label == "Capacitor":
			key = "h_capacitor"
		elif label == "Battery straps":
			key = "h_straps"
		elif label == "Harness remainder":
			key = "h_sundries"
		elif label.begins_with("Soft mount"):
			key = "soft_mounts"
		elif label == "prop_guard":
			key = "guard"
		grams[key] = float(grams.get(key, 0.0)) + part.mass_kg * 1000.0
		counts[key] = int(counts.get(key, 0)) + 1
	# Frame edits: the flown frame mass is the published mass plus the drawing's delta; show the delta apart.
	var edit := session.frame_edit(catalog)
	if not edit.is_empty() and grams.has("frame"):
		var delta := float(edit.get("drawn_delta_g", 0.0))
		grams["frame"] = float(grams["frame"]) - delta
		grams["frame_edit"] = delta
	var rows: Array = []
	for key in order:
		if not grams.has(key):
			continue
		var row := {"category": key, "name": "", "qty": 1, "mass_g": float(grams[key]), "source": "catalog"}
		match key:
			"motor":
				var prop: String = (names["propeller"][0] if names.has("propeller") else "")
				row["category"] = "motor + propeller"
				row["name"] = "%s + %s" % [names["motor"][0] if names.has("motor") else "", prop]
				row["qty"] = int(counts[key])
				row["source"] = names["motor"][1] if names.has("motor") else "catalog"
			"frame", "battery", "flight_controller", "esc":
				var cat: String = key
				row["name"] = names[cat][0] if names.has(cat) else String(b.frame.get("name", ""))
				row["source"] = names[cat][1] if names.has(cat) else "catalog"
				row["category"] = {"frame": "frame", "battery": "battery", "flight_controller": "flight controller",
					"esc": "esc"}[key]
			"frame_edit":
				row["category"] = "frame edits"
				row["name"] = "Drawn holes and pockets (mass change vs the published frame)"
				row["source"] = "custom"
			"h_wires":
				row["category"] = "wiring"
				row["name"] = "Main lead and motor leads (wire by gauge and length)"
				row["source"] = "est."
			"h_connector":
				row["category"] = "connector"
				row["name"] = _row_name(b.harness.connector_row(b))
				row["source"] = _harness_source(b.harness.connector_row(b))
			"h_capacitor":
				row["category"] = "capacitor"
				row["name"] = _row_name(b.harness.capacitor_row(b))
				row["source"] = _harness_source(b.harness.capacitor_row(b))
			"h_straps":
				row["category"] = "straps"
				row["name"] = _row_name(b.harness.strap_row(b))
				row["qty"] = b.harness.strap_count(b)
				row["source"] = _harness_source(b.harness.strap_row(b))
			"h_sundries":
				row["category"] = "sundries"
				if b.harness.straps_authored():
					row["name"] = "Solder, heat-shrink, tape, zip ties"
				else:
					row["name"] = "Default strap + solder, heat-shrink, tape, zip ties"
				row["source"] = "est."
			"soft_mounts":
				row["category"] = "soft mounts"
				row["name"] = "Motor soft mounts"
				row["qty"] = int(counts[key])
				row["source"] = "est."
			"guard":
				row["category"] = "prop guard"
				row["name"] = names["guard"][0] if names.has("guard") else "Prop guard"
				row["qty"] = int(counts[key])
			"payload":
				row["category"] = "payload"
				row["name"] = String(b.payload_part.get("kind", "payload")) if b.payload_part_mass_g() > 0.0 else "Payload"
				row["source"] = "custom"
			"other":
				row["category"] = "other"
				row["name"] = "Printed parts and anything else the mass model carries"
				row["source"] = "est."
			_:
				row["name"] = names[key][0] if names.has(key) else key
				row["source"] = names[key][1] if names.has(key) else "catalog"
				row["category"] = key
		rows.append(row)
	return rows


static func _harness_source(part: Dictionary) -> String:
	return "custom" if PartsCatalog.is_custom(String(part.get("part_id", ""))) else "catalog"


static func source_of(id: String, _part: Dictionary) -> String:
	if PartsCatalog.is_custom(id):
		return "custom"
	return "catalog"


static func compose(session: DesignSession, catalog: PartsCatalog, project_name: String, date: String) -> String:
	var b := session.build(catalog)
	if b == null:
		return ""
	var out := PackedStringArray()
	var entry := DroneClass.by_id(session.drone_class)
	var shown := project_name.strip_edges() if project_name.strip_edges() != "" else "Untitled"
	out.append("# Build sheet — %s" % shown)
	out.append("")
	out.append("- Class: %s" % String(entry.get("name", session.drone_class)))
	out.append("- Date: %s" % date)
	out.append("- Lothal version: %s" % LothalVersion.CURRENT)

	var r := DesignSession.readouts_of(b)
	r["can_hover"] = b.can_hover()

	out.append("")
	out.append("## Parts")
	out.append("")
	out.append("| Category | Part | Qty | Mass | Source |")
	out.append("|---|---|---|---|---|")
	var listed := 0.0
	for row in part_rows(session, catalog, b):
		listed += float(row["mass_g"])
		out.append("| %s | %s | %d | %.1f g | %s |" % [row["category"], row["name"], row["qty"],
			float(row["mass_g"]), row["source"]])
	out.append("| **Total** | | | **%.1f g** | |" % listed)

	out.append("")
	out.append("## Key figures")
	out.append("")
	for figure in FIGURES:
		out.append("- %s: %s" % [figure[1], DesignSpace.format_readout(String(figure[0]), r)])
	out.append("- Current cap: %s" % _current_cap(b))

	out.append("")
	out.append("## Warnings")
	out.append("")
	var warnings := b.warnings()
	if warnings.is_empty():
		out.append("None flagged.")
	for warning in warnings:
		out.append("- [%s] %s" % [BuildWarning.severity_name(warning.severity), warning.message])

	out.append("")
	out.append("## Frame")
	out.append("")
	out.append("- Frame: %s" % String(b.frame.get("name", "")))
	var edit := session.frame_edit(catalog)
	if edit.is_empty():
		out.append("- Edits: none")
	else:
		var doc := session.frame_document()
		var holes := 0
		if doc != null:
			for plate in doc.plates:
				holes += ((plate as Dictionary).get("holes", []) as Array).size()
		out.append("- Edits: %d holes and pockets in the drawing; mass %+.1f g against the published frame" % [
			holes, float(edit.get("drawn_delta_g", 0.0))])
	out.append("- Payload: %.1f g, %.0f mm fore of the attach point" % [
		b.total_payload_mass_g(), b.payload_fore_m() * 1000.0] if b.total_payload_mass_g() > 0.0
		else "- Payload: none")

	out.append("")
	out.append("## Harness")
	out.append("")
	var h := b.harness
	out.append("- Connector: %s" % _row_name(h.connector_row(b)))
	out.append("- Capacitor: %s" % _row_name(h.capacitor_row(b)))
	out.append("- Straps: %s x %d" % [_row_name(h.strap_row(b)), h.strap_count(b)])
	out.append("- Harness mass: %.1f g" % h.total_mass_g(b))
	out.append("")
	return "\n".join(out)


static func write(session: DesignSession, catalog: PartsCatalog, project_name: String, path: String,
		date: String) -> bool:
	var text := compose(session, catalog, project_name, date)
	if text == "":
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


static func _row_name(row: Dictionary) -> String:
	return String(row.get("name", "none")) if not row.is_empty() else "none"


## The limiting component and its throttle ceiling, as `Build.limiting_component` states them.
static func _current_cap(b: Build) -> String:
	var limit := b.limiting_component()
	return "%s, %.0f A, %.0f %% throttle" % [limit["label"], float(limit["amps"]),
		float(limit["throttle"]) * 100.0]
