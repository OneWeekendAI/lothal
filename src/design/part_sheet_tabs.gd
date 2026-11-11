class_name PartSheetTabs
extends RefCounted
## The tab registry of the Part sheet: which tabs a part category's sheet has, and the one place a
## tab id turns into the control that fills it. A category with no entry here has no sheet; the
## Parts drawer shows "Open sheet" only for a category this registry answers for.
##
## Tabs land one at a time as the old rooms are merged in (MERGE_TRACKER). Every category has the
## "sheet" tab (the fitted part's facts, the same rows the inspector shows), so no sheet is empty;
## the propeller "blade" (the blade designer's door and the blades drawn in the old Propulsion room),
## the frame also has "shape" (the plan editor, layouts, SVG/DXF import and the exports).

const SHEET := {"id": "sheet", "label": "Sheet"}
const SHAPE := {"id": "shape", "label": "Shape"}
const NUMBERS := {"id": "numbers", "label": "Numbers"}
const ARMS := {"id": "arms", "label": "Arms"}
const HARDWARE := {"id": "hardware", "label": "Hardware"}
const LAYOUT := {"id": "layout", "label": "Layout"}
const BENCH := {"id": "bench", "label": "Bench"}
const BLADE := {"id": "blade", "label": "Blade"}

## Category -> tab list, in tab order. Frame is a category of the sheet though not of the shelf.
const TABS := {
	"frame": [SHEET, SHAPE, NUMBERS, ARMS, HARDWARE, LAYOUT, BENCH],
	"battery": [SHEET],
	"motor": [SHEET, BENCH],
	"propeller": [SHEET, BLADE],
	"guard": [SHEET],
	"flight_controller": [SHEET],
	"esc": [SHEET, BENCH],
	"receiver": [SHEET],
	"camera": [SHEET],
	"vtx": [SHEET],
	"antenna": [SHEET],
}


## The categories the Parts drawer opens a sheet for (the shelf's ten, and the frame).
const SHELF_CATEGORIES_WITH_SHEET := ["frame", "battery", "motor", "propeller", "guard", "flight_controller", "esc", "receiver", "camera", "vtx", "antenna"]


## The tabs of `category`'s sheet ([{id, label}]); empty for a category without one.
static func for_category(category: String) -> Array:
	return (TABS.get(category, []) as Array).duplicate()


## The categories that have a sheet.
static func categories() -> Array:
	return TABS.keys()


## The part category a picked address belongs to ("" when none): frame/... is the frame; part/<slot>/...
## is the first category of that slot.
static func category_of_address(address: String) -> String:
	var p := address.split("/")
	if p.size() < 2:
		return ""
	if p[0] == "frame":
		return "frame"
	if p[0] == "part" and PartFacts.SLOT_CATEGORIES.has(p[1]):
		return String((PartFacts.SLOT_CATEGORIES[p[1]] as Array)[0])
	return ""


## The control for one tab. `ds` is the DesignSpace the sheet is open over (its session and catalog
## are what every tab reads and edits). A tab id the category does not have returns null.
static func build(category: String, tab_id: String, ds: DesignSpace, sheet: PartSheet) -> Control:
	var has := false
	for t in for_category(category):
		if String(t["id"]) == tab_id:
			has = true
	if not has:
		return null
	match tab_id:
		"sheet":
			return _facts_tab(category, ds)
		"shape":
			return FrameShapeTab.new(ds, sheet)
		"blade":
			return PropBladeTab.new(ds, sheet)
		"bench":
			return BenchTab.new(ds, {"motor": "thrust", "esc": "esc", "frame": "frame"}[category])
		"numbers", "arms", "hardware", "layout":
			return FrameFiguresTab.new(ds, tab_id)
	return null


## The fitted part's facts, as the inspector shows them.
static func _facts_tab(category: String, ds: DesignSpace) -> Control:
	var box := VBoxContainer.new()
	box.name = "FactsTab"
	box.add_theme_constant_override("separation", 6)
	var part_id := String(ds.session.selection.get(category, ""))
	var part: Dictionary = ds._catalog.get_part(part_id)
	var rows: Array = [["Part", String(part.get("name", part_id))],
		["Mass", "%.1f g" % float(part.get("mass_g", 0.0))] if part.has("mass_g") else ["", ""]]
	var source := String(part.get("source", ""))
	if source != "":
		rows.append(["Source", source])
		rows.append(["Trust", PartFacts.confidence(source)])
	for r in rows:
		if String(r[0]) == "":
			continue
		var l := DsUi.label("%s: %s" % [r[0], r[1]], DsUi.INK if String(r[0]) in ["Part", "Mass"] else DsUi.INK_MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(l)
	return box
