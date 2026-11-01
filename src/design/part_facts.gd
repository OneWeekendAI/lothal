class_name PartFacts
extends RefCounted
## The inspector's rows for one picked address: what it is, what it weighs, where the number comes
## from and how far to trust it. Every number is read from somewhere that already exists: the
## catalog part the session has fitted (mass_g, source), the session's `Build` (wiring), the frame's
## generated `AirframeDocument` through `FrameHardware` (standoff and screw grams), or the drawn
## model's own pick shape (hole and pocket sizes, labelled as drawn). Nothing here invents a figure.
##
## Rows are [label, value] pairs; the first row is always the name.

const SLOT_CATEGORIES := {"battery": ["battery"], "camera": ["camera"],
	"stack": ["flight_controller", "esc"], "antennas": ["antenna", "vtx"], "motor": ["motor"],
	"prop": ["propeller"], "gps": ["gps"], "aio": ["flight_controller"]}
## Words in a catalog `source` that mean "a class-typical figure, not one product's".
const TYPICAL_WORDS := ["representative", "class-typical", "typical", "assumed", "estimate", "placeholder"]


## How far to trust a catalog part's numbers, from its own source line.
static func confidence(source: String) -> String:
	var s := source.to_lower()
	if s.strip_edges() == "":
		return "unknown"
	for w in TYPICAL_WORDS:
		if s.contains(w):
			return "typical (not one product)"
	return "published"


static func _short(source: String) -> String:
	var s := source.strip_edges()
	var cut := s.find(";")
	if cut > 0:
		s = s.substr(0, cut)
	return s if s.length() <= 90 else s.substr(0, 87) + "..."


## The rows for `address`. `box` is the address's model-space box (holes and pockets are sized by it).
static func rows(address: String, session: DesignSession, catalog: PartsCatalog,
		box: AABB = AABB()) -> Array:
	var out: Array = [["", PickRegistry.display_name(address)]]
	var p := address.split("/")
	if p.size() < 2:
		return out
	if p[0] == "part":
		if p[1] == "wires":
			var b := session.build(catalog)
			if b != null:
				out.append(["Mass", "%.1f g" % b.harness_mass_g()])
			out.append(["Source", "harness weighed by Build (wire gauge x length)"])
			out.append(["Confidence", "computed"])
			return out
		for cat in SLOT_CATEGORIES.get(p[1], []):
			_part_rows(out, cat, session, catalog)
		return out
	var frame := catalog.get_part(String(session.selection.get("frame", "")))
	var specs: Dictionary = frame.get("specs", {})
	match p[1]:
		"plate", "body":
			out.append(["Thickness", "%.1f mm" % float(specs.get("plate_thickness_mm", 0.0))])
			_frame_rows(out, frame)
		"arm", "arms":
			out.append(["Arm", "%.0f x %.1f mm (width x thickness)" % [
				float(specs.get("arm_width_mm", 0.0)), float(specs.get("arm_thickness_mm", 0.0))]])
			_frame_rows(out, frame)
		"pad":
			out.append(["Motor mount", String(specs.get("motor_mount", "n/a"))])
			_frame_rows(out, frame)
		"standoff", "screw":
			var doc := AirframeDocument.from_catalog_frame(frame)
			var kind := "standoff_round" if p[1] == "standoff" else "screw"
			var items := FrameHardware.standoffs(doc) if p[1] == "standoff" else FrameHardware.items_of_kind(doc, kind)
			if items.is_empty():
				out.append(["Mass", "n/a (no bolted joint in the frame document)"])
			else:
				var item: Dictionary = items[items.size() - 1]
				var g := FrameHardware.item_mass_g(item, FrameMaterials.load_default())
				out.append(["Mass", "%.2f g each" % g])
				out.append(["Material", String(item.get("material_id", "")).replace("_", " ")])
			out.append(["Source", "frame document hardware, geometry x density (FrameHardware)"])
			out.append(["Confidence", "computed"])
		"tail_mount":
			out.append(["Material", "TPU (printed)"])
			out.append(["Source", "drawn model; not in the frame's mass"])
			out.append(["Confidence", "drawn model"])
		"hole", "pocket":
			var mm := box.size * 1000.0
			var across := maxf(mm.x, mm.z)
			var narrow := minf(mm.x, mm.z)
			if p[1] == "hole":
				out.append(["Diameter", "%.1f mm" % across])
			else:
				out.append(["Size", "%.1f x %.1f mm" % [across, narrow]])
			out.append(["Through", "%.1f mm" % mm.y])
			out.append(["Source", "drawn model (tools/blender/build_drone.py)"])
			out.append(["Confidence", "drawn model, not the frame document"])
	return out


static func _part_rows(out: Array, cat: String, session: DesignSession, catalog: PartsCatalog) -> void:
	var id := String(session.selection.get(cat, ""))
	if id == "":
		return
	var part := catalog.get_part(id)
	if part.is_empty():
		return
	var src := String(part.get("source", ""))
	if out.size() > 1:
		out.append(["", ""])
	out.append(["Part", String(part.get("name", id))])
	out.append(["Mass", "%.1f g" % float(part.get("mass_g", 0.0))])
	out.append(["Source", _short(src)])
	out.append(["Confidence", confidence(src)])


static func _frame_rows(out: Array, frame: Dictionary) -> void:
	var src := String(frame.get("source", ""))
	out.append(["Frame", String(frame.get("name", ""))])
	out.append(["Frame mass", "%.1f g (whole frame)" % float(frame.get("mass_g", 0.0))])
	out.append(["Source", _short(src)])
	out.append(["Confidence", confidence(src)])
